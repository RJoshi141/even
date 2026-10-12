-- routable sidewalk graph, rebuilt by build_graph.py on every run

DROP TABLE IF EXISTS edges;
DROP TABLE IF EXISTS nodes;

CREATE TABLE nodes (
    id    bigint PRIMARY KEY,
    elev  real,
    geom  geometry(Point, 4326) NOT NULL
);
CREATE INDEX nodes_geom_idx ON nodes USING gist (geom);

CREATE TABLE edges (
    id             serial PRIMARY KEY,
    source         bigint NOT NULL REFERENCES nodes (id),
    target         bigint NOT NULL REFERENCES nodes (id),
    osm_id         bigint NOT NULL,
    kind           text NOT NULL,     -- sidewalk | crossing | footway | pedestrian | steps | elevator
    length_m       real NOT NULL,
    grade          real NOT NULL,     -- percent, source -> target; reverse direction is -grade
    curb           text,              -- crossings only: ramp | flush | barrier | unknown (worst of both ends)
    steep_ramp     boolean NOT NULL DEFAULT false,  -- a ramp on this crossing is steeper than 8.33%
    poor_ramp      boolean NOT NULL DEFAULT false,  -- a ramp on this crossing scores under 60/100
    geom           geometry(LineString, 4326) NOT NULL
);
CREATE INDEX edges_geom_idx ON edges USING gist (geom);
CREATE INDEX edges_source_idx ON edges (source);
CREATE INDEX edges_target_idx ON edges (target);
