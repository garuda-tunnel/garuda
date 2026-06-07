#!/usr/bin/env bash
# Helm-level tests for modules/k8s_gateway_bootstrap.
# helm lint + helm template diffed against tests/golden/*.yaml.
# Update goldens with: REGEN_GOLDEN=1 ./run-helm-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/../.."
CHART_DIR="${MODULE_DIR}/charts/platform-gateway"
GOLDEN_DIR="${SCRIPT_DIR}/../golden"

# Resolve any in-tree chart dependencies on every run. The chart has no
# dependencies today; the call is kept for parity with sibling runners and
# to make adding one in the future a no-op for the harness.
helm dependency update "${CHART_DIR}"

for scenario in one-hostname two-hostnames; do
  values_file="${SCRIPT_DIR}/values-${scenario}.yaml"
  helm lint "${CHART_DIR}" -f "${values_file}"

  out="$(helm template platform-gateway "${CHART_DIR}" --namespace gateway-system -f "${values_file}")"
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
