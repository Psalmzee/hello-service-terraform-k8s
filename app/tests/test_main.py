from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root_returns_hello_message():
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert "message" in body
    assert "Hello World" in body["message"]


def test_health_returns_ok():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_ready_returns_ready():
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ready"}


def test_unknown_route_returns_404():
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404
