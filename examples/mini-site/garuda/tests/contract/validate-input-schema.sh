#!/usr/bin/env bash
# Level 0 contract test: validate each stand's intended garuda-tunnel
# InputSchema against the current upstream schema on @main.
#
# Catches schema drift between the local terragrunt JSON producer and
# the version of garuda-tunnel pulled by `uvx --from ...@main`. Runs
# offline; needs internet only on the first uvx invocation per cache.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
samples_dir="${script_dir}/sample-inputs"

fail=0
for sample in "${samples_dir}"/*.json; do
  name="$(basename "${sample}")"
  if uvx --from git+https://github.com/AlexMKX/garuda-tunnel.git@main \
      python -c "
import sys
from pathlib import Path
from garuda_tunnel.schemas import InputSchema
InputSchema.model_validate_json(Path(sys.argv[1]).read_text())
print(f'ok: {sys.argv[1]}')
" "${sample}"; then
    :
  else
    echo "FAIL: ${name}" >&2
    fail=1
  fi
done

exit "${fail}"
