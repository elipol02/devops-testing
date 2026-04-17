"""Typed runtime configuration.

Why pydantic-settings:
    * Reads env vars AND .env files with one class definition.
    * Gives us type coercion: AGENT_ECHO_OPENROUTER_TIMEOUT_SECONDS="5"
      becomes a float, not a string. Errors at startup, not at first call.
    * Single import (`from app.config import settings`) everywhere - makes
      the code easy to grep for config usages.

Why env_prefix="AGENT_ECHO_":
    Prevents accidental collision with other libraries' env vars (e.g.
    HTTP_PROXY, LOG_LEVEL set at the shell). The chart's ConfigMap and
    Secret both emit AGENT_ECHO_* keys exclusively.
"""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration, loaded from env vars.

    The ConfigMap / Secret in the Helm chart populates these at pod start.
    """

    # case_sensitive=False matches AGENT_ECHO_TENANT regardless of casing
    # (some CI systems lowercase env vars). env_prefix strips the prefix,
    # so TENANT field reads from AGENT_ECHO_TENANT.
    model_config = SettingsConfigDict(env_prefix="AGENT_ECHO_", case_sensitive=False)

    # "unknown" default so a bare `python -m app.main` works locally for
    # exploration without 15 env vars set.
    tenant: str = Field(default="unknown", description="Customer/tenant identifier")
    environment: str = Field(default="dev", description="dev|staging|prod")

    # API key default "" (not None) so startup doesn't crash; the /ready
    # probe returns 503 until it's set. That separation matters: it keeps
    # the pod schedulable while a Sealed Secret is still unsealing.
    openrouter_api_key: str = Field(default="", description="OpenRouter API key")
    openrouter_base_url: str = Field(default="https://openrouter.ai/api/v1")
    # openrouter/auto = OpenRouter's "pick the best model for the prompt"
    # option. Good default; tenants override via Helm values for cost/quality tuning.
    openrouter_model: str = Field(default="openrouter/auto")
    # 30s is generous for LLM calls. Matches httpx default; set explicitly
    # so future changes are auditable.
    openrouter_timeout_seconds: float = Field(default=30.0)

    system_prompt: str = Field(
        default=(
            "You are a helpful AI customer-service agent operating on behalf of "
            "the tenant. Be concise, warm, and accurate."
        )
    )

    log_level: str = Field(default="INFO")


# Module-level singleton. BaseSettings reads env vars at INSTANCE CREATION
# time, so this runs once at import. That's what we want - re-reading env
# per request would be wasteful and could surface racy updates.
settings = Settings()
