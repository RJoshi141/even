"""Even API. Run: uv run uvicorn main:app --reload   then open http://localhost:8000/docs"""
import os
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from psycopg_pool import ConnectionPool

import routing
from models import (PRESETS, InspectResponse, NetworkResponse, Point, PresetName, Profile,
                    RouteRequest, RouteResponse)

load_dotenv(Path(__file__).resolve().parent.parent / ".env")
pool: ConnectionPool | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    pool = ConnectionPool(os.environ["DATABASE_URL"], min_size=1, max_size=5, open=True)
    yield
    pool.close()


app = FastAPI(title="Even API", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/health")
def health():
    with pool.connection() as conn:
        edges = conn.execute("SELECT count(*) FROM edges").fetchone()[0]
    return {"ok": True, "edges": edges}


@app.get("/profiles", response_model=dict[str, Profile])
def profiles():
    return PRESETS


@app.post("/route", response_model=RouteResponse)
def route(req: RouteRequest):
    profile = req.profile or PRESETS[req.preset]
    try:
        with pool.connection() as conn:
            return routing.plan(conn, req.origin, req.destination, profile)
    except routing.OutsideCoverage as e:
        raise HTTPException(status_code=422, detail=str(e))


@app.get("/inspect", response_model=InspectResponse)
def inspect(lat: float, lon: float, preset: PresetName = "manual_wheelchair"):
    """The path nearest a tapped spot, judged for the given profile."""
    with pool.connection() as conn:
        return routing.inspect(conn, Point(lat=lat, lon=lon), PRESETS[preset])


@app.get("/network", response_model=NetworkResponse)
def network(min_lat: float, min_lon: float, max_lat: float, max_lon: float,
            preset: PresetName = "manual_wheelchair"):
    """Every path in a map view, classed by steepness for the given profile."""
    with pool.connection() as conn:
        return routing.network(conn, min_lon, min_lat, max_lon, max_lat, PRESETS[preset])
