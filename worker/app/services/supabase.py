from typing import Any

import httpx

from app.config import get_settings


class SupabaseRestClient:
    def __init__(self) -> None:
        settings = get_settings()
        self.base_url = settings.supabase_url.rstrip("/")
        self.headers = {
            "apikey": settings.supabase_service_role_key,
            "Authorization": f"Bearer {settings.supabase_service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }

    async def select_by_id(self, table: str, row_id: str) -> dict[str, Any] | None:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(
                f"{self.base_url}/rest/v1/{table}",
                headers=self.headers,
                params={"id": f"eq.{row_id}", "select": "*", "limit": "1"},
            )
            response.raise_for_status()
            rows = response.json()
            return rows[0] if rows else None

    async def get_user(self, jwt: str) -> dict[str, Any] | None:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(
                f"{self.base_url}/auth/v1/user",
                headers={
                    "apikey": self.headers["apikey"],
                    "Authorization": f"Bearer {jwt}",
                },
            )
            if response.status_code in {401, 403}:
                return None
            response.raise_for_status()
            return response.json()

    async def select(
        self,
        table: str,
        params: dict[str, str],
    ) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(
                f"{self.base_url}/rest/v1/{table}",
                headers=self.headers,
                params=params,
            )
            response.raise_for_status()
            return response.json()

    async def insert(self, table: str, payload: dict[str, Any]) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{self.base_url}/rest/v1/{table}",
                headers=self.headers,
                json=payload,
            )
            response.raise_for_status()
            rows = response.json()
            return rows[0] if isinstance(rows, list) and rows else rows

    async def update_by_id(
        self,
        table: str,
        row_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.patch(
                f"{self.base_url}/rest/v1/{table}",
                headers=self.headers,
                params={"id": f"eq.{row_id}"},
                json=payload,
            )
            response.raise_for_status()
            rows = response.json()
            return rows[0] if isinstance(rows, list) and rows else None

    async def delete_by_id(
        self,
        table: str,
        row_id: str,
        extra_params: dict[str, str] | None = None,
    ) -> None:
        params: dict[str, str] = {"id": f"eq.{row_id}"}
        if extra_params:
            params.update(extra_params)
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.delete(
                f"{self.base_url}/rest/v1/{table}",
                headers=self.headers,
                params=params,
            )
            response.raise_for_status()

    async def rpc(self, name: str, payload: dict[str, Any]) -> Any:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{self.base_url}/rest/v1/rpc/{name}",
                headers=self.headers,
                json=payload,
            )
            response.raise_for_status()
            return response.json()
