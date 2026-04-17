from fastapi.testclient import TestClient

from app.config import settings
from app.main import app


def test_health_ok():
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_requires_api_key(monkeypatch):
    monkeypatch.setattr(settings, "openrouter_api_key", "")
    with TestClient(app) as client:
        response = client.get("/ready")
    assert response.status_code == 503


def test_ready_ok_when_configured(monkeypatch):
    monkeypatch.setattr(settings, "openrouter_api_key", "sk-test")
    with TestClient(app) as client:
        response = client.get("/ready")
    assert response.status_code == 200


def test_metrics_endpoint_exposes_prometheus_format():
    with TestClient(app) as client:
        client.get("/health")
        response = client.get("/metrics")
    assert response.status_code == 200
    assert "agent_echo_requests_total" in response.text
