# GitOps (Argo CD)

Terraform creates a single "root" Application that watches this directory
recursively. Anything you drop here becomes part of the platform.

## Layout

- `projects/` - `AppProject` resources (e.g. `tenants` project that scopes
  what tenant Applications may deploy).
- `tenants/` - one `Application` per tenant. Each points at
  `charts/agent-integration` and lands in its own `tenant-<name>` namespace.

## Adding a tenant

Either:

1. Copy `tenants/acme.yaml` to `tenants/newcustomer.yaml`, edit the values, PR.
2. Or run `platformctl new-tenant --name newcustomer` which does the copy and
   opens the PR for you.

## Replace placeholders before first apply

Every file in `tenants/` references `https://github.com/YOUR-USER/devops-platform.git`.
Replace `YOUR-USER` with your GitHub username (or change to your fork URL).
`ghcr.io/YOUR-USER/agent-echo` likewise.
