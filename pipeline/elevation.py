"""Add elevation and slope to every path loaded by load_osm.py.

Usage: uv run elevation.py [area]   (default: sf-core)
Reads osm_ways, rebuilds the segments table, writes data/<area>_slopes.geojson
"""
import json
import math
import os
import sys
from pathlib import Path

import numpy as np
import psycopg
import rasterio
from dotenv import load_dotenv
from rasterio.windows import Window

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(__file__).parent / "data"
SCHEMA = ROOT / "db" / "schema" / "002_segments.sql"

# USGS 3DEP 1/3 arc-second (~10 m) bare-earth DEM, tile covering 37-38N, 122-123W.
# Cloud-optimized, so we only download the window we need.
DEM_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/n38w123/USGS_13_n38w123.tif"

# the DEM is ~10 m per pixel, so grades over shorter runs are mostly noise
MIN_CHUNK_M = 15.0
BUCKETS = [(0, 3), (3, 5), (5, 8), (8, 12), (12, None)]


# ---------- geometry helpers ----------

def dist_m(a, b):
    # equirectangular approximation, plenty accurate at city scale
    lat = math.radians((a[1] + b[1]) / 2)
    dx = (b[0] - a[0]) * 111_320 * math.cos(lat)
    dy = (b[1] - a[1]) * 110_540
    return math.hypot(dx, dy)


def chunk(coords, min_len=MIN_CHUNK_M):
    """Group consecutive vertices into runs of at least min_len meters.
    Returns [(points, length_m)]. A short leftover tail folds into the previous run."""
    out, cur, run = [], [coords[0]], 0.0
    for prev, pt in zip(coords, coords[1:]):
        run += dist_m(prev, pt)
        cur.append(pt)
        if run >= min_len:
            out.append((cur, run))
            cur, run = [pt], 0.0
    if len(cur) > 1:
        if out and run < min_len:
            pts, length = out.pop()
            out.append((pts + cur[1:], length + run))
        else:
            out.append((cur, run))
    return out


# ---------- elevation ----------

def load_dem(bounds, cache):
    """Read the DEM window covering bounds (w, s, e, n), cached as a local GeoTIFF."""
    if cache.exists():
        with rasterio.open(cache) as src:
            return src.read(1).astype("float64"), src.transform

    print("Downloading elevation window from USGS...")
    w, s, e, n = bounds
    with rasterio.open(DEM_URL) as src:
        inv = ~src.transform
        c0, r0 = inv * (w, n)
        c1, r1 = inv * (e, s)
        pad = 3  # a few pixels of margin for interpolation at the edges
        win = Window(math.floor(c0) - pad, math.floor(r0) - pad,
                     math.ceil(c1 - c0) + 2 * pad, math.ceil(r1 - r0) + 2 * pad)
        arr = src.read(1, window=win)
        transform = src.window_transform(win)
        profile = src.profile.copy()

    profile.update(width=arr.shape[1], height=arr.shape[0], transform=transform,
                   driver="GTiff", tiled=False, compress="deflate")
    profile.pop("blockxsize", None)
    profile.pop("blockysize", None)
    with rasterio.open(cache, "w", **profile) as dst:
        dst.write(arr, 1)
    print(f"Cached {cache.name} ({arr.shape[1]}x{arr.shape[0]} px)")
    return arr.astype("float64"), transform


def make_sampler(arr, transform):
    """Bilinear elevation lookup in meters for a (lon, lat)."""
    inv = ~transform
    h, w = arr.shape

    def elev(lon, lat):
        c, r = inv * (lon, lat)
        c, r = c - 0.5, r - 0.5  # shift to pixel centers
        c0 = min(max(int(math.floor(c)), 0), w - 2)
        r0 = min(max(int(math.floor(r)), 0), h - 2)
        fc = min(max(c - c0, 0.0), 1.0)
        fr = min(max(r - r0, 0.0), 1.0)
        top = arr[r0, c0] * (1 - fc) + arr[r0, c0 + 1] * fc
        bot = arr[r0 + 1, c0] * (1 - fc) + arr[r0 + 1, c0 + 1] * fc
        return float(top * (1 - fr) + bot * fr)

    return elev


# ---------- pipeline ----------

def build_segments(ways, elev):
    rows = []
    for osm_id, kind, tags, coords in ways:
        if kind == "elevator":
            continue  # vertical, slope means nothing here
        if tags.get("bridge") or tags.get("tunnel"):
            # bare-earth DEM sees the ground under a bridge, so only trust the ends
            pieces = [(coords, sum(dist_m(a, b) for a, b in zip(coords, coords[1:])))]
        else:
            pieces = chunk(coords)
        for seq, (pts, length) in enumerate(pieces):
            if length < 0.5:
                continue
            z0, z1 = elev(*pts[0]), elev(*pts[-1])
            grade = (z1 - z0) / length * 100
            wkt = "LINESTRING(" + ",".join(f"{x} {y}" for x, y in pts) + ")"
            rows.append((osm_id, seq, kind, length, z0, z1, grade, wkt, pts))
    return rows


def summary(cur):
    walkable = "('sidewalk', 'crossing', 'footway', 'pedestrian')"
    print("\nWalkable km by steepness")
    for lo, hi in BUCKETS:
        cond = f"abs(grade) >= {lo}" + (f" AND abs(grade) < {hi}" if hi else "")
        cur.execute(f"SELECT coalesce(sum(length_m), 0) / 1000 FROM segments WHERE kind IN {walkable} AND {cond}")
        label = f"{lo}-{hi}%" if hi else f"{lo}%+"
        print(f"  {label:<8} {cur.fetchone()[0]:>7.1f} km")

    # sanity check: open these in Google Maps and see if they look steep
    cur.execute("""
        SELECT round(abs(grade)::numeric, 1), round(length_m::numeric),
               round(ST_Y(ST_Centroid(geom))::numeric, 5), round(ST_X(ST_Centroid(geom))::numeric, 5)
        FROM segments WHERE kind = 'sidewalk' AND length_m >= 30
        ORDER BY abs(grade) DESC LIMIT 5
    """)
    print("\nSteepest sidewalk runs (30 m+)")
    for g, l, lat, lon in cur.fetchall():
        print(f"  {g:>5}%  {l:>4} m   {lat},{lon}")


def export_geojson(area, rows):
    feats = [{
        "type": "Feature",
        "properties": {"osm_id": o, "kind": k, "length_m": round(l, 1),
                       "grade": round(g, 1), "abs_grade": round(abs(g), 1)},
        "geometry": {"type": "LineString", "coordinates": pts},
    } for o, _, k, l, _, _, g, _, pts in rows]
    out = DATA_DIR / f"{area}_slopes.geojson"
    out.write_text(json.dumps({"type": "FeatureCollection", "features": feats}))
    print(f"\nPreview: {out.relative_to(ROOT)}  (color by abs_grade)")


def main():
    area = sys.argv[1] if len(sys.argv) > 1 else "sf-core"
    load_dotenv(ROOT / ".env")
    db_url = os.environ.get("DATABASE_URL") or sys.exit("DATABASE_URL missing, copy .env.example to .env")

    with psycopg.connect(db_url) as conn, conn.cursor() as cur:
        cur.execute("SELECT osm_id, kind, tags, ST_AsGeoJSON(geom) FROM osm_ways")
        ways = [(i, k, t, json.loads(g)["coordinates"]) for i, k, t, g in cur.fetchall()]
        if not ways:
            sys.exit("osm_ways is empty, run load_osm.py first")

        # ways can stick out past the fetch box, so size the DEM to the real extent
        cur.execute("SELECT ST_XMin(e), ST_YMin(e), ST_XMax(e), ST_YMax(e) FROM (SELECT ST_Extent(geom) e FROM osm_ways) x")
        DATA_DIR.mkdir(exist_ok=True)
        arr, transform = load_dem(cur.fetchone(), DATA_DIR / f"dem_{area}.tif")
        rows = build_segments(ways, make_sampler(arr, transform))

        cur.execute(SCHEMA.read_text())
        cur.execute("TRUNCATE segments RESTART IDENTITY")
        cur.executemany(
            "INSERT INTO segments (osm_id, seq, kind, length_m, elev_start, elev_end, grade, geom) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, ST_GeomFromText(%s, 4326))",
            [r[:8] for r in rows],
        )
        conn.commit()
        print(f"Built {len(rows)} segments from {len(ways)} ways")
        summary(cur)

    export_geojson(area, rows)


if __name__ == "__main__":
    main()
