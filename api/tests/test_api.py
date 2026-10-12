"""Integration tests. Need the local db up and the pipeline run (docker compose up -d)."""
import pytest
from fastapi.testclient import TestClient

from main import app

CIVIC_CENTER = {"lat": 37.7796, "lon": -122.4138}
MISSION_24TH = {"lat": 37.7522, "lon": -122.4184}
OAKLAND = {"lat": 37.8044, "lon": -122.2712}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:  # runs startup, opens the db pool
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["edges"] > 0


def test_profiles(client):
    assert "manual_wheelchair" in client.get("/profiles").json()


def test_route_fits_profile(client):
    r = client.post("/route", json={"origin": CIVIC_CENTER, "destination": MISSION_24TH})
    assert r.status_code == 200
    fits, shortest = r.json()["routes"]
    assert fits["kind"] == "fits_profile" and shortest["kind"] == "shortest"
    if fits["reaches_destination"]:
        assert fits["fits_profile"]
        assert fits["summary"]["max_uphill"] <= 5
        assert fits["summary"]["steps"] == 0


def test_custom_profile_overrides_preset(client):
    body = {"origin": CIVIC_CENTER, "destination": MISSION_24TH,
            "profile": {"max_uphill": 2, "max_downhill": 2}}
    r = client.post("/route", json=body)
    assert r.json()["profile"]["max_uphill"] == 2


def test_outside_coverage(client):
    r = client.post("/route", json={"origin": OAKLAND, "destination": MISSION_24TH})
    assert r.status_code == 422
