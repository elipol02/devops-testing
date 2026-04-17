#!/usr/bin/env bash
# =============================================================================
# Bring up the full local platform: kind cluster + Argo CD + monitoring +
# ingress, in one command. Idempotent; safe to re-run.
#
# What this script does:
#   1. Sanity-checks that required tools are installed.
#   2. Runs `terraform apply` in infra/terraform/envs/local.
#      That creates the kind cluster AND installs the platform Helm charts.
#   3. Waits for argocd-server and Grafana to be healthy.
#   4. Prints next-step hints (hosts file, Argo CD admin password).
#
# Run from anywhere; BASH_SOURCE dance finds the repo root.
# =============================================================================

# Bash strict mode:
#   -e: exit on any command failure.
#   -u: error on unset variables (catches typos).
#   -o pipefail: a pipeline fails if ANY command in it fails, not just the last.
set -euo pipefail

# Resolve the repo root, independent of where the user cd'd to.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ROOT}/infra/terraform/envs/local"

# Small helper to fail fast with a friendly message rather than a cryptic
# "command not found" halfway through.
need() {
  command -v "$1" >/dev/null 2>&1 || { echo >&2 "missing: $1"; exit 2; }
}
need docker
need terraform
need kubectl
need helm
need kind

# terraform.tfvars holds the user's repo URL (required var). If missing,
# copy the example and bail so they can edit it once.
if [[ ! -f "${ENV_DIR}/terraform.tfvars" ]]; then
  echo ">>> creating terraform.tfvars from example (edit it and re-run)"
  cp "${ENV_DIR}/terraform.tfvars.example" "${ENV_DIR}/terraform.tfvars"
  exit 1
fi

# `-upgrade` refreshes provider versions per versions.tf constraints.
# `-auto-approve` skips the interactive "yes" - fine for local dev; never
# use in prod CI without a prior plan-and-review step.
echo ">>> terraform init + apply"
(cd "${ENV_DIR}" && terraform init -upgrade && terraform apply -auto-approve)

# Use the kind-managed kubeconfig (not the user's default ~/.kube/config).
# terraform output -raw returns just the value with no quoting for shell use.
KUBECONFIG_PATH="$(cd "${ENV_DIR}" && terraform output -raw kubeconfig_path)"
export KUBECONFIG="${KUBECONFIG_PATH}"
echo ">>> KUBECONFIG=${KUBECONFIG}"

# Wait for the control-plane-ish components. `rollout status` blocks until
# the Deployment's ready replica count == desired replica count, or timeout.
echo ">>> waiting for argocd rollout"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

# Grafana sometimes takes longer due to image pulls. `|| true` keeps the
# script going even if this times out - Grafana isn't strictly required
# for the demo's happy path.
echo ">>> waiting for kube-prometheus-stack grafana"
kubectl -n monitoring rollout status deploy/kps-grafana --timeout=300s || true

# Final UX sugar: tell the user exactly what to put in /etc/hosts, where
# to find the URLs, and how to read the generated Argo CD admin password.
echo
echo "Add the following to your hosts file (one-time):"
echo "  127.0.0.1  argocd.local.test grafana.local.test acme.local.test globex.local.test"
echo
echo "Argo CD UI:  http://argocd.local.test"
echo "Grafana:     http://grafana.local.test   (admin / admin)"
echo
echo "Argo CD initial admin password:"
# The Secret value is base64-encoded in the JSON output (standard k8s Secret).
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
