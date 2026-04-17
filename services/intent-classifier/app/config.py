"""Typed runtime configuration for intent-classifier.

Note the env_prefix: INTENT_CLASSIFIER_ rather than AGENT_ECHO_. Each service
owns its own config namespace. The chart (values.config) is a generic
key-value passthrough - it doesn't know or care which prefix the service
uses. This is what makes the chart reusable across different services.
"""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="INTENT_CLASSIFIER_", case_sensitive=False)

    tenant: str = Field(default="unknown")
    environment: str = Field(default="dev")

    openrouter_api_key: str = Field(default="")
    openrouter_base_url: str = Field(default="https://openrouter.ai/api/v1")
    openrouter_model: str = Field(default="openrouter/auto")
    openrouter_timeout_seconds: float = Field(default=15.0)

    # Comma-separated list of intents the classifier picks from. Tenants
    # override this to match their business domain (sales pipeline, support
    # triage, telco churn, etc.).
    intents: str = Field(
        default="greeting,question,complaint,cancel,unknown",
        description="Comma-separated allowed intents.",
    )

    log_level: str = Field(default="INFO")

    @property
    def intent_list(self) -> list[str]:
        # Normalize: strip whitespace, drop empties, lowercase.
        return [s.strip().lower() for s in self.intents.split(",") if s.strip()]


settings = Settings()
