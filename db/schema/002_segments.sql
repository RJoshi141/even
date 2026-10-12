-- paths cut into runs of ~15 m+ with elevation and slope, rebuilt on every run

CREATE TABLE IF NOT EXISTS segments (
    id          serial PRIMARY KEY,
    osm_id      bigint NOT NULL,
    seq         int NOT NULL,          -- order along the OSM way
    kind        text NOT NULL,
    length_m    real NOT NULL,
    elev_start  real,
    elev_end    real,
    grade       real NOT NULL,         -- percent; positive = uphill in drawing direction
    geom        geometry(LineString, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS segments_geom_idx ON segments USING gist (geom);
CREATE INDEX IF NOT EXISTS segments_osm_idx ON segments (osm_id);
