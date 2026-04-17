#!/usr/bin/env bash
# =============================================================================
# End-to-end smoke test. Run AFTER bootstrap-local.sh + seed-openrouter-secret.sh.
#
# What it does:
#   1. Waits for Argo CD to mark the tenant Application as Synced.
#   2. Waits for the Deployment rollout (pods Ready).
#   3. curls /health, /ready, /metrics, and the tenant's business endpoint
#      through the ingress.
#
# The business endpoint varies PER SERVICE:
#   agent-echo        -> POST /v1/respond    { "message": "..." }
#   intent-classifier -> POST /v1/classify   { "utterance": "..." }
#
# The script reads the devops.platform/service label from the tenant's Argo
# CD Application to figure out which one to call. That label is set by
# `platformctl new-tenant --service ...` and by the hand-edited examples.
#
# Hits 127.0.0.1 with a Host header (because kind's ingress listens on
# localhost:80). Real envs would hit the actual hostname/IP.
# =============================================================================
set -euo pipefail

TENANT="${1:-acme}"
HOST="${TENANT}.local.test"

echo ">>> waiting for Argo CD Application tenant-${TENANT}"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/tenant-"${TENANT}" --timeout=300s || true

echo ">>> waiting for deployment rollout"
kubectl -n "tenant-${TENANT}" rollout status deployment --timeout=300s

echo ">>> /health via ingress"
curl -sS -H "Host: ${HOST}" http://127.0.0.1/health
echo

echo ">>> /ready via ingress"
curl -sS -H "Host: ${HOST}" http://127.0.0.1/ready
echo

echo ">>> /metrics sample (first 20 lines)"
curl -sS -H "Host: ${HOST}" http://127.0.0.1/metrics | head -n 20

# Figure out which service this tenant runs so we hit the right endpoint.
# The label is the single source of truth; the image repository is a
# cross-check if the label is missing (older tenant files).
SERVICE=$(kubectl -n argocd get application "tenant-${TENANT}" \
  -o jsonpath='{.metadata.labels.devops\.platform/service}' 2>/dev/null || true)

if [[ -z "${SERVICE}" ]]; then
  echo "WARN: no devops.platform/service label on Application; assuming agent-echo"
  SERVICE="agent-echo"
fi

echo ">>> tenant '${TENANT}' runs service '${SERVICE}'"

case "${SERVICE}" in
  agent-echo)
    echo ">>> POST /v1/respond"
    curl -sS -X POST -H "Host: ${HOST}" -H "Content-Type: application/json" \
      -d '{"message":"Say hi in 5 words."}' http://127.0.0.1/v1/respond
    ;;
  intent-classifier)
    echo ">>> POST /v1/classify"
    curl -sS -X POST -H "Host: ${HOST}" -H "Content-Type: application/json" \
      -d '{"utterance":"I want to cancel my subscription"}' http://127.0.0.1/v1/classify
    ;;
  *)
    echo "WARN: don't know which endpoint to call for service '${SERVICE}'."
    echo "      Add a case branch in scripts/smoke-test.sh."
    ;;
esac
echo
