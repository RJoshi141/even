"""Route planning on the edges/nodes graph built by pipeline/build_graph.py."""
import json

import math

from models import InspectResponse, NetworkLine, NetworkResponse, Point, Profile, Route, RouteSummary, Segment, Step

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
       ST_AsGeoJSON(CASE WHEN r.node = e.source THEN e.geom ELSE ST_Reverse(e.geom) END, 6) AS gj,
       e.osm_id, w.tags->>'surface'
FROM pgr_dijkstra(%s, %s::bigint, %s::bigint, true) r
JOIN edges e ON e.id = r.edge
JOIN osm_ways w ON w.osm_id = e.osm_id
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
    out: list[Segment] = []
    for _, kind, curb, steep, poor, length, g, gj, _, _ in rows:
        coords = json.loads(gj)["coordinates"]
        cls = slope_class(g, p)
        last = out[-1] if out else None
        if last and last.kind == kind and last.slope == cls and last.curb is None and curb is None \
                and not (steep or poor):
            last.coordinates += coords[1:]
            last.length_m = round(last.length_m + length, 1)
            if abs(g) > abs(last.grade):
                last.grade = round(g, 1)
        else:
            out.append(Segment(kind=kind, slope=cls, grade=round(g, 1), length_m=round(length, 1),
                               curb=curb, ramp_issue=bool(steep or poor), coordinates=coords))
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
                            breaks=breaks, summary=summary, segments=segments(r, p),
                            steps=directions(r, p, reaches=ok)))
    return {
        "profile": p,
        "origin_snap_m": round(src_d, 1),
        "destination_snap_m": round(dst_d, 1),
        "identical": [x[0] for x in rows] == [x[0] for x in short_rows],
        "routes": routes,
    }


# ---------- tap to inspect ----------

INSPECT_SQL = """
SELECT e.kind, e.grade, e.length_m, e.curb, (e.steep_ramp OR e.poor_ramp),
       w.tags->>'surface', w.tags->>'name',
       ST_Distance(e.geom::geography, ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326)::geography),
       ST_AsGeoJSON(e.geom, 6)
FROM edges e JOIN osm_ways w ON w.osm_id = e.osm_id
ORDER BY e.geom <-> ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326)
LIMIT 1
"""

INSPECT_RADIUS_M = 25


def inspect(conn, pt: Point, p: Profile) -> InspectResponse:
    with conn.cursor() as cur:
        cur.execute(INSPECT_SQL, {"lon": pt.lon, "lat": pt.lat})
        row = cur.fetchone()
    if row is None or row[7] > INSPECT_RADIUS_M:
        return InspectResponse(found=False, point=pt)

    kind, g, length, curb, ramp_issue, surface, name, _, gj = row
    steep = abs(g)
    blocked = (kind == "steps" and p.avoid_steps) or (curb == "barrier" and p.require_ramps)
    fwd = g <= p.max_uphill and -g <= p.max_downhill
    rev = -g <= p.max_uphill and g <= p.max_downhill

    if kind == "steps" and p.avoid_steps:
        access, verdict = "none", "Steps, not usable with your profile"
    elif blocked:
        access, verdict = "none", "No curb ramp here, not usable with your profile"
    elif fwd and rev:
        access, verdict = "both_ways", "Works both ways for you"
    elif fwd or rev:
        # one direction fails: say which one still works
        downhill_ok = steep <= p.max_downhill
        access = "one_way"
        verdict = "Only works going downhill for you" if downhill_ok else "Only works going uphill for you"
    else:
        access, verdict = "none", "Too steep for you either way"

    if ramp_issue and access != "none":
        verdict += ". A ramp here is steep or worn"

    return InspectResponse(
        found=True, point=pt, kind=kind, name=name, surface=surface,
        grade=round(steep, 1), length_m=round(length, 1), curb=curb, ramp_issue=bool(ramp_issue),
        access=access, verdict=verdict, coordinates=json.loads(gj)["coordinates"],
    )


# ---------- slope layer ----------

MAX_SPAN_DEG = 0.03  # about 3 km; bigger views ask the user to zoom in

NETWORK_SQL = """
WITH e AS (
    SELECT CASE
        WHEN kind = 'steps' THEN 'steps'
        WHEN curb = 'barrier' THEN 'barrier'
        WHEN abs(grade) > %(limit)s THEN 'over'
        WHEN abs(grade) >= 3 THEN 'moderate'
        ELSE 'easy' END AS cls,
        geom
    FROM edges
    WHERE geom && ST_MakeEnvelope(%(w)s, %(s)s, %(e)s, %(n)s, 4326) AND kind <> 'elevator'
), merged AS (
    -- join touching pieces of the same class, so the app draws far fewer lines
    SELECT cls, ST_LineMerge(ST_Collect(geom)) AS g FROM e GROUP BY cls
)
SELECT m.cls, ST_AsGeoJSON(d.geom, 6)
FROM merged m, LATERAL ST_Dump(m.g) d
"""


def network(conn, w, s, e, n, p: Profile) -> NetworkResponse:
    if (n - s) > MAX_SPAN_DEG or (e - w) > MAX_SPAN_DEG * 1.3:
        return NetworkResponse(too_large=True, lines=[])
    # "over" means too steep in at least one direction for this profile
    limit = min(p.max_uphill, p.max_downhill)
    with conn.cursor() as cur:
        cur.execute(NETWORK_SQL, {"w": w, "s": s, "e": e, "n": n, "limit": limit})
        rows = cur.fetchall()
    return NetworkResponse(too_large=False, lines=[
        NetworkLine(cls=cls, coordinates=json.loads(gj)["coordinates"]) for cls, gj in rows
    ])


# ---------- turn-by-turn ----------

TURN_SLIGHT = 20     # degrees of heading change before it counts as a turn at all
TURN_FULL = 55
TURN_SHARP = 150
CONNECTOR_M = 8      # tiny footway links between sidewalk and crosswalk; fold them in
SLIVER_M = 12        # steps shorter than this fold into their neighbors


def _bearing(a, b):
    """Compass heading from a to b, degrees clockwise from north."""
    lat = math.radians((a[1] + b[1]) / 2)
    dx = (b[0] - a[0]) * math.cos(lat)
    dy = b[1] - a[1]
    return (math.degrees(math.atan2(dx, dy)) + 360) % 360


def _cardinal(deg):
    names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
    return names[int((deg + 22.5) // 45) % 8]


def _turn(delta):
    """Heading change in degrees, -180..180, positive = right."""
    a = abs(delta)
    side = "right" if delta > 0 else "left"
    if a < TURN_SLIGHT:
        return "straight"
    if a < TURN_FULL:
        return f"slight_{side}"
    if a < TURN_SHARP:
        return side
    return f"sharp_{side}"


_ON = {"sidewalk": "on the sidewalk", "footway": "on the path", "pedestrian": "through the plaza",
       "steps": "up the steps", "elevator": "in the elevator"}
_TURN_WORDS = {"straight": "Continue", "slight_left": "Slight left", "slight_right": "Slight right",
               "left": "Turn left", "right": "Turn right",
               "sharp_left": "Sharp left", "sharp_right": "Sharp right"}
_CURB_WORDS = {"ramp": "Curb ramps", "flush": "Level with the street", "barrier": "No curb ramp",
               "unknown": "Curbs not surveyed"}
_CURB_RANK = {"barrier": 3, "unknown": 2, "flush": 1, "ramp": 0}


def _slope_words(g, p: Profile):
    a = abs(g)
    way = "uphill" if g > 0 else "downhill"
    if a < 2:
        return "Flat"
    if (g > 0 and a > p.max_uphill) or (g < 0 and a > p.max_downhill):
        return f"Steep {way}, {a:.1f}%"
    return f"{'Gentle' if a < 5 else 'Moderate'} {way}, {a:.1f}%"


def directions(rows, p: Profile, reaches: bool) -> list[Step]:
    """Group path edges into human steps: a new step when the kind of path changes
    or the heading turns, with tiny connectors folded into their neighbors."""
    groups = []
    for _, kind, curb, steep, poor, length, g, gj, _, surface in rows:
        coords = json.loads(gj)["coordinates"]
        if len(coords) < 2:
            continue
        start_b, end_b = _bearing(coords[0], coords[1]), _bearing(coords[-2], coords[-1])
        if groups and kind == "footway" and length < CONNECTOR_M:
            groups[-1]["length"] += length       # connector: part of whatever came before
            groups[-1]["end_b"] = end_b
            continue
        turn = "straight"
        if groups:
            delta = (start_b - groups[-1]["end_b"] + 540) % 360 - 180
            turn = _turn(delta)
            last = groups[-1]
            same_line = turn in ("straight",) or (kind == "crossing" and last["kind"] == "crossing")
            if kind == last["kind"] and same_line:
                last["length"] += length
                last["end_b"] = end_b
                if abs(g) > abs(last["grade"]):
                    last["grade"] = g
                if curb and _CURB_RANK.get(curb, 0) > _CURB_RANK.get(last["curb"] or "ramp", 0):
                    last["curb"] = curb
                last["ramp_issue"] |= bool(steep or poor)
                last["surface"] = last["surface"] or surface
                continue
        groups.append({"kind": kind, "turn": turn, "length": length, "grade": g, "curb": curb,
                       "ramp_issue": bool(steep or poor), "surface": surface,
                       "start_b": start_b, "end_b": end_b, "at": coords[0], "end": coords[-1]})
        groups[-1]["end"] = coords[-1]

    groups = _consolidate(groups)

    steps: list[Step] = []
    for i, gr in enumerate(groups):
        on = _ON.get(gr["kind"], "on the path")
        if i == 0:
            maneuver = "start"
            text = f"Head {_cardinal(gr['start_b'])} {on}" if gr["kind"] != "crossing" \
                else f"Head {_cardinal(gr['start_b'])} and cross the street"
        elif gr["kind"] == "crossing":
            maneuver = "cross"
            text = "Cross the street" if gr["turn"] == "straight" else f"{_TURN_WORDS[gr['turn']]} and cross the street"
            if gr.get("then"):
                text += ", then continue"
        else:
            maneuver = gr["turn"]
            text = f"{_TURN_WORDS[gr['turn']]} {on}"

        bits = [_slope_words(gr["grade"], p)]
        if gr["kind"] == "crossing":
            curb = _CURB_WORDS.get(gr["curb"] or "unknown")
            bits.append(curb + (", one is steep or worn" if gr["ramp_issue"] and gr["curb"] != "barrier" else ""))
        elif gr["surface"]:
            bits.append(gr["surface"].replace("_", " ").capitalize())

        steps.append(Step(maneuver=maneuver, instruction=text, detail=" · ".join(bits),
                          length_m=round(gr["length"], 1), grade=round(gr["grade"], 1),
                          slope=slope_class(gr["grade"], p), kind=gr["kind"], curb=gr["curb"],
                          coordinate=gr["at"]))

    if groups:
        steps.append(Step(
            maneuver="arrive",
            instruction="Arrive at your destination" if reaches else "The closest point within your limits",
            coordinate=groups[-1]["end"]))
    return steps


def _consolidate(groups):
    """Fewer, more meaningful steps:
    - slivers (short pieces) fold into the step before them, keeping the heading before the sliver,
      so a real turn still shows up on the next step
    - a crossing followed by sidewalk straight ahead becomes one step: "Cross the street, then continue"
    Turns are recomputed against whatever step they now follow."""
    out = []
    for i, g in enumerate(groups):
        is_last = i == len(groups) - 1
        if out and g["kind"] != "crossing" and g["length"] < SLIVER_M and not is_last:
            out[-1]["length"] += g["length"]       # fold; keep out[-1]["end_b"] so the next turn still counts
            continue

        if out:
            delta = (g["start_b"] - out[-1]["end_b"] + 540) % 360 - 180
            g["turn"] = _turn(delta)

        prev = out[-1] if out else None
        if prev and prev["kind"] == "crossing" and not prev.get("then") \
                and g["kind"] == "sidewalk" and g["turn"] == "straight":
            prev["then"] = True
            prev["length"] += g["length"]
            if abs(g["grade"]) > abs(prev["grade"]):
                prev["grade"] = g["grade"]
            prev["end_b"], prev["end"] = g["end_b"], g["end"]
            prev["surface"] = prev["surface"] or g["surface"]
            continue

        if prev and prev["kind"] == g["kind"] and g["turn"] == "straight" and g["kind"] != "crossing":
            prev["length"] += g["length"]          # two straight pieces of the same thing
            if abs(g["grade"]) > abs(prev["grade"]):
                prev["grade"] = g["grade"]
            prev["end_b"], prev["end"] = g["end_b"], g["end"]
            continue

        out.append(g)
    return out
