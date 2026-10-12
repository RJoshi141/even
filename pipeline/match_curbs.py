"""Work out the curb at both ends of every crosswalk.

Combines DataSF's ramp inventory with OSM kerb tags. DataSF wins when it has
a definite answer (it's a city survey, updated yearly); OSM fills the gaps.

DataSF stores every ramp at its intersection's center point and labels the
corner (NE, SW...). So we find the intersection nearest each crosswalk end,
then pick the corner whose compass direction matches the end's bearing.

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

INTERSECTION_RADIUS_M = 35  # crosswalk ends sit 10-30 m from the center on wide streets; blocks are 80 m+
MAX_CORNER_ANGLE = 67.5     # end's bearing must roughly point at the labeled corner
KERB_RADIUS_M = 4      # OSM kerb nodes are usually on or right next to the crossing end


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
            (r.get("curbreturnloc") or "").strip().upper() or None, r.get("positiononreturn"),
            to_int(r.get("crexist")) == 1, to_int(r.get("conditionscore")),
            to_int(r.get("sloperangeid")), None if lip is None else lip == 1,
            f"POINT({lon} {lat})",
        )


# one row per labeled corner of each intersection, summarizing its ramps
CORNERS_SQL = """
CREATE TEMP TABLE corners AS
SELECT cnn, corner,
    ST_Centroid(ST_Collect(geom)) AS center,
    CASE corner WHEN 'N' THEN 0 WHEN 'NE' THEN 45 WHEN 'E' THEN 90 WHEN 'SE' THEN 135
                WHEN 'S' THEN 180 WHEN 'SW' THEN 225 WHEN 'W' THEN 270 WHEN 'NW' THEN 315 END AS bearing,
    bool_and(cr_exist) AS all_exist,
    bool_or(cr_exist) AS any_exist,
    bool_or(condition_score = 0) AS any_missing,
    min(condition_score) FILTER (WHERE cr_exist) AS worst_condition,
    max(slope_range) FILTER (WHERE cr_exist AND slope_range < 5) AS steepest_range
FROM curb_ramps
WHERE cnn IS NOT NULL AND corner IN ('N','NE','E','SE','S','SW','W','NW')
GROUP BY cnn, corner;
CREATE INDEX ON corners (cnn);
"""

MATCH_SQL = f"""
INSERT INTO crossing_ends (crossing_id, which, status, source, osm_kerb, cnn, corner,
                           datasf_corner, corner_angle, ramp_condition, ramp_slope_range, geom)
SELECT e.osm_id, e.which,
    CASE
        WHEN r.all_exist THEN 'ramp'
        WHEN NOT r.any_exist AND r.any_missing THEN 'barrier'   -- city says needed and missing
        WHEN k.kerb = 'lowered' THEN 'ramp'
        WHEN k.kerb IN ('flush', 'no') THEN 'flush'
        WHEN k.kerb = 'raised' THEN 'barrier'
        ELSE 'unknown'                                          -- mixed corners, kerb=yes, no data
    END,
    CASE
        WHEN r.all_exist OR (NOT r.any_exist AND r.any_missing) THEN 'datasf'
        WHEN k.kerb IN ('lowered', 'flush', 'no', 'raised') THEN 'osm'
        ELSE 'none'
    END,
    k.kerb, r.cnn, r.corner,
    CASE
        WHEN r.cnn IS NULL THEN NULL
        WHEN r.all_exist THEN 'ramp'
        WHEN NOT r.any_exist AND r.any_missing THEN 'missing'
        WHEN r.any_exist THEN 'mixed'
        ELSE 'none'                                             -- not needed / not possible
    END,
    r.angle, r.worst_condition, r.steepest_range, e.pt
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
    -- the corner of the nearest intersection that this end points toward
    SELECT c.*, a.angle
    FROM (
        SELECT cr.cnn FROM curb_ramps cr
        WHERE ST_DWithin(cr.geom::geography, e.pt::geography, {INTERSECTION_RADIUS_M})
        ORDER BY cr.geom <-> e.pt LIMIT 1
    ) x
    JOIN corners c ON c.cnn = x.cnn
    CROSS JOIN LATERAL (
        SELECT degrees(acos(least(1, greatest(-1,
            cos(radians(c.bearing) - ST_Azimuth(c.center::geography, e.pt::geography)))))) AS angle
    ) a
    WHERE a.angle < {MAX_CORNER_ANGLE}
    ORDER BY a.angle LIMIT 1
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

    cur.execute("SELECT datasf_corner, count(*) FROM crossing_ends WHERE cnn IS NOT NULL GROUP BY 1 ORDER BY 2 DESC")
    print("Matched to a city corner: " + ", ".join(f"{c} {n}" for c, n in cur.fetchall()))

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

        # pad the area a little so corners on the edge still find their ramps
        cur.execute("""
            SELECT ST_XMin(e) - 0.001, ST_YMin(e) - 0.001, ST_XMax(e) + 0.001, ST_YMax(e) + 0.001
            FROM (SELECT ST_Extent(geom) e FROM osm_ways) x
        """)
        rows = list(ramp_rows(json.loads(src.read_text()), cur.fetchone()))
        cur.executemany(
            "INSERT INTO curb_ramps (locid, cnn, location, corner, position, cr_exist, condition_score, "
            "slope_range, lip_too_high, geom) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, ST_GeomFromText(%s, 4326))",
            rows,
        )
        print(f"Loaded {len(rows)} curb ramps in the area")

        cur.execute(CORNERS_SQL)
        cur.execute(MATCH_SQL)
        conn.commit()
        summary(cur)
        export_geojson(cur, area)


if __name__ == "__main__":
    main()
