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


def test_inspect_near_sidewalk(client):
    r = client.get("/inspect", params={"lat": CIVIC_CENTER["lat"], "lon": CIVIC_CENTER["lon"]})
    assert r.status_code == 200
    body = r.json()
    if body["found"]:
        assert body["grade"] is not None and body["verdict"]


def test_inspect_far_away(client):
    assert client.get("/inspect", params=OAKLAND).json()["found"] is False


def test_network_small_view(client):
    r = client.get("/network", params={"min_lat": 37.775, "min_lon": -122.418,
                                       "max_lat": 37.782, "max_lon": -122.410})
    assert r.status_code == 200 and r.json()["too_large"] is False


def test_network_too_large(client):
    r = client.get("/network", params={"min_lat": 37.70, "min_lon": -122.50,
                                       "max_lat": 37.80, "max_lon": -122.38})
    assert r.json()["too_large"] is True


def test_route_has_directions(client):
    r = client.post("/route", json={"origin": CIVIC_CENTER, "destination": MISSION_24TH}).json()
    steps = r["routes"][0]["steps"]
    assert steps, "expected turn-by-turn steps"
    assert steps[0]["maneuver"] == "start" and steps[-1]["maneuver"] == "arrive"
