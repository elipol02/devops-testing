# platformctl

Self-service CLI for the DevOps platform. Turns "spin up a new customer" into
one command.

## Install (editable)

```bash
pip install -e .
```

## Commands

```bash
platformctl new-tenant --name acme --model openrouter/auto
platformctl new-tenant --name acme --dry-run       # print the manifest, don't write
platformctl list-tenants
platformctl delete-tenant --name acme --yes
platformctl lint                                    # validate all tenant manifests
```

## What happens under the hood

`new-tenant`:

1. Validates the tenant slug (`[a-z][a-z0-9-]*`, length 3-40).
2. Renders `platformctl/templates/tenant-app.yaml.j2` with your inputs.
3. Writes it to `gitops/argocd/tenants/<name>.yaml`.
4. Creates a branch, commits, pushes, opens a PR via `gh`.
5. When the PR merges, Argo CD picks it up and reconciles.

No cluster credentials are ever used. Everything is Git -> Argo CD.
