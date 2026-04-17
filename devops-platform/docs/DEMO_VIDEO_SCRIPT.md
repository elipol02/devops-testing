# Demo video script (3 minutes)

You record. Below is the beat-by-beat. Target length 3:00, hard cap 3:30.

## Setup before you hit record

- Both clusters already bootstrapped (local kind is enough for the video;
  mention AKS at the end).
- Hosts file has `acme.local.test`, `globex.local.test`, `argocd.local.test`,
  `grafana.local.test`.
- OpenRouter secret seeded for `acme`.
- Browser tabs, in order: Argo CD UI, Grafana (dashboard "agent-echo"),
  GitHub repo home.
- Terminal windows: (1) left = code/CLI, (2) right = `kubectl get pods -A -w`.
- Mic check.

## Beat 1 - 20 seconds. The pitch.

Open on the root [README.md](../README.md).

Say: "This is a self-service DevOps platform I built to host per-customer
integration services on Kubernetes. One command onboards a tenant. Argo CD
deploys it. Prometheus watches it. Same stack on a laptop and on AKS."

## Beat 2 - 30 seconds. Architecture at a glance.

Open [docs/ARCHITECTURE.md](ARCHITECTURE.md), scroll to the Mermaid diagram.

Say: "FDE runs `platformctl`. It opens a PR in this repo. Merging hands off
to Argo CD, which reconciles a namespace per tenant. CI is a reusable GitHub
Actions workflow that any service adopts in 15 lines."

Hover over `charts/agent-integration/` in the file tree, then `platformctl/`,
then `infra/terraform/modules/`.

## Beat 3 - 40 seconds. Self-service in action.

Switch to terminal.

```bash
platformctl list-tenants
```

Show the table (acme, globex).

```bash
platformctl new-tenant --name stark --model openrouter/auto --dry-run
```

Scroll the rendered manifest. Point at `destination.namespace: tenant-stark`
and the Helm values block.

```bash
platformctl new-tenant --name stark --model openrouter/auto --no-pr
git diff gitops/argocd/tenants/stark.yaml
```

Say: "No PR here because this is a demo, but in the real flow this would
commit, push, and open a PR via `gh`."

## Beat 4 - 45 seconds. GitOps sync.

Manually commit and push stark.yaml on a branch:

```bash
git checkout -b demo/stark
git add gitops/argocd/tenants/stark.yaml
git commit -m "tenant: stark"
git push -u origin demo/stark
gh pr create --title "tenant: stark" --body "demo" --fill
gh pr merge --merge --delete-branch
```

Switch to Argo CD UI. Hit refresh on the root application. Show
`tenant-stark` appear. Wait for Synced + Healthy.

Switch to right terminal running `kubectl get pods -A -w`. Show the new
`tenant-stark` pods come up.

## Beat 5 - 30 seconds. It actually works.

```bash
kubectl -n tenant-stark create secret generic stark-agent-echo-secrets \
  --from-literal=AGENT_ECHO_OPENROUTER_API_KEY="$OR_KEY"
```

```bash
curl -s -H "Host: stark.local.test" http://127.0.0.1/health
curl -s -H "Host: stark.local.test" \
  -X POST -H "Content-Type: application/json" \
  -d '{"message":"Say hi in five words."}' \
  http://127.0.0.1/v1/respond | jq
```

Show the JSON reply with the model and token usage.

## Beat 6 - 25 seconds. Observability.

Switch to Grafana, "agent-echo" dashboard. Pick `tenant-stark` from the
template var. Show request rate and OpenRouter latency panels populate.

Switch to `kubectl -n tenant-stark logs deploy/stark` and show one JSON log
line with `tenant=stark`, `request_id=...`.

## Beat 7 - 20 seconds. Portability.

Open [docs/AZURE_DEMO_RUNBOOK.md](AZURE_DEMO_RUNBOOK.md) briefly.

Say: "Exact same chart, same GitOps repo, different Terraform env wires up
AKS, ACR, and Log Analytics. The platform-bootstrap module is shared."

Optional: if you have the AKS cluster still up, show
`kubectl --context aks get applications -n argocd` for half a second.

## Beat 8 - 10 seconds. Close.

Show [docs/INTERVIEW_TALKING_POINTS.md](INTERVIEW_TALKING_POINTS.md).

Say: "Repo maps each bullet of the JD to a file path. Happy to walk through
any of it. Thanks."

## After you stop recording

```bash
cd infra/terraform/envs/azure-dev && terraform destroy -auto-approve
```

Yes, really. Before bed.
