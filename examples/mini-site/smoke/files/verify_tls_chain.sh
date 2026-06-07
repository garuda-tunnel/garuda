#!/usr/bin/env bash
# Verify the public TLS endpoint for $1 serves a valid, non-staging
# Let's Encrypt cert whose SAN includes the FQDN and whose chain
# validates against the system trust store. Exit non-zero on any
# failure. Invoked by smoke phase 12 via ansible.builtin.script so the
# Ansible preparser never has to tokenize this shell body.
set -euo pipefail

fqdn="${1:?usage: verify_tls_chain.sh <fqdn>}"

out=$(echo | openssl s_client -connect "${fqdn}:443" \
        -servername "${fqdn}" -showcerts 2>/dev/null)

# SAN must include the expected hostname anchored to a DNS: entry.
fqdn_escaped=$(printf '%s' "${fqdn}" | sed 's/\./\\./g')
printf '%s' "${out}" | openssl x509 -noout -ext subjectAltName \
  | grep -qE "(^|[, ])DNS:${fqdn_escaped}(,|\$| )"

# Issuer must be Let's Encrypt production (not staging).
issuer=$(printf '%s' "${out}" | openssl x509 -noout -issuer)
printf '%s' "${issuer}" | grep -qi "let's encrypt"
printf '%s' "${issuer}" | grep -qiv "staging"

# Chain validates against the system trust store.
echo | openssl s_client -connect "${fqdn}:443" \
        -servername "${fqdn}" -verify_return_error >/dev/null 2>&1

echo "TLS chain OK for ${fqdn}"
