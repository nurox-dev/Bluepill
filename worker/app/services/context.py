from typing import Any

from app.services.supabase import SupabaseRestClient


CALENDAR_EVENTS_SCOPE = "https://www.googleapis.com/auth/calendar.events"


def _google_calendar_context(
    connected_accounts: list[dict[str, Any]],
) -> dict[str, Any]:
    for account in connected_accounts:
        scopes = account.get("scopes") or []
        metadata = account.get("metadata") or {}
        if (
            account.get("provider") == "google"
            and account.get("status") == "connected"
            and CALENDAR_EVENTS_SCOPE in scopes
        ):
            events = metadata.get("upcoming_events") if isinstance(metadata, dict) else []
            return {
                "connected": True,
                "account_email": account.get("account_email"),
                "scopes": scopes,
                "synced_at": metadata.get("synced_at")
                if isinstance(metadata, dict)
                else None,
                "events": events if isinstance(events, list) else [],
            }

    return {"connected": False, "events": []}


async def load_user_context(
    supabase: SupabaseRestClient,
    user_id: str,
) -> dict[str, Any]:
    profile_rows = await supabase.select(
        "users_profile",
        {"user_id": f"eq.{user_id}", "select": "*", "limit": "1"},
    )
    tasks = await supabase.select(
        "tasks",
        {
            "user_id": f"eq.{user_id}",
            "select": "*",
            "order": "due_date.asc.nullslast,created_at.desc",
            "limit": "50",
        },
    )
    goals = await supabase.select(
        "goals",
        {"user_id": f"eq.{user_id}", "select": "*", "limit": "50"},
    )
    habits = await supabase.select(
        "habits",
        {"user_id": f"eq.{user_id}", "select": "*", "limit": "50"},
    )
    connected_accounts = await supabase.select(
        "connected_accounts",
        {
            "user_id": f"eq.{user_id}",
            "select": "provider,account_label,account_email,scopes,status,metadata,updated_at",
            "order": "updated_at.desc",
            "limit": "20",
        },
    )
    ai_checkin_streak = await supabase.select(
        "ai_checkin_streaks",
        {"user_id": f"eq.{user_id}", "select": "*", "limit": "1"},
    )

    return {
        "profile": profile_rows[0] if profile_rows else None,
        "tasks": tasks,
        "goals": goals,
        "habits": habits,
        "ai_checkin_streak": ai_checkin_streak[0] if ai_checkin_streak else None,
        "connected_accounts": connected_accounts,
        "google_calendar": _google_calendar_context(connected_accounts),
    }
