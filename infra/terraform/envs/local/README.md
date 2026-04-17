# local env

Stands up a single-node kind cluster and installs the platform add-ons
(ingress-nginx, kube-prometheus-stack, sealed-secrets, Argo CD + a root
Application pointing at your GitOps repo).

## Prereqs

- Docker Desktop running
- `terraform` >= 1.6
- `kubectl`, `helm` (optional, for inspection)

## Run

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars to point at your GitOps repo
terraform init
terraform apply
```

Then add to `C:\Windows\System32\drivers\etc\hosts` (or `/etc/hosts`):

```text
127.0.0.1  argocd.local.test grafana.local.test acme.local.test globex.local.test
```

## Tear down

```bash
terraform destroy
```
