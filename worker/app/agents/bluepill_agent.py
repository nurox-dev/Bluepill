from typing import Any

from app.config import get_settings

try:
    from agents import Agent, AsyncOpenAI, OpenAIProvider, RunConfig, Runner
except ImportError:  # pragma: no cover - lets scaffolding run before deps install.
    Agent = None
    AsyncOpenAI = None
    OpenAIProvider = None
    RunConfig = None
    Runner = None


SYSTEM_INSTRUCTIONS = """
You are the Project BluePill agent. Answer the user's latest message directly.
Use stored user context only when it is clearly relevant to goals, mission,
tasks, calendar, habits, check-ins, progress, planning, motivation, personal
patterns, or an explicit personalization request.

For simple factual questions, math, definitions, coding help, general
knowledge, or casual chat, answer normally without mentioning the user's
mission, profile, progress, weaknesses, tasks, habits, or next action.

Ask for approval before actions that mutate external systems.
"""


def _model_runtime(settings: Any) -> tuple[str, Any | None]:
    provider_name = settings.ai_provider.strip().lower()

    if provider_name == "openrouter":
        api_key = settings.openrouter_api_key or settings.openai_api_key
        model = settings.openrouter_model
        base_url = settings.openrouter_base_url
        headers = {
            "HTTP-Referer": settings.openrouter_site_url,
            "X-Title": settings.openrouter_app_name,
        }
    else:
        api_key = settings.openai_api_key
        model = settings.openai_model
        base_url = settings.openai_base_url
        headers = {}

    if not api_key or AsyncOpenAI is None or OpenAIProvider is None or RunConfig is None:
        return model, None

    client = AsyncOpenAI(
        api_key=api_key,
        base_url=base_url,
        default_headers=headers or None,
    )
    provider = OpenAIProvider(openai_client=client, use_responses=False)
    return model, RunConfig(model_provider=provider)


async def run_bluepill_agent(
    *,
    message: str,
    user_context: dict[str, Any],
    memories: list[dict[str, Any]],
    conversation_history: list[dict[str, Any]] | None = None,
    attachments: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    settings = get_settings()
    prompt = {
        "message": message,
        "conversation_history": conversation_history or [],
        "user_context": user_context,
        "memories": memories,
        "attachments": attachments or [],
    }

    if Agent is None or Runner is None:
        return {
            "text": "Agent dependencies are not installed in this worker yet.",
            "tool_names": [],
            "raw": {"prompt": prompt},
        }

    model, run_config = _model_runtime(settings)
    agent = Agent(
        name="BluePill Agent",
        instructions=SYSTEM_INSTRUCTIONS,
        model=model,
    )
    result = await Runner.run(agent, str(prompt), run_config=run_config)

    return {
        "text": result.final_output,
        "tool_names": [],
        "raw": {"final_output": result.final_output},
    }
