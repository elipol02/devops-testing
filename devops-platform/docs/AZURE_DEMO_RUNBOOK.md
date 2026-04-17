# Azure (AKS) demo runbook

The whole point of this step: prove that the exact same Helm chart, GitOps
repo, and tenant Applications that worked locally also come up unchanged on
real Azure. This is the "cloud-agnostic platform" interview story.

Time budget: 2 hours. Cost target: under $10.

## 0. Prereqs

- Azure subscription; `az login` works
- Permissions to create Resource Groups, AKS, ACR in your subscription
- The local demo already working (so you've seen what "success" looks like)

## 1. Apply Terraform

```bash
cd infra/terraform/envs/azure-dev
cp terraform.tfvars.example terraform.tfvars
# edit gitops_repo_url to your fork
az login
az account set --subscription <your-sub>
terraform init
terraform apply   # ~10-12 min
```

Or use the helper:

```bash
bash scripts/bootstrap-azure.sh
```

This creates:

- Resource group `devopsplat-rg`
- AKS cluster `devopsplat-aks` (2x `Standard_B2s`)
- ACR `devopsplatXXXXX` (random suffix)
- Log Analytics workspace + Container Insights enabled
- Same add-ons as local: ingress-nginx (LoadBalancer), kube-prometheus-stack,
  Argo CD, sealed-secrets
- A root Argo CD Application tracking your GitOps repo -> tenant apps sync

## 2. Discover the ingress public IP

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

Either point a real DNS record at the external IP, or edit your local hosts
file:

```text
<EXTERNAL-IP>  acme.local.test globex.local.test argocd.local.test grafana.local.test
```

## 3. Seed tenant secrets

Same script as local, just against the AKS kubeconfig:

```bash
bash scripts/seed-openrouter-secret.sh acme   agent-echo        sk-or-v1-XXXXXXXX
bash scripts/seed-openrouter-secret.sh globex intent-classifier sk-or-v1-XXXXXXXX
```

In a "real" setup, we'd replace this with:

- Install the Azure Key Vault CSI provider or External Secrets Operator.
- Store `agent-echo/acme/openrouter` in Key Vault.
- Bind via Workload Identity (already enabled on the cluster).

See `docs/NEXT_STEPS.md`.

## 4. Push the image to ACR (optional)

The sample uses GHCR; that works on AKS too. To demo AKS pulling from ACR:

```bash
ACR="$(cd infra/terraform/envs/azure-dev && terraform output -raw acr_login_server)"
az acr login --name "${ACR%%.*}"
docker tag ghcr.io/YOUR-USER/agent-echo:0.1.0 "${ACR}/agent-echo:0.1.0"
docker push "${ACR}/agent-echo:0.1.0"
```

Then update the tenant YAML's `image.repository` to the ACR URL, commit, merge.
Argo CD rolls the Deployment.

## 5. Smoke test

```bash
bash scripts/smoke-test.sh acme
bash scripts/smoke-test.sh globex
```

## 6. Tear down (do this!)

```bash
cd infra/terraform/envs/azure-dev
terraform destroy -auto-approve
```

## Interview talking points this proves

- "I can take an app from my laptop to production Azure without changing the
  Helm chart, the CI, or the GitOps repo."
- "The only env-specific code is the Terraform module per cloud; the
  `platform-bootstrap` module is reused as-is."
- "Secrets are the one thing that differs, and the chart's `existingSecret`
  knob is the seam: Sealed Secrets locally, Key Vault + Workload Identity on
  Azure."
