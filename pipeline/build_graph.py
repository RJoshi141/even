"""Build the routable sidewalk graph: nodes, edges, slope and curb status.

Usage: uv run build_graph.py [area]   (default: sf-core)
Needs load_osm.py and match_curbs.py to have run. Reuses the cached DEM from elevation.py.
"""
import json
import os
import sys
from collections import Counter
from pathlib import Path

import psycopg
from dotenv import load_dotenv

from elevation import chunk, dist_m, load_dem, make_sampler

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(__file__).parent / "data"
SCHEMA = ROOT / "db" / "schema" / "004_graph.sql"

TINY_M = 2.0  # pieces this short get grade 0, the DEM can't resolve them

# demo routes, (lat, lon)
PLACES = {
    "Civic Center BART": (37.77960, -122.41380),
    "24th St Mission BART": (37.75220, -122.41840),
    "Dolores Park": (37.75960, -122.42690),
}
DEMOS = [("Civic Center BART", "24th St Mission BART"), ("Civic Center BART", "Dolores Park")]

CURB_RANK = {"barrier": 3, "unknown": 2, "flush": 1, "ramp": 0}


def key(pt):
    # OSM shares node coordinates exactly between ways, 7 decimals is OSM's precision
    return (round(pt[0], 7), round(pt[1], 7))


def split_at_junctions(ways):
    """Cut every way at vertices shared with another way, so no connection is lost."""
    uses = Counter()
    for _, _, _, coords in ways:
        for k in {key(p) for p in coords}:
            uses[k] += 1
    for osm_id, kind, tags, coords in ways:
        piece = [coords[0]]
        for i, p in enumerate(coords[1:], start=1):
            piece.append(p)
            if i == len(coords) - 1 or uses[key(p)] > 1:
                yield osm_id, kind, tags, coords, piece
                piece = [p]


def build(ways, elev):
    node_ids, nodes, edges = {}, {}, []

    def node(pt):
        k = key(pt)
        if k not in node_ids:
            node_ids[k] = len(node_ids) + 1
            nodes[node_ids[k]] = (pt, elev(*pt))
        return node_ids[k]

    way_ends = {}  # bridges: elevation interpolated between the way's two ends
    for osm_id, kind, tags, full, piece in split_at_junctions(ways):
        if tags.get("bridge") or tags.get("tunnel"):
            if osm_id not in way_ends:
                total = sum(dist_m(a, b) for a, b in zip(full, full[1:])) or 1.0
                way_ends[osm_id] = (full[0], elev(*full[0]), elev(*full[-1]), total, full)
            runs = [(piece, sum(dist_m(a, b) for a, b in zip(piece, piece[1:])))]
        else:
            runs = chunk(piece)

        for pts, length in runs:
            if osm_id in way_ends:
                z0, z1 = bridge_elev(way_ends[osm_id], pts[0]), bridge_elev(way_ends[osm_id], pts[-1])
            else:
                z0, z1 = elev(*pts[0]), elev(*pts[-1])
            grade = 0.0 if (length < TINY_M or kind == "elevator") else (z1 - z0) / length * 100
            edges.append((node(pts[0]), node(pts[-1]), osm_id, kind, length, grade, pts))
    return nodes, edges


def bridge_elev(info, pt):
    start, z_start, z_end, total, full = info
    # distance along the way to the vertex matching pt
    d, k = 0.0, key(pt)
    for a, b in zip(full, full[1:]):
        if key(a) == k:
            break
        d += dist_m(a, b)
    return z_start + (z_end - z_start) * min(d / total, 1.0)


def curb_info(cur):
    cur.execute("""
        SELECT crossing_id, array_agg(status),
               bool_or(source = 'datasf' AND status = 'ramp' AND ramp_slope_range IN (3, 4)),
               bool_or(source = 'datasf' AND status = 'ramp' AND ramp_condition BETWEEN 1 AND 59)
        FROM crossing_ends GROUP BY crossing_id
    """)
    return {cid: (max(sts, key=CURB_RANK.get), steep, poor) for cid, sts, steep, poor in cur.fetchall()}


def write(cur, nodes, edges, curbs):
    cur.execute(SCHEMA.read_text())
    with cur.copy("COPY nodes (id, elev, geom) FROM STDIN") as cp:
        for nid, (pt, z) in nodes.items():
            cp.write_row((nid, z, f"SRID=4326;POINT({pt[0]} {pt[1]})"))
    with cur.copy("COPY edges (source, target, osm_id, kind, length_m, grade, curb, steep_ramp, poor_ramp, geom) FROM STDIN") as cp:
        for s, t, osm_id, kind, length, grade, pts in edges:
            curb, steep, poor = curbs.get(osm_id, (None, False, False)) if kind == "crossing" else (None, False, False)
            line = "SRID=4326;LINESTRING(" + ",".join(f"{x} {y}" for x, y in pts) + ")"
            cp.write_row((s, t, osm_id, kind, length, grade, curb, bool(steep), bool(poor), line))


# routing costs for the demo. The API will build these from a user's profile.
SHORTEST_SQL = "SELECT id, source, target, length_m AS cost, length_m AS reverse_cost FROM edges"

# manual wheelchair: up to 5% uphill, 8% downhill, no steps, no barrier curbs. -1 = impassable
WHEELCHAIR_SQL = """
SELECT id, source, target,
    CASE WHEN kind = 'steps' OR curb = 'barrier' OR grade > 5 OR grade < -8 THEN -1
         ELSE length_m * (1 + abs(grade) / 10) * (CASE WHEN curb = 'unknown' THEN 1.5 ELSE 1 END) END AS cost,
    CASE WHEN kind = 'steps' OR curb = 'barrier' OR -grade > 5 OR -grade < -8 THEN -1
         ELSE length_m * (1 + abs(grade) / 10) * (CASE WHEN curb = 'unknown' THEN 1.5 ELSE 1 END) END AS reverse_cost
FROM edges
"""

ROUTE_STATS = """
SELECT round(sum(e.length_m)::numeric / 1000, 2),
       round(max(CASE WHEN r.node = e.source THEN e.grade ELSE -e.grade END)::numeric, 1),
       round(-min(CASE WHEN r.node = e.source THEN e.grade ELSE -e.grade END)::numeric, 1),
       count(*) FILTER (WHERE e.kind = 'steps'),
       count(*) FILTER (WHERE e.curb = 'barrier'),
       count(*) FILTER (WHERE e.curb = 'unknown')
FROM pgr_dijkstra(%s, %s::bigint, %s::bigint, true) r
JOIN edges e ON e.id = r.edge
"""


def summary(cur):
    cur.execute("SELECT count(*) FROM nodes")
    n_nodes = cur.fetchone()[0]
    cur.execute("SELECT count(*), round(sum(length_m)::numeric / 1000, 1) FROM edges")
    n_edges, km = cur.fetchone()
    print(f"\nGraph: {n_nodes} nodes, {n_edges} edges, {km} km")

    cur.execute(f"""
        CREATE TEMP TABLE cc AS
        SELECT component, node FROM pgr_connectedComponents('{SHORTEST_SQL}')
    """)
    cur.execute("SELECT count(DISTINCT component) FROM cc")
    n_comp = cur.fetchone()[0]
    cur.execute("""
        CREATE TEMP TABLE main_nodes AS
        SELECT node FROM cc WHERE component = (
            SELECT component FROM cc GROUP BY 1 ORDER BY count(*) DESC LIMIT 1)
    """)
    cur.execute("UPDATE nodes SET in_main = true FROM main_nodes m WHERE nodes.id = m.node")
    main = cur.rowcount
    print(f"Connected pieces: {n_comp}. Largest holds {main / n_nodes:.0%} of nodes")
    return main


def nearest_node(cur, lat, lon):
    # only snap to the main connected network, an island node would make routing fail
    cur.execute("""
        SELECT n.id FROM nodes n WHERE n.in_main
        ORDER BY n.geom <-> ST_SetSRID(ST_MakePoint(%s, %s), 4326) LIMIT 1
    """, (lon, lat))
    return cur.fetchone()[0]


# everywhere reachable from src within the profile's limits, nearest to the destination first
CLOSEST_REACHABLE = """
SELECT n.id, round(ST_Distance(n.geom::geography,
                               ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography)::numeric) AS gap_m
FROM pgr_drivingDistance(%s, %s::bigint, 1e9, true) dd
JOIN nodes n ON n.id = dd.node
ORDER BY gap_m LIMIT 1
"""


def demo_routes(cur):
    for a, b in DEMOS:
        src, dst = nearest_node(cur, *PLACES[a]), nearest_node(cur, *PLACES[b])
        print(f"\n{a} -> {b}")
        for label, sql in [("Shortest", SHORTEST_SQL), ("Wheelchair", WHEELCHAIR_SQL)]:
            cur.execute(ROUTE_STATS, (sql, src, dst))
            km, up, down, steps, barriers, unknown = cur.fetchone()
            note = ""
            if km is None:
                # no full route: get as close as the user's limits allow, and say how close
                lat, lon = PLACES[b]
                cur.execute(CLOSEST_REACHABLE, (lon, lat, sql, src))
                near, gap = cur.fetchone()
                cur.execute(ROUTE_STATS, (sql, src, near))
                km, up, down, steps, barriers, unknown = cur.fetchone()
                note = f"   (can't reach it, closest point is {gap} m away)"
            print(f"  {label:<11} {km} km   steepest up {up}%  down {down}%   "
                  f"steps {steps}  barrier curbs {barriers}  unknown curbs {unknown}{note}")


def main():
    area = sys.argv[1] if len(sys.argv) > 1 else "sf-core"
    load_dotenv(ROOT / ".env")
    db_url = os.environ.get("DATABASE_URL") or sys.exit("DATABASE_URL missing, copy .env.example to .env")
    dem_path = DATA_DIR / f"dem_{area}.tif"
    if not dem_path.exists():
        sys.exit(f"{dem_path.name} not found, run elevation.py first")

    with psycopg.connect(db_url) as conn, conn.cursor() as cur:
        cur.execute("SELECT osm_id, kind, tags, ST_AsGeoJSON(geom) FROM osm_ways")
        ways = [(i, k, t, json.loads(g)["coordinates"]) for i, k, t, g in cur.fetchall()]
        cur.execute("SELECT to_regclass('crossing_ends') IS NOT NULL")
        curbs = curb_info(cur) if cur.fetchone()[0] else {}
        if not curbs:
            print("No curb data found, run match_curbs.py first for curb-aware routing")

        arr, transform = load_dem(None, dem_path)
        nodes, edges = build(ways, make_sampler(arr, transform))
        write(cur, nodes, edges, curbs)
        conn.commit()

        summary(cur)
        conn.commit()  # keep the in_main flags for the API
        demo_routes(cur)


if __name__ == "__main__":
    main()
