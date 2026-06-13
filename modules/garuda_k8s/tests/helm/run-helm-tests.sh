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

# Negative assertion: whereabouts must be fully gone from the garuda render.
if [[ "${garuda_render}" == *"whereabouts"* ]]; then
  echo "garuda render still references whereabouts" >&2
  exit 1
fi

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
