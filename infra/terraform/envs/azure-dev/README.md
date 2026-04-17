# azure-dev env

Stands up an AKS cluster + ACR + Log Analytics, then installs the same
platform add-ons as the local env (ingress-nginx on a real Azure Load
Balancer, Argo CD, kube-prometheus-stack, sealed-secrets).

## Prereqs

- Azure subscription + `az login` working
- `terraform` >= 1.6, `kubectl`, `helm`
- Quota for 2x `Standard_B2s` VMs (tiny)

## Apply (~10-12 min)

```bash
az login
az account set --subscription <your-sub-id>
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform apply
```

Then:

```bash
$(terraform output -raw get_kubeconfig_cmd)
kubectl get nodes
kubectl -n argocd get applications
```

## Cost estimate

~$0.20-0.40 per hour running. `terraform destroy` when you're done.

## Tear down

```bash
terraform destroy -auto-approve
```
