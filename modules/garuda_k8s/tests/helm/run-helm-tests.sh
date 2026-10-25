#!/usr/bin/env bash
# Helm-level tests for modules/garuda_k8s.
# Runs `helm lint` and `helm template` for both bundled charts:
#   * garuda      — NetworkAttachmentDefinitions + network-meta ConfigMap.
#   * garuda-cni  — vendored Multus DaemonSet, gated by
#                   installCni for the operator-already-installed case.
#
# Scenarios diffed against tests/golden/*.yaml:
#   * garuda.yaml             — main chart, sole rendering (no toggles).
#   * garuda-cni-default.yaml — garuda-cni with installCni=true.
#   * garuda-cni-disabled.yaml — garuda-cni with installCni=false (empty render).
#
# Update goldens: REGEN_GOLDEN=1 ./run-helm-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/../.."
GARUDA_CHART="${MODULE_DIR}/charts/garuda"
CNI_CHART="${MODULE_DIR}/charts/garuda-cni"
GOLDEN_DIR="${SCRIPT_DIR}/../golden"

helm lint "${GARUDA_CHART}" \
  --set backboneSubnet=10.42.0.0/24 \
  --set borderSubnet=10.43.0.0/24 \
  --set borderGateway=10.43.0.1 \
  --set borderRangeStart=10.43.0.2

helm lint "${CNI_CHART}" \
  --set installCni=true

render_garuda() {
  helm template g "${GARUDA_CHART}" \
    --namespace garuda \
    --set backboneSubnet=10.42.0.0/24 \
    --set borderSubnet=10.43.0.0/24 \
    --set borderGateway=10.43.0.1 \
    --set borderRangeStart=10.43.0.2
}

render_garuda_layers_off() {
  helm template g "${GARUDA_CHART}" \
    --namespace garuda \
    --set backboneSubnet=10.42.0.0/24 \
    --set borderSubnet=10.43.0.0/24 \
    --set borderGateway=10.43.0.1 \
    --set borderRangeStart=10.43.0.2 \
    --set multusReadiness.enabled=false \
    --set podReaper.enabled=false
}

render_cni() {
  local install="$1"
  helm template g "${CNI_CHART}" \
    --namespace garuda \
    --set installCni="${install}"
}

declare -A renders
renders["garuda"]="$(render_garuda)"
renders["garuda-cni-default"]="$(render_cni true)"
renders["garuda-cni-disabled"]="$(render_cni false)"
renders["garuda-layers-off"]="$(render_garuda_layers_off)"

cni_render="${renders["garuda-cni-default"]}"
for expected in \
  'mountPath: /opt/cni/bin' \
  'path: /var/lib/rancher/k3s/data' \
  '"binDir": "/var/lib/rancher/k3s/data/cni"' \
  'image: "rancher/hardened-multus-thick:v4.2.4-build20260310"'; do
  if [[ "${cni_render}" != *"${expected}"* ]]; then
    echo "garuda-cni-default missing expected CNI setting: ${expected}" >&2
    exit 1
  fi
done

garuda_render="${renders["garuda"]}"
for expected in \
  '"type": "host-local"' \
  '"dataDir": "/var/run/cni/backbone"' \
  '"subnet": "10.42.0.0/24"' \
  '"dataDir": "/var/run/cni/border"' \
  '"subnet": "10.43.0.0/24"' \
  '"rangeStart": "10.43.0.2"' \
  '"gateway": "10.43.0.1"'; do
  if [[ "${garuda_render}" != *"${expected}"* ]]; then
    echo "garuda missing expected host-local setting: ${expected}" >&2
    exit 1
  fi
done

# Pod reaper only reaps pods whose containers started and failed (never pods
# that have no sandbox yet), and Helm hook pods must stay outside its
# part-of=garuda scope. See issue #179.
for expected in \
  'name: CONTAINER_STATUSES' \
  'value: "CrashLoopBackOff,Error,StartError,CreateContainerError"'; do
  if [[ "${garuda_render}" != *"${expected}"* ]]; then
    echo "garuda missing expected pod-reaper setting: ${expected}" >&2
    exit 1
  fi
done
# The hook pod template's labels block: anchored at `kind: Job` → `template:`
# → `labels:` so a label placed above `name: multus-readiness` is caught too.
hook_pod_labels="$(printf '%s\n' "${garuda_render}" | awk '
  /kind: Job$/ {job=1}
  job && /^  template:$/ {in_tpl=1}
  in_tpl && /^      labels:$/ {in_lbl=1; next}
  in_lbl && /^        / {print; next}
  in_lbl {exit}')"
if [[ "${hook_pod_labels}" != *"name: multus-readiness"* || "${hook_pod_labels}" == *"app.kubernetes.io/part-of"* ]]; then
  echo "multus-ready hook pod must not carry app.kubernetes.io/part-of (pod reaper scope)" >&2
  exit 1
fi

# Negative assertion: an empty podReaper.containerStatuses would silently
# disable the reaper; the values schema must reject it.
if helm template g "${GARUDA_CHART}" \
  --namespace garuda \
  --set backboneSubnet=10.42.0.0/24 \
  --set borderSubnet=10.43.0.0/24 \
  --set borderGateway=10.43.0.1 \
  --set borderRangeStart=10.43.0.2 \
  --set podReaper.containerStatuses= >/dev/null 2>&1; then
  echo "garuda schema must reject an empty podReaper.containerStatuses" >&2
  exit 1
fi

# Multus: memory limit 256Mi and no CPU limit (upstream 100m/50Mi starves it).
kube_multus_limits="$(printf '%s\n' "${cni_render}" | awk '/^            limits:/ {f=1; next} f && /^              / {print; next} f {exit}')"
if [[ "${kube_multus_limits}" != '              memory: "256Mi"' ]]; then
  echo "garuda-cni-default: kube-multus limits must be exactly memory 256Mi, got: ${kube_multus_limits}" >&2
  exit 1
fi

# Negative assertion: whereabouts must be fully gone from the garuda render.
if [[ "${garuda_render}" == *"whereabouts"* ]]; then
  echo "garuda render still references whereabouts" >&2
  exit 1
fi

# Verify layers-off render has no pod-reaper or multus-ready resources.
layers_off_render="${renders["garuda-layers-off"]}"
for forbidden in 'pod-reaper' 'multus-ready'; do
  if echo "${layers_off_render}" | grep -q "${forbidden}"; then
    echo "garuda-layers-off unexpectedly contains '${forbidden}'" >&2
    exit 1
  fi
done

for scenario in "${!renders[@]}"; do
  out="${renders[${scenario}]}"
  golden="${GOLDEN_DIR}/${scenario}.yaml"

  if [[ "${REGEN_GOLDEN:-0}" == "1" ]]; then
    printf '%s\n' "${out}" > "${golden}"
    echo "regenerated ${golden}"
    continue
  fi

  if ! diff -u "${golden}" <(printf '%s\n' "${out}"); then
    echo "golden mismatch for ${scenario}" >&2
    exit 1
  fi

  echo "ok: ${scenario}"
done
