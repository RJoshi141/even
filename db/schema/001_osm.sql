-- raw OSM pedestrian data, reloaded from scratch on every pipeline run

CREATE TABLE IF NOT EXISTS osm_ways (
    osm_id  bigint PRIMARY KEY,
    kind    text NOT NULL,   -- sidewalk | crossing | footway | pedestrian | steps | elevator
    tags    jsonb NOT NULL,
    geom    geometry(LineString, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS osm_ways_geom_idx ON osm_ways USING gist (geom);
CREATE INDEX IF NOT EXISTS osm_ways_kind_idx ON osm_ways (kind);

CREATE TABLE IF NOT EXISTS osm_points (
    osm_id  bigint PRIMARY KEY,
    kind    text NOT NULL,   -- elevator | kerb | crossing
    kerb    text,            -- lowered | flush | raised | rolled | no, when tagged
    tags    jsonb NOT NULL,
    geom    geometry(Point, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS osm_points_geom_idx ON osm_points USING gist (geom);
