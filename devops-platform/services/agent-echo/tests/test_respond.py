from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app import main
from app.config import settings


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "openrouter_api_key", "sk-test")
    with TestClient(main.app) as client:
        yield client


def test_respond_happy_path(client, monkeypatch):
    fake = AsyncMock(
        return_value={
            "model": "openrouter/auto",
            "choices": [{"message": {"role": "assistant", "content": "hello there"}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }
    )
    monkeypatch.setattr(main, "chat_completion", fake)

    response = client.post("/v1/respond", json={"message": "hi"})
    assert response.status_code == 200
    body = response.json()
    assert body["reply"] == "hello there"
    assert body["model"] == "openrouter/auto"
    assert body["usage"]["total_tokens"] == 15
    assert "request_id" in body


def test_respond_upstream_failure(client, monkeypatch):
    async def boom(*_args, **_kwargs):
        raise main.OpenRouterError("upstream exploded")

    monkeypatch.setattr(main, "chat_completion", boom)

    response = client.post("/v1/respond", json={"message": "hi"})
    assert response.status_code == 502
    assert "upstream exploded" in response.json()["detail"]
