"""platformctl: self-service CLI for the DevOps platform.

Subcommands
-----------
new-tenant      Create a PR that adds an Argo CD Application for a new tenant
                running a SPECIFIC service. (`--service` is required.)
new-service     Scaffold a new service directory under services/, copied
                from an existing service template.
list-tenants    List existing tenant Applications in the repo.
list-services   List services that live under services/.
delete-tenant   Create a PR that removes a tenant (Argo CD's finalizer then
                cleans up the namespace on sync).
lint            Static-check tenant manifests (YAML well-formed, required keys).

Design note
-----------
This CLI is intentionally a thin wrapper around git + gh. All durable state
lives in the Git repo. The cluster is reconciled by Argo CD. That means the
CLI has no secrets, no cluster creds, and can run from a laptop, CI, or an
internal dev portal identically.

The platform hosts MANY services (one per FDE / customer integration) and
MANY tenants (one per customer deployment). A tenant runs ONE service:
acme runs agent-echo, globex runs intent-classifier, etc. `new-tenant`
requires `--service` so we never implicitly couple "add a tenant" to a
single service.

Why Typer (not argparse/click): decorators + type hints give us parsing,
help text, and validation from one function signature.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Annotated

import typer
import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from rich.console import Console
from rich.table import Table

app = typer.Typer(
    add_completion=False,
    help="Self-service CLI for the DevOps platform.",
    no_args_is_help=True,
)
console = Console()

TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"

# DNS-1123 subdomain constraints (applied to both tenant slug and service name).
NAME_RE = re.compile(r"^[a-z][a-z0-9-]{1,38}[a-z0-9]$")


# -- helpers ------------------------------------------------------------------


def _repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        console.print("[red]platformctl must be run inside the devops-platform git repo.[/red]")
        raise typer.Exit(code=2) from exc
    return Path(out.stdout.strip())


def _tenants_dir(root: Path) -> Path:
    return root / "gitops" / "argocd" / "tenants"


def _services_dir(root: Path) -> Path:
    return root / "services"


def _validate_slug(name: str, kind: str) -> None:
    if not NAME_RE.match(name):
        console.print(
            f"[red]Invalid {kind} name '{name}'. Must be 3-40 chars, "
            "lowercase alphanumerics + hyphen, start with a letter.[/red]"
        )
        raise typer.Exit(code=2)


def _env_prefix_for(service: str) -> str:
    """Derive an env-var prefix from a service name.

    intent-classifier -> INTENT_CLASSIFIER_
    agent-echo        -> AGENT_ECHO_

    Convention matches services/<service>/app/config.py env_prefix. If a
    service breaks the convention, the caller can pass --env-prefix
    explicitly.
    """
    return service.upper().replace("-", "_") + "_"


def _render_tenant(**ctx: str | int) -> str:
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        keep_trailing_newline=True,
        undefined=StrictUndefined,
    )
    return env.get_template("tenant-app.yaml.j2").render(**ctx)


def _run(cmd: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    console.print(f"[dim]$ {' '.join(cmd)}[/dim]")
    return subprocess.run(cmd, cwd=cwd, check=check, text=True)


def _require_tool(binary: str) -> None:
    if shutil.which(binary) is None:
        console.print(f"[red]Required tool '{binary}' not found on PATH.[/red]")
        raise typer.Exit(code=2)


def _discover_services(root: Path) -> list[str]:
    """Return the list of service dirs under services/, sorted."""
    services_dir = _services_dir(root)
    if not services_dir.exists():
        return []
    return sorted(
        p.name
        for p in services_dir.iterdir()
        if p.is_dir() and (p / "Dockerfile").exists()
    )


# -- commands -----------------------------------------------------------------


@app.command("new-tenant")
def new_tenant(
    name: Annotated[str, typer.Option("--name", "-n", help="Tenant slug, e.g. 'acme'.")],
    service: Annotated[
        str,
        typer.Option(
            "--service",
            "-s",
            help=(
                "Which service this tenant runs (e.g. 'agent-echo', "
                "'intent-classifier'). Must exist under services/."
            ),
        ),
    ],
    environment: Annotated[str, typer.Option(help="dev|staging|prod")] = "dev",
    model: Annotated[str, typer.Option(help="OpenRouter model to default to.")] = "openrouter/auto",
    image_repository: Annotated[
        str,
        typer.Option(
            "--image-repo",
            help=(
                "Container image repository. Defaults to "
                "ghcr.io/<owner>/<service>, derived from git remote + --service."
            ),
        ),
    ] = "",
    image_tag: Annotated[str, typer.Option("--image-tag", help="Image tag.")] = "0.1.0",
    replica_count: Annotated[int, typer.Option("--replicas", min=1, max=20)] = 2,
    ingress_domain: Annotated[str, typer.Option(help="Wildcard ingress domain.")] = "local.test",
    repo_url: Annotated[
        str, typer.Option("--repo-url", help="GitOps repo URL.")
    ] = "https://github.com/elipol02/devops-testing.git",
    revision: Annotated[str, typer.Option(help="Git revision for Argo CD to track.")] = "main",
    env_prefix: Annotated[
        str,
        typer.Option(
            "--env-prefix",
            help=(
                "Env var prefix the service expects (e.g. AGENT_ECHO_). "
                "Auto-derived from --service if omitted."
            ),
        ),
    ] = "",
    open_pr: Annotated[bool, typer.Option("--pr/--no-pr", help="Open a PR via gh.")] = True,
    dry_run: Annotated[bool, typer.Option("--dry-run", help="Print the manifest and exit.")] = False,
) -> None:
    """Onboard a new tenant running a specific service.

    Example:
        platformctl new-tenant --name initech --service intent-classifier

    The tenant Application gets placed under gitops/argocd/tenants/. Argo CD
    picks it up on merge and deploys the service into namespace tenant-<name>.
    """
    _validate_slug(name, "tenant")
    _validate_slug(service, "service")

    # Derive defaults that depend on --service.
    effective_prefix = env_prefix or _env_prefix_for(service)
    if image_repository == "":
        # Try to guess the image repo from the GitOps repo_url's owner.
        # Best-effort: we parse ".../<owner>/<repo>.git" out of repo_url.
        m = re.search(r"[/:]([^/]+)/[^/]+?(?:\.git)?$", repo_url)
        owner = m.group(1) if m else "YOUR-USER"
        image_repository = f"ghcr.io/{owner}/{service}"

    manifest = _render_tenant(
        tenant=name,
        service=service,
        env_prefix=effective_prefix,
        environment=environment,
        model=model,
        image_repository=image_repository,
        image_tag=image_tag,
        replica_count=replica_count,
        ingress_domain=ingress_domain,
        repo_url=repo_url,
        revision=revision,
    )

    if dry_run:
        console.print(manifest)
        return

    parsed = yaml.safe_load(manifest)
    if parsed.get("kind") != "Application" or not parsed.get("apiVersion", "").startswith("argoproj.io"):
        console.print("[red]Rendered manifest is not an Argo CD Application.[/red]")
        raise typer.Exit(code=1)

    # Only touch git once we know we're actually writing.
    root = _repo_root()

    # Warn (but don't block) if the service doesn't exist yet in the repo.
    # A tenant CAN reference an image that's built elsewhere, but 99% of
    # the time you want to point at a service that lives in this repo, so
    # a misspelling is more likely than an advanced use case.
    known = _discover_services(root)
    if known and service not in known:
        console.print(
            f"[yellow]Warning: service '{service}' not found under services/. "
            f"Known services: {', '.join(known) or '(none)'}[/yellow]"
        )

    tenants_dir = _tenants_dir(root)
    tenants_dir.mkdir(parents=True, exist_ok=True)
    target = tenants_dir / f"{name}.yaml"
    if target.exists():
        console.print(f"[red]Tenant '{name}' already exists at {target.relative_to(root)}.[/red]")
        raise typer.Exit(code=1)
    target.write_text(manifest, encoding="utf-8")
    console.print(f"[green]Wrote {target.relative_to(root)}[/green]")

    # Reminder to wire the caller workflow. This is the manual step we
    # choose NOT to automate - editing the caller workflow is a review
    # surface (which tenants does a service deploy to?) and should be a
    # deliberate commit, not a CLI side-effect.
    console.print(
        f"[cyan]Next:[/cyan] add "
        f"gitops/argocd/tenants/{name}.yaml to "
        f".github/workflows/{service}.yml -> with.gitops_values_paths "
        "so CI for that service bumps this tenant's image tag."
    )

    if not open_pr:
        console.print("Skipping PR (--no-pr). Commit and push manually.")
        return

    _require_tool("git")
    _require_tool("gh")
    branch = f"tenant/{name}"
    _run(["git", "checkout", "-b", branch], cwd=root)
    _run(["git", "add", str(target.relative_to(root))], cwd=root)
    _run(
        ["git", "commit", "-m", f"feat(tenants): onboard {name} on {service}"],
        cwd=root,
    )
    _run(["git", "push", "-u", "origin", branch], cwd=root)
    _run(
        [
            "gh",
            "pr",
            "create",
            "--title",
            f"feat(tenants): onboard {name} ({service})",
            "--body",
            (
                f"Onboards `{name}` as a new tenant running `{service}`.\n\n"
                f"- Environment: `{environment}`\n"
                f"- Service: `{service}`\n"
                f"- Image: `{image_repository}:{image_tag}`\n"
                f"- Ingress: `https://{name}.{ingress_domain}`\n"
                "\nArgo CD will create namespace `tenant-"
                f"{name}` and reconcile the Helm release on merge.\n"
                f"\nRemember to add this tenant to "
                f"`.github/workflows/{service}.yml` -> `gitops_values_paths`."
            ),
        ],
        cwd=root,
    )
    console.print(f"[green]PR opened for tenant '{name}'. Merge to deploy.[/green]")


@app.command("new-service")
def new_service(
    name: Annotated[str, typer.Option("--name", "-n", help="Service slug, e.g. 'churn-scorer'.")],
    from_service: Annotated[
        str,
        typer.Option(
            "--from",
            help=(
                "Existing service to copy as the starting template. "
                "Defaults to 'intent-classifier' because it's the smallest."
            ),
        ),
    ] = "intent-classifier",
) -> None:
    """Scaffold a new service by copying an existing one.

    This is what an FDE does on day one of a new customer integration:
    clone the last one, rename, then edit the business logic. We codify
    that pattern here so the boring parts (Dockerfile, metrics, probes,
    config shape) are correct from the first commit.

    After running this you still have to:
      1. Edit services/<name>/app/*.py to implement the new endpoint
      2. Copy .github/workflows/<from>.yml to .github/workflows/<name>.yml
         and update service_name / image_name / gitops_values_paths
      3. Point a tenant at the new service via `platformctl new-tenant
         --service <name>`
    """
    _validate_slug(name, "service")
    _validate_slug(from_service, "service")

    root = _repo_root()
    src = _services_dir(root) / from_service
    dst = _services_dir(root) / name

    if not src.exists():
        console.print(f"[red]Template service '{from_service}' not found at {src}.[/red]")
        raise typer.Exit(code=1)
    if dst.exists():
        console.print(f"[red]Service '{name}' already exists at {dst}.[/red]")
        raise typer.Exit(code=1)

    # Copy the tree, skipping generated junk that shouldn't carry over.
    def _ignore(_directory: str, names: list[str]) -> list[str]:
        skip = {"__pycache__", ".pytest_cache", ".ruff_cache", ".venv", "venv", "build", "dist"}
        return [n for n in names if n in skip or n.endswith(".egg-info")]

    shutil.copytree(src, dst, ignore=_ignore)

    # Rename identifiers inside the copied files. These substitutions are
    # deliberately dumb: they only hit exact slug/prefix strings. If the
    # FDE has custom code already, they'll see the new skeleton and edit
    # from there.
    old_slug = from_service
    new_slug = name
    old_prefix = _env_prefix_for(from_service)
    new_prefix = _env_prefix_for(name)
    old_snake = from_service.replace("-", "_")
    new_snake = name.replace("-", "_")

    replacements: list[tuple[str, str]] = [
        (old_prefix, new_prefix),
        (old_slug, new_slug),
        (old_snake, new_snake),
    ]

    text_suffixes = {".py", ".toml", ".yaml", ".yml", ".md", ".txt", ".cfg", ".ini"}
    for path in dst.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in text_suffixes:
            continue
        original = path.read_text(encoding="utf-8")
        updated = original
        for old, new in replacements:
            updated = updated.replace(old, new)
        if updated != original:
            path.write_text(updated, encoding="utf-8")

    console.print(f"[green]Scaffolded services/{name}/ from services/{from_service}/[/green]")
    console.print(
        "[cyan]Next:[/cyan]\n"
        f"  1. Edit services/{name}/app/main.py to implement your endpoint.\n"
        f"  2. cp .github/workflows/{from_service}.yml .github/workflows/{name}.yml\n"
        f"     and update service_name / image_name / gitops_values_paths.\n"
        f"  3. platformctl new-tenant --name <tenant> --service {name}"
    )


@app.command("list-tenants")
def list_tenants() -> None:
    """List tenants by inspecting the GitOps repo."""
    root = _repo_root()
    tenants_dir = _tenants_dir(root)
    if not tenants_dir.exists():
        console.print("[yellow]No tenants directory yet.[/yellow]")
        return

    table = Table(title="Tenants")
    table.add_column("Tenant")
    table.add_column("Service")
    table.add_column("Environment")
    table.add_column("Namespace")
    table.add_column("Image")
    table.add_column("File", overflow="fold")

    found = 0
    for yaml_file in sorted(tenants_dir.glob("*.yaml")):
        try:
            doc = yaml.safe_load(yaml_file.read_text(encoding="utf-8"))
        except yaml.YAMLError:
            continue
        if not isinstance(doc, dict) or doc.get("kind") != "Application":
            continue

        values_text: str = (
            (doc.get("spec") or {}).get("source", {}).get("helm", {}).get("values", "") or ""
        )
        try:
            values = yaml.safe_load(values_text) or {}
        except yaml.YAMLError:
            values = {}

        # Prefer the label metadata for service (authoritative per
        # platform convention). Fall back to parsing the image repo if
        # the label is missing (older tenants).
        labels = (doc.get("metadata") or {}).get("labels", {}) or {}
        service = labels.get("devops.platform/service")
        image = (values.get("image") or {})
        image_repo = image.get("repository", "?")
        image_tag = image.get("tag", "?")
        if not service:
            # Heuristic: last path segment of the image repository.
            service = image_repo.rsplit("/", 1)[-1]

        table.add_row(
            str(values.get("tenant", "?")),
            str(service),
            str(values.get("environment", "?")),
            (doc.get("spec") or {}).get("destination", {}).get("namespace", "?"),
            f"{image_repo}:{image_tag}",
            str(yaml_file.relative_to(root)),
        )
        found += 1

    if found == 0:
        console.print("[yellow]No tenants found.[/yellow]")
        return
    console.print(table)


@app.command("list-services")
def list_services() -> None:
    """List services that live under services/."""
    root = _repo_root()
    services = _discover_services(root)
    if not services:
        console.print("[yellow]No services found under services/.[/yellow]")
        return

    table = Table(title="Services")
    table.add_column("Service")
    table.add_column("Dockerfile")
    table.add_column("Tests?")

    for s in services:
        svc_dir = _services_dir(root) / s
        has_tests = (svc_dir / "tests").exists()
        table.add_row(
            s,
            str((svc_dir / "Dockerfile").relative_to(root)),
            "yes" if has_tests else "no",
        )
    console.print(table)


@app.command("delete-tenant")
def delete_tenant(
    name: Annotated[str, typer.Option("--name", "-n")],
    open_pr: Annotated[bool, typer.Option("--pr/--no-pr")] = True,
    confirm: Annotated[bool, typer.Option("--yes", help="Skip confirmation prompt.")] = False,
) -> None:
    """Remove a tenant Application via a PR. Argo CD's finalizer handles the rest."""
    _validate_slug(name, "tenant")
    root = _repo_root()
    target = _tenants_dir(root) / f"{name}.yaml"
    if not target.exists():
        console.print(f"[red]No tenant file at {target.relative_to(root)}.[/red]")
        raise typer.Exit(code=1)

    if not confirm:
        typer.confirm(
            f"Decommission tenant '{name}'? This deletes its namespace on sync.",
            abort=True,
        )

    target.unlink()
    console.print(f"[yellow]Removed {target.relative_to(root)}[/yellow]")

    if not open_pr:
        return

    _require_tool("git")
    _require_tool("gh")
    branch = f"tenant/{name}-offboard"
    _run(["git", "checkout", "-b", branch], cwd=root)
    _run(["git", "add", str(target.relative_to(root))], cwd=root)
    _run(
        ["git", "commit", "-m", f"feat(tenants): decommission {name}"],
        cwd=root,
    )
    _run(["git", "push", "-u", "origin", branch], cwd=root)
    _run(
        [
            "gh",
            "pr",
            "create",
            "--title",
            f"feat(tenants): decommission {name}",
            "--body",
            (
                f"Removes tenant `{name}`. On merge, Argo CD deletes the "
                "Application and its namespace (prune=true, finalizer set)."
            ),
        ],
        cwd=root,
    )


@app.command("lint")
def lint() -> None:
    """Validate every tenant manifest in the repo.

    Same checks that CI runs (see .github/workflows/platformctl.yml).
    Useful for pre-commit hooks.
    """
    root = _repo_root()
    tenants_dir = _tenants_dir(root)
    if not tenants_dir.exists():
        console.print("[yellow]No tenants directory.[/yellow]")
        return

    errors: list[str] = []
    for yaml_file in sorted(tenants_dir.glob("*.yaml")):
        try:
            doc = yaml.safe_load(yaml_file.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            errors.append(f"{yaml_file.name}: invalid YAML - {exc}")
            continue
        if not isinstance(doc, dict):
            errors.append(f"{yaml_file.name}: not a mapping")
            continue
        if doc.get("kind") != "Application":
            errors.append(f"{yaml_file.name}: kind is not Application")
        spec = doc.get("spec") or {}
        dest = (spec.get("destination") or {}).get("namespace", "")
        if not dest.startswith("tenant-"):
            errors.append(f"{yaml_file.name}: destination.namespace must start with 'tenant-'")

    if errors:
        console.print("[red]Lint failed:[/red]")
        for e in errors:
            console.print(f"  - {e}")
        sys.exit(1)
    console.print(f"[green]{len(list(tenants_dir.glob('*.yaml')))} tenant manifest(s) OK.[/green]")


if __name__ == "__main__":  # pragma: no cover
    app()
