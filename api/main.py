"""Even API. Run: uv run uvicorn main:app --reload   then open http://localhost:8000/docs"""
import os
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from psycopg_pool import ConnectionPool

import routing
from models import PRESETS, Profile, RouteRequest, RouteResponse

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
