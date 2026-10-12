"""Work out the curb at both ends of every crosswalk.

Combines DataSF's ramp inventory with OSM kerb tags. DataSF wins when it has
a definite answer (it's a city survey, updated yearly); OSM fills the gaps.

Usage: uv run match_curbs.py [area]   (default: sf-core)
"""
import json
import os
import sys
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(__file__).parent / "data"
SCHEMA = ROOT / "db" / "schema" / "003_curbs.sql"

RAMP_RADIUS_M = 10   # DataSF points sit on the corner, OSM crossings end at the curb
KERB_RADIUS_M = 4    # OSM kerb nodes are usually on or right next to the crossing end


def to_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def ramp_rows(raw, bounds):
    w, s, e, n = bounds
    for r in raw:
        lat, lon = r.get("latitude"), r.get("longitude")
        if lat is None or lon is None:
            continue
        lat, lon = float(lat), float(lon)
        if not (s <= lat <= n and w <= lon <= e):
            continue  # keep only ramps inside our area
        lip = to_int(r.get("liptoohigh"))
        yield (
            r["locid"], to_int(r.get("cnn")), r.get("locationdescription"),
            to_int(r.get("crexist")) == 1, to_int(r.get("conditionscore")),
            to_int(r.get("sloperangeid")), None if lip is None else lip == 1,
            f"POINT({lon} {lat})",
        )


MATCH_SQL = f"""
INSERT INTO crossing_ends (crossing_id, which, status, source, osm_kerb,
                           ramp_id, ramp_dist_m, ramp_condition, ramp_slope_range, geom)
SELECT e.osm_id, e.which,
    CASE
        WHEN r.cr_exist THEN 'ramp'
        WHEN r.condition_score = 0 THEN 'barrier'      -- city says a ramp is needed and missing
        WHEN k.kerb = 'lowered' THEN 'ramp'
        WHEN k.kerb IN ('flush', 'no') THEN 'flush'
        WHEN k.kerb = 'raised' THEN 'barrier'
        ELSE 'unknown'                                 -- includes kerb=yes, rolled, no data
    END,
    CASE
        WHEN r.cr_exist OR r.condition_score = 0 THEN 'datasf'
        WHEN k.kerb IN ('lowered', 'flush', 'no', 'raised') THEN 'osm'
        ELSE 'none'
    END,
    k.kerb, r.id, r.dist, r.condition_score, r.slope_range, e.pt
FROM (
    SELECT osm_id, 'start' AS which, ST_StartPoint(geom) AS pt FROM osm_ways WHERE kind = 'crossing'
    UNION ALL
    SELECT osm_id, 'end', ST_EndPoint(geom) FROM osm_ways WHERE kind = 'crossing'
) e
LEFT JOIN LATERAL (
    -- nearest OSM kerb node (KNN on the gist index, then a real-meters cutoff)
    SELECT p.kerb FROM osm_points p
    WHERE p.kind = 'kerb' AND ST_DWithin(p.geom::geography, e.pt::geography, {KERB_RADIUS_M})
    ORDER BY p.geom <-> e.pt LIMIT 1
) k ON true
LEFT JOIN LATERAL (
    SELECT c.id, c.cr_exist, c.condition_score, c.slope_range,
           ST_Distance(c.geom::geography, e.pt::geography) AS dist
    FROM curb_ramps c
    WHERE ST_DWithin(c.geom::geography, e.pt::geography, {RAMP_RADIUS_M})
    ORDER BY c.geom <-> e.pt LIMIT 1
) r ON true
"""


def summary(cur):
    cur.execute("SELECT count(*) FROM crossing_ends")
    total = cur.fetchone()[0]

    cur.execute("SELECT status, count(*) FROM crossing_ends GROUP BY 1 ORDER BY 2 DESC")
    print(f"\nCrosswalk ends: {total}")
    for status, n in cur.fetchall():
        print(f"  {status:<9} {n:>6}  {n / total:>5.0%}")

    cur.execute("""
        SELECT count(*) FILTER (WHERE osm_kerb IN ('lowered','flush','no','raised')),
               count(*) FILTER (WHERE status <> 'unknown')
        FROM crossing_ends
    """)
    osm_known, known = cur.fetchone()
    print(f"\nCurb known: OSM alone {osm_known / total:.0%}  ->  with DataSF {known / total:.0%}")

    cur.execute("""
        SELECT count(*) FROM crossing_ends
        WHERE (source = 'datasf' AND status = 'ramp' AND osm_kerb = 'raised')
           OR (source = 'datasf' AND status = 'barrier' AND osm_kerb IN ('lowered','flush','no'))
    """)
    print(f"OSM and DataSF disagree: {cur.fetchone()[0]}")

    cur.execute("""
        SELECT count(*) FILTER (WHERE ramp_slope_range IN (3, 4)),
               count(*) FILTER (WHERE ramp_condition BETWEEN 1 AND 59)
        FROM crossing_ends WHERE status = 'ramp' AND source = 'datasf'
    """)
    steep, poor = cur.fetchone()
    print(f"Ramps steeper than 8.33%: {steep}   Ramps in poor condition (<60/100): {poor}")


def export_geojson(cur, area):
    cur.execute("""
        SELECT crossing_id, which, status, source, ramp_condition, ramp_slope_range,
               ST_X(geom), ST_Y(geom)
        FROM crossing_ends
    """)
    feats = [{
        "type": "Feature",
        "properties": {"crossing_id": c, "which": w, "status": st, "source": src,
                       "condition": cond, "slope_range": sr},
        "geometry": {"type": "Point", "coordinates": [x, y]},
    } for c, w, st, src, cond, sr, x, y in cur.fetchall()]
    out = DATA_DIR / f"{area}_curbs.geojson"
    out.write_text(json.dumps({"type": "FeatureCollection", "features": feats}))
    print(f"\nPreview: {out.relative_to(ROOT)}  (color by status)")


def main():
    area = sys.argv[1] if len(sys.argv) > 1 else "sf-core"
    src = DATA_DIR / "curb_ramps.json"
    if not src.exists():
        sys.exit("curb_ramps.json not found, run fetch_curb_ramps.py first")

    load_dotenv(ROOT / ".env")
    db_url = os.environ.get("DATABASE_URL") or sys.exit("DATABASE_URL missing, copy .env.example to .env")

    with psycopg.connect(db_url) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM osm_ways WHERE kind = 'crossing'")
        if not cur.fetchone()[0]:
            sys.exit("No crossings loaded, run load_osm.py first")

        cur.execute(SCHEMA.read_text())
        cur.execute("TRUNCATE curb_ramps, crossing_ends RESTART IDENTITY")

        # pad the area a little so corners on the edge still find their ramps
        cur.execute("""
            SELECT ST_XMin(e) - 0.001, ST_YMin(e) - 0.001, ST_XMax(e) + 0.001, ST_YMax(e) + 0.001
            FROM (SELECT ST_Extent(geom) e FROM osm_ways) x
        """)
        rows = list(ramp_rows(json.loads(src.read_text()), cur.fetchone()))
        cur.executemany(
            "INSERT INTO curb_ramps (locid, cnn, location, cr_exist, condition_score, slope_range, lip_too_high, geom) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, ST_GeomFromText(%s, 4326))",
            rows,
        )
        print(f"Loaded {len(rows)} curb ramps in the area")

        cur.execute(MATCH_SQL)
        conn.commit()
        summary(cur)
        export_geojson(cur, area)


if __name__ == "__main__":
    main()
