# Install prerequisites (Windows / PowerShell)

You already have `docker` and `kubectl`. You still need `helm`, `terraform`,
`kind`, `gh`, and a recent Python. The fastest path on Windows is `winget`
(preinstalled on Win11) or `choco`.

## One-shot (winget, run in elevated PowerShell)

```powershell
winget install --id Kubernetes.kind -e
winget install --id Helm.Helm -e
winget install --id Hashicorp.Terraform -e
winget install --id GitHub.cli -e
winget install --id Python.Python.3.12 -e
winget install --id Microsoft.AzureCLI -e
```

Restart the terminal, then verify:

```powershell
kind version
helm version
terraform version
gh --version
python --version
az version
```

## WSL alternative (recommended for bash scripts)

The `scripts/bootstrap-*.sh` files are bash. They work under Git Bash but run
more predictably inside WSL:

```powershell
wsl --install -d Ubuntu
```

Then inside Ubuntu:

```bash
sudo apt update
sudo apt install -y curl git python3.12 python3.12-venv python3-pip
# Install Docker Desktop and enable WSL integration; docker/kubectl come from there.
curl -fsSL https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz | tar xz && sudo mv linux-amd64/helm /usr/local/bin/
curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 && sudo install -m 0755 /tmp/kind /usr/local/bin/kind
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install -y gh
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Then `gh auth login` and `az login` once.

## Hosts file

Add this line (elevated Notepad on Windows, or `sudo` in WSL on
`/etc/hosts`):

```text
127.0.0.1  argocd.local.test grafana.local.test acme.local.test globex.local.test
```

On Windows: `C:\Windows\System32\drivers\etc\hosts`.
