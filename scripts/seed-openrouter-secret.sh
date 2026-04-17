#!/usr/bin/env bash
# =============================================================================
# Seeds the per-tenant Secret that the chart expects (existingSecret) with
# an OpenRouter API key.
#
# LOCAL DEV ONLY. Production path:
#   - SealedSecrets: encrypt the Secret into Git so it's reproducible.
#   - ExternalSecrets + Azure Key Vault: the secret lives in KV, the
#     controller materializes it.
# Either of those is ~40 lines of YAML; left out of the demo for simplicity.
#
# Usage: ./seed-openrouter-secret.sh <tenant> <service> <openrouter-api-key>
#
# Examples:
#   ./seed-openrouter-secret.sh acme   agent-echo        sk-or-v1-xxxxx
#   ./seed-openrouter-secret.sh globex intent-classifier sk-or-v1-xxxxx
#
# `service` parameter:
#   - determines the Secret name           (`<tenant>-<service>-secrets`)
#   - determines the env-var key inside it (`<SERVICE_UPPER>_OPENROUTER_API_KEY`)
#   Both must match the tenant's Argo CD Application + the service's
#   app/config.py env_prefix. The CLI (`platformctl new-tenant`) generates
#   matching names automatically.
# =============================================================================
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <tenant> <service> <openrouter-api-key>"
  echo ""
  echo "examples:"
  echo "  $0 acme   agent-echo        sk-or-v1-xxxxx"
  echo "  $0 globex intent-classifier sk-or-v1-xxxxx"
  exit 2
fi

TENANT="$1"
SERVICE="$2"
API_KEY="$3"

NS="tenant-${TENANT}"
SECRET_NAME="${TENANT}-${SERVICE}-secrets"

# Derive the env var key the service expects: `<SERVICE_UPPER>_OPENROUTER_API_KEY`.
# tr translates '-' to '_', then upper-cases. bash 4+.
SERVICE_UPPER=$(echo "${SERVICE}" | tr '[:lower:]-' '[:upper:]_')
ENV_KEY="${SERVICE_UPPER}_OPENROUTER_API_KEY"

# `dry-run=client -o yaml | kubectl apply -f -` = the idempotent create
# pattern. If the namespace exists, apply is a no-op; if not, it creates.
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# Ensure the namespace has the kubernetes.io/metadata.name label (newer k8s
# adds this automatically, older clusters don't). Our NetworkPolicy matches
# on this label so "ingress from monitoring ns" works reliably.
kubectl label namespace "${NS}" kubernetes.io/metadata.name="${NS}" --overwrite

kubectl -n "${NS}" create secret generic "${SECRET_NAME}" \
  --from-literal="${ENV_KEY}=${API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "seeded secret ${SECRET_NAME} in namespace ${NS} (key: ${ENV_KEY})"
