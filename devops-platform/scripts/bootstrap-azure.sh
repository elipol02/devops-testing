#!/usr/bin/env bash
# =============================================================================
# Bring up AKS + the same platform we run locally, in one command.
#
# Prereqs:
#   - `az login` has been run and the active subscription is correct.
#   - terraform.tfvars in envs/azure-dev is populated with your repo URL.
#
# Cost warning: this spins up ~2 B2s nodes + an LB + an ACR. Cheap (~$2-3
# per day) but NOT FREE. Run `terraform destroy` when done.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ROOT}/infra/terraform/envs/azure-dev"

need() { command -v "$1" >/dev/null 2>&1 || { echo >&2 "missing: $1"; exit 2; }; }
need az
need terraform
need kubectl
need helm

# az account show fails with nonzero exit if not logged in. Silencing stderr
# and checking exit code is a cleaner "are you logged in?" probe.
if ! az account show >/dev/null 2>&1; then
  echo "run 'az login' first"; exit 2
fi

if [[ ! -f "${ENV_DIR}/terraform.tfvars" ]]; then
  echo ">>> creating terraform.tfvars from example (edit it and re-run)"
  cp "${ENV_DIR}/terraform.tfvars.example" "${ENV_DIR}/terraform.tfvars"
  exit 1
fi

# AKS provisioning is slow (control plane creation is the bottleneck,
# ~8 min). Terraform apply also does Helm installs on top, so budget ~12.
echo ">>> terraform init + apply (expect 10-12 min)"
(cd "${ENV_DIR}" && terraform init -upgrade && terraform apply -auto-approve)

# The aks-cluster module returns a ready-to-run `az aks get-credentials`
# command as an output, so we can eval it without repeating args.
KUBECONFIG_CMD="$(cd "${ENV_DIR}" && terraform output -raw get_kubeconfig_cmd)"
echo ">>> ${KUBECONFIG_CMD}"
eval "${KUBECONFIG_CMD}"

echo ">>> nodes:"
kubectl get nodes
echo ">>> argocd applications:"
kubectl -n argocd get applications

# The Azure LB provisions asynchronously - may be <pending> on first run.
# Re-run or `kubectl -n ingress-nginx get svc` later to see the IP.
LB_IP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
echo
echo "ingress-nginx external IP: ${LB_IP:-<pending>}"
echo "Point a wildcard DNS A record (or hosts entry) at it for acme/globex hostnames."
echo
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
