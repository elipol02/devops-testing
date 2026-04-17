# Local demo runbook

Goal: go from `git clone` to a tenant answering HTTP requests through the
ingress, with Grafana showing metrics, in ~10 minutes.

## 0. Prereqs (one-time)

- Docker Desktop
- `kind`, `kubectl`, `helm`, `terraform`, `gh`, `git`, Python 3.12+
- A GitHub repo (fork of this code) you can push to
- An OpenRouter API key (https://openrouter.ai)

Add this line to `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts`):

```text
127.0.0.1  argocd.local.test grafana.local.test acme.local.test globex.local.test
```

## 1. Set the GitOps repo in Terraform vars

```bash
cd infra/terraform/envs/local
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set gitops_repo_url to your fork's HTTPS URL
```

Also replace `YOUR-USER` in:

- `gitops/argocd/tenants/acme.yaml`
- `gitops/argocd/tenants/globex.yaml`
- `platformctl/platformctl/cli.py` defaults (optional; you can pass `--repo-url`)

## 2. Bring up the cluster + platform

```bash
bash scripts/bootstrap-local.sh
```

Expect ~5 min. At the end it prints the Argo CD admin password and the
kubeconfig path.

## 3. Seed per-tenant secrets (local dev only)

```bash
export KUBECONFIG="$HOME/.kube/devops-platform.kubeconfig"
bash scripts/seed-openrouter-secret.sh acme   agent-echo        sk-or-v1-XXXXXXXX
bash scripts/seed-openrouter-secret.sh globex intent-classifier sk-or-v1-XXXXXXXX
```

For production: replace with a `SealedSecret` committed to Git. See
`docs/SEALED_SECRETS.md` (next-steps).

## 4. Watch Argo CD reconcile

Open http://argocd.local.test - login `admin` / (the password from step 2).
Wait until `tenant-acme` and `tenant-globex` go Synced + Healthy.

## 5. Smoke test

```bash
bash scripts/smoke-test.sh acme
bash scripts/smoke-test.sh globex
```

## 6. Grafana

Open http://grafana.local.test (admin / admin). Under Dashboards -> Kubernetes
you'll see per-namespace CPU, memory, and the default Prometheus dashboards.

Import `docs/grafana-agent-echo.json` (if present) to see the service's own
`agent_echo_*` metrics.

## 7. Onboard a new tenant with platformctl

```bash
cd platformctl && pip install -e .
cd ..
platformctl new-tenant --name stark --service agent-echo --model openrouter/auto
# merge the PR
bash scripts/seed-openrouter-secret.sh stark agent-echo sk-or-v1-XXXXXXXX
```

Argo CD picks up the new Application on sync; `stark.local.test` should
resolve after your hosts file gets the new entry.

## 8. CI round trip

- Make a trivial change to `services/agent-echo/app/main.py`.
- Push to `main`.
- GitHub Actions runs the `agent-echo` workflow: lint, pytest, Trivy, push to
  GHCR, then opens a `ci(agent-echo): bump image` PR against this repo.
- Merge that PR; Argo CD rolls the Deployments.

## 9. Tear down

```bash
cd infra/terraform/envs/local
terraform destroy -auto-approve
```
