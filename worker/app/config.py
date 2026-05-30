from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    supabase_url: str = Field(alias="SUPABASE_URL")
    supabase_service_role_key: str = Field(alias="SUPABASE_SERVICE_ROLE_KEY")
    supabase_anon_key: str = Field(alias="SUPABASE_ANON_KEY")
    worker_shared_secret: str = Field(alias="WORKER_SHARED_SECRET")
    mcp_enabled: bool = Field(default=True, alias="MCP_ENABLED")
    mcp_worker_base_url: str = Field(
        default="http://localhost:10000", alias="MCP_WORKER_BASE_URL"
    )
    mcp_public_url: str = Field(
        default="http://localhost:10000/mcp", alias="MCP_PUBLIC_URL"
    )
    agent_daily_run_limit: int = Field(default=50, alias="AGENT_DAILY_RUN_LIMIT")
    ai_provider: str = Field(default="openai", alias="AI_PROVIDER")
    openai_api_key: str | None = Field(default=None, alias="OPENAI_API_KEY")
    openai_base_url: str = Field(
        default="https://api.openai.com/v1",
        alias="OPENAI_BASE_URL",
    )
    openai_model: str = Field(default="gpt-4o-mini", alias="OPENAI_MODEL")
    openrouter_api_key: str | None = Field(default=None, alias="OPENROUTER_API_KEY")
    openrouter_model: str = Field(
        default="openai/gpt-4o-mini",
        alias="OPENROUTER_MODEL",
    )
    openrouter_base_url: str = Field(
        default="https://openrouter.ai/api/v1",
        alias="OPENROUTER_BASE_URL",
    )
    openrouter_site_url: str = Field(
        default="https://project-bluepill.web.app",
        alias="OPENROUTER_SITE_URL",
    )
    openrouter_app_name: str = Field(
        default="Project BluePill",
        alias="OPENROUTER_APP_NAME",
    )
    cors_allow_origins: str = Field(default="*", alias="CORS_ALLOW_ORIGINS")
    cron_scheduler_enabled: bool = Field(
        default=True,
        alias="CRON_SCHEDULER_ENABLED",
    )
    cron_scheduler_interval_seconds: int = Field(
        default=30,
        alias="CRON_SCHEDULER_INTERVAL_SECONDS",
    )
    cron_scheduler_batch_size: int = Field(
        default=10,
        alias="CRON_SCHEDULER_BATCH_SIZE",
    )
    cron_scheduler_lock_ttl_seconds: int = Field(
        default=600,
        alias="CRON_SCHEDULER_LOCK_TTL_SECONDS",
    )

    model_config = SettingsConfigDict(
        env_file="../server.env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
