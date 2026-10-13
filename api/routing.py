"""Route planning on the edges/nodes graph built by pipeline/build_graph.py."""
from models import Point, Profile, Route, RouteSummary, Segment

MAX_SNAP_M = 200  # further than this from any sidewalk = outside coverage


class OutsideCoverage(Exception):
    pass


# cost in "effective meters": hills, unverified curbs and bad ramps all make an edge feel longer.
# a bad ramp makes its crosswalk cost 4x, so a ~15 m crossing is worth a ~45 m detour to avoid
WEIGHT = """length_m * (1 + abs(grade) / 10)
    * (CASE WHEN curb = 'unknown' THEN 1.5 ELSE 1 END)
    * (CASE WHEN steep_ramp OR poor_ramp THEN 4 ELSE 1 END)"""


def profile_sql(p: Profile) -> str:
    """pgRouting edge query for a profile. -1 cost = impassable in that direction.
    Numbers come from a validated Profile, so formatting them in is safe."""
    blocked = []
    if p.avoid_steps:
        blocked.append("kind = 'steps'")
    if p.require_ramps:
        blocked.append("curb = 'barrier'")
    always = " OR ".join(blocked) or "false"
    up, down = float(p.max_uphill), float(p.max_downhill)
    # forward travel climbs at +grade; reverse travel climbs at -grade
    return f"""
        SELECT id, source, target,
            CASE WHEN {always} OR grade > {up} OR -grade > {down} THEN -1 ELSE {WEIGHT} END AS cost,
            CASE WHEN {always} OR -grade > {up} OR grade > {down} THEN -1 ELSE {WEIGHT} END AS reverse_cost
        FROM edges"""


SHORTEST_SQL = "SELECT id, source, target, length_m AS cost, length_m AS reverse_cost FROM edges"

PATH_SQL = """
SELECT e.id, e.kind, e.curb, e.steep_ramp, e.poor_ramp, e.length_m,
       CASE WHEN r.node = e.source THEN e.grade ELSE -e.grade END AS g,
       ST_AsGeoJSON(CASE WHEN r.node = e.source THEN e.geom ELSE ST_Reverse(e.geom) END) AS gj,
       e.osm_id
FROM pgr_dijkstra(%s, %s::bigint, %s::bigint, true) r
JOIN edges e ON e.id = r.edge
ORDER BY r.seq
"""

SNAP_SQL = """
SELECT id, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326)::geography)
FROM nodes WHERE in_main
ORDER BY geom <-> ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326)
LIMIT 1
"""

CLOSEST_REACHABLE_SQL = """
SELECT n.id, ST_Distance(n.geom::geography, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography) AS gap
FROM pgr_drivingDistance(%s, %s::bigint, 1e9, true) dd
JOIN nodes n ON n.id = dd.node
ORDER BY gap LIMIT 1
"""


def snap(cur, pt: Point, which: str):
    cur.execute(SNAP_SQL, {"lon": pt.lon, "lat": pt.lat})
    row = cur.fetchone()
    if row is None or row[1] > MAX_SNAP_M:
        raise OutsideCoverage(f"Your {which} is outside the area Even covers so far: "
                              "Downtown, SoMa and the Mission in San Francisco.")
    return row


def path(cur, sql, src, dst):
    cur.execute(PATH_SQL, (sql, src, dst))
    return cur.fetchall()


def slope_class(g, p: Profile):
    if g > p.max_uphill or -g > p.max_downhill:
        return "over"
    return "easy" if abs(g) < 3 else "moderate"


def segments(rows, p: Profile) -> list[Segment]:
    """Merge consecutive edges that look the same, so the app draws fewer lines."""
    import json
    out: list[Segment] = []
    for _, kind, curb, _, _, length, g, gj, _ in rows:
        coords = json.loads(gj)["coordinates"]
        cls = slope_class(g, p)
        last = out[-1] if out else None
        if last and last.kind == kind and last.slope == cls and last.curb is None and curb is None:
            last.coordinates += coords[1:]
            last.length_m = round(last.length_m + length, 1)
            if abs(g) > abs(last.grade):
                last.grade = round(g, 1)
        else:
            out.append(Segment(kind=kind, slope=cls, grade=round(g, 1), length_m=round(length, 1),
                               curb=curb, coordinates=coords))
    return out


def summarize(rows, p: Profile) -> tuple[RouteSummary, list[str]]:
    dist = sum(r[5] for r in rows)
    # uphill slows you down, floor at 40% of flat speed
    dur = sum(r[5] / (p.speed_mps * max(0.4, 1 - max(r[6], 0) / 20)) for r in rows)
    grades = [r[6] for r in rows] or [0.0]

    def crosswalks(test):
        # a crosswalk is split into several edges, count each OSM crossing once
        return len({r[8] for r in rows if test(r)})

    s = RouteSummary(
        distance_m=round(dist, 1),
        duration_s=round(dur),
        max_uphill=round(max(max(grades), 0), 1),
        max_downhill=round(max(-min(grades), 0), 1),
        steps=crosswalks(lambda r: r[1] == "steps"),
        barrier_curbs=crosswalks(lambda r: r[2] == "barrier"),
        unknown_curbs=crosswalks(lambda r: r[2] == "unknown"),
        steep_ramps=crosswalks(lambda r: bool(r[3])),
        poor_ramps=crosswalks(lambda r: bool(r[4])),
    )
    breaks = []
    if s.max_uphill > p.max_uphill:
        breaks.append("uphill")
    if s.max_downhill > p.max_downhill:
        breaks.append("downhill")
    if p.avoid_steps and s.steps:
        breaks.append("steps")
    if p.require_ramps and s.barrier_curbs:
        breaks.append("curb")
    return s, breaks


def plan(conn, origin: Point, destination: Point, p: Profile) -> dict:
    with conn.cursor() as cur:
        src, src_d = snap(cur, origin, "starting point")
        dst, dst_d = snap(cur, destination, "destination")
        sql = profile_sql(p)

        rows, reaches, gap = path(cur, sql, src, dst), True, None
        if not rows and src != dst:
            # nothing fits the profile all the way, so get as close as the limits allow
            cur.execute(CLOSEST_REACHABLE_SQL, (destination.lon, destination.lat, sql, src))
            near, gap = cur.fetchone()
            rows, reaches, gap = path(cur, sql, src, near), False, round(gap)

        short_rows = path(cur, SHORTEST_SQL, src, dst)

    routes = []
    for kind, r, ok, g in [("fits_profile", rows, reaches, gap), ("shortest", short_rows, True, None)]:
        summary, breaks = summarize(r, p)
        routes.append(Route(kind=kind, reaches_destination=ok, gap_m=g, fits_profile=not breaks,
                            breaks=breaks, summary=summary, segments=segments(r, p)))
    return {
        "profile": p,
        "origin_snap_m": round(src_d, 1),
        "destination_snap_m": round(dst_d, 1),
        "identical": [x[0] for x in rows] == [x[0] for x in short_rows],
        "routes": routes,
    }
