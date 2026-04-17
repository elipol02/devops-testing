from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app import main
from app.config import settings


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "openrouter_api_key", "sk-test")
    monkeypatch.setattr(
        settings, "intents", "greeting,question,complaint,cancel,unknown"
    )
    with TestClient(main.app) as client:
        yield client


def _fake_body(label: str) -> dict:
    return {
        "model": "openrouter/auto",
        "choices": [{"message": {"role": "assistant", "content": label}}],
        "usage": {"prompt_tokens": 20, "completion_tokens": 1, "total_tokens": 21},
    }


def test_classify_happy_path(client, monkeypatch):
    monkeypatch.setattr(main, "classify", AsyncMock(return_value=_fake_body("complaint")))

    response = client.post("/v1/classify", json={"utterance": "this is terrible"})
    assert response.status_code == 200
    body = response.json()
    assert body["intent"] == "complaint"
    assert body["confident"] is True
    assert body["raw_label"] == "complaint"


def test_classify_out_of_set_falls_back_to_unknown(client, monkeypatch):
    # Model ignores the prompt and returns a label that isn't in the
    # allowed set; the service must NOT trust it blindly.
    monkeypatch.setattr(main, "classify", AsyncMock(return_value=_fake_body("rainbows")))

    response = client.post("/v1/classify", json={"utterance": "???"})
    assert response.status_code == 200
    body = response.json()
    assert body["intent"] == "unknown"
    assert body["confident"] is False
    assert body["raw_label"] == "rainbows"


def test_classify_strips_punctuation(client, monkeypatch):
    monkeypatch.setattr(main, "classify", AsyncMock(return_value=_fake_body("Greeting.")))

    response = client.post("/v1/classify", json={"utterance": "hi there"})
    assert response.status_code == 200
    body = response.json()
    assert body["intent"] == "greeting"
    assert body["confident"] is True


def test_classify_upstream_failure(client, monkeypatch):
    async def boom(*_a, **_kw):
        raise main.OpenRouterError("upstream exploded")

    monkeypatch.setattr(main, "classify", boom)

    response = client.post("/v1/classify", json={"utterance": "hi"})
    assert response.status_code == 502
    assert "upstream exploded" in response.json()["detail"]
