import yaml
from typer.testing import CliRunner

from platformctl.cli import _env_prefix_for, _render_tenant, app

runner = CliRunner()


def test_render_produces_valid_application_for_agent_echo():
    rendered = _render_tenant(
        tenant="acme",
        service="agent-echo",
        env_prefix=_env_prefix_for("agent-echo"),
        environment="dev",
        model="openrouter/auto",
        image_repository="ghcr.io/me/agent-echo",
        image_tag="0.1.0",
        replica_count=2,
        ingress_domain="local.test",
        repo_url="https://github.com/me/devops-platform.git",
        revision="main",
    )
    doc = yaml.safe_load(rendered)
    assert doc["apiVersion"].startswith("argoproj.io")
    assert doc["kind"] == "Application"
    assert doc["metadata"]["name"] == "tenant-acme"
    assert doc["metadata"]["labels"]["devops.platform/service"] == "agent-echo"
    assert doc["spec"]["destination"]["namespace"] == "tenant-acme"

    values = yaml.safe_load(doc["spec"]["source"]["helm"]["values"])
    assert values["tenant"] == "acme"
    assert values["ingress"]["host"] == "acme.local.test"
    assert values["image"]["repository"] == "ghcr.io/me/agent-echo"
    assert values["config"]["AGENT_ECHO_OPENROUTER_MODEL"] == "openrouter/auto"
    assert values["secret"]["existingSecret"] == "acme-agent-echo-secrets"


def test_render_uses_service_specific_env_prefix_for_intent_classifier():
    rendered = _render_tenant(
        tenant="globex",
        service="intent-classifier",
        env_prefix=_env_prefix_for("intent-classifier"),
        environment="dev",
        model="anthropic/claude-3.5-haiku",
        image_repository="ghcr.io/me/intent-classifier",
        image_tag="0.2.0",
        replica_count=3,
        ingress_domain="local.test",
        repo_url="https://github.com/me/devops-platform.git",
        revision="main",
    )
    doc = yaml.safe_load(rendered)
    values = yaml.safe_load(doc["spec"]["source"]["helm"]["values"])
    # Different service -> different env-var prefix -> different ConfigMap keys.
    assert "INTENT_CLASSIFIER_OPENROUTER_MODEL" in values["config"]
    assert "AGENT_ECHO_OPENROUTER_MODEL" not in values["config"]
    assert values["secret"]["existingSecret"] == "globex-intent-classifier-secrets"
    assert doc["metadata"]["labels"]["devops.platform/service"] == "intent-classifier"


def test_env_prefix_derivation():
    assert _env_prefix_for("agent-echo") == "AGENT_ECHO_"
    assert _env_prefix_for("intent-classifier") == "INTENT_CLASSIFIER_"
    assert _env_prefix_for("churn-scorer") == "CHURN_SCORER_"


def test_dry_run_prints_manifest():
    result = runner.invoke(
        app,
        [
            "new-tenant",
            "--name", "acme",
            "--service", "agent-echo",
            "--dry-run",
        ],
    )
    assert result.exit_code == 0, result.stdout
    assert "tenant-acme" in result.stdout


def test_rejects_bad_tenant_name():
    result = runner.invoke(
        app,
        [
            "new-tenant",
            "--name", "BAD_NAME",
            "--service", "agent-echo",
            "--dry-run",
        ],
    )
    assert result.exit_code == 2


def test_rejects_missing_service():
    # --service is required now.
    result = runner.invoke(app, ["new-tenant", "--name", "acme", "--dry-run"])
    assert result.exit_code != 0
