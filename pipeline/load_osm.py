"""Load a fetched OSM file into PostGIS and export a GeoJSON preview.

Usage: uv run load_osm.py [area]   (default: sf-core)
Needs DATABASE_URL in the repo's .env
"""
import json
import os
import sys
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(__file__).parent / "data"
SCHEMA = ROOT / "db" / "schema" / "001_osm.sql"


def way_kind(tags):
    hw = tags.get("highway")
    if hw in ("steps", "elevator", "pedestrian"):
        return hw
    if tags.get("footway") in ("sidewalk", "crossing"):
        return tags["footway"]
    return "footway"  # generic paths: plazas, park paths, alleys


def point_kind(tags):
    # elevators matter most for routing, then curb info, then plain crossings
    if tags.get("highway") == "elevator":
        return "elevator"
    if "kerb" in tags:
        return "kerb"
    return "crossing"


def parse(elements):
    ways, points = [], []
    for e in elements:
        tags = e.get("tags", {})
        if e["type"] == "way":
            coords = [(p["lon"], p["lat"]) for p in e.get("geometry", []) if p]
            if len(coords) < 2:
                continue
            wkt = "LINESTRING(" + ",".join(f"{x} {y}" for x, y in coords) + ")"
            ways.append((e["id"], way_kind(tags), tags, wkt, coords))
        elif e["type"] == "node":
            wkt = f"POINT({e['lon']} {e['lat']})"
            points.append((e["id"], point_kind(tags), tags.get("kerb"), tags, wkt, (e["lon"], e["lat"])))
    return ways, points


def load(conn, ways, points):
    with conn.cursor() as cur:
        cur.execute(SCHEMA.read_text())
        cur.execute("TRUNCATE osm_ways, osm_points")
        cur.executemany(
            "INSERT INTO osm_ways (osm_id, kind, tags, geom) VALUES (%s, %s, %s, ST_GeomFromText(%s, 4326))",
            [(i, k, json.dumps(t), w) for i, k, t, w, _ in ways],
        )
        cur.executemany(
            "INSERT INTO osm_points (osm_id, kind, kerb, tags, geom) VALUES (%s, %s, %s, %s, ST_GeomFromText(%s, 4326))",
            [(i, k, kb, json.dumps(t), w) for i, k, kb, t, w, _ in points],
        )
    conn.commit()


def summary(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT kind, count(*), round(sum(ST_Length(geom::geography))::numeric / 1000, 1)
            FROM osm_ways GROUP BY kind ORDER BY 3 DESC
        """)
        print("\nWays            count      km")
        for kind, n, km in cur.fetchall():
            print(f"  {kind:<12} {n:>7} {km:>7}")

        cur.execute("""
            SELECT kind, coalesce(kerb, '-'), count(*)
            FROM osm_points GROUP BY 1, 2 ORDER BY 1, 3 DESC
        """)
        print("\nPoints          kerb       count")
        for kind, kerb, n in cur.fetchall():
            print(f"  {kind:<12} {kerb:<10} {n:>5}")


def export_geojson(area, ways, points):
    # quick preview file: drag it into geojson.io or kepler.gl
    features = [
        {"type": "Feature", "properties": {"osm_id": i, "kind": k},
         "geometry": {"type": "LineString", "coordinates": c}}
        for i, k, _, _, c in ways
    ] + [
        {"type": "Feature", "properties": {"osm_id": i, "kind": k, "kerb": kb},
         "geometry": {"type": "Point", "coordinates": c}}
        for i, k, kb, _, _, c in points
    ]
    out = DATA_DIR / f"{area}.geojson"
    out.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    print(f"\nPreview: {out.relative_to(ROOT)}")


def main():
    area = sys.argv[1] if len(sys.argv) > 1 else "sf-core"
    src = DATA_DIR / f"osm_{area}.json"
    if not src.exists():
        sys.exit(f"{src.name} not found, run fetch_osm.py {area} first")

    load_dotenv(ROOT / ".env")
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        sys.exit("DATABASE_URL missing, copy .env.example to .env")

    ways, points = parse(json.loads(src.read_text())["elements"])
    with psycopg.connect(db_url) as conn:
        load(conn, ways, points)
        summary(conn)
    export_geojson(area, ways, points)


if __name__ == "__main__":
    main()
