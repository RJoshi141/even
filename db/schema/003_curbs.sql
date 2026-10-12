-- DataSF curb ramp inventory, plus the curb status at both ends of every OSM crosswalk

CREATE TABLE IF NOT EXISTS curb_ramps (
    id               serial PRIMARY KEY,
    locid            text NOT NULL,      -- DataSF key, not unique in their data
    cnn              bigint,             -- city intersection id
    location         text,
    cr_exist         boolean NOT NULL,   -- is there a ramp at all
    condition_score  int,                -- 1-100 if it exists; 0 = needed but missing; -1/-2 = not needed or not possible
    slope_range      int,                -- 1 <6.67%, 2 6.67-8.33%, 3 8.33-10%, 4 >10%, 5 unknown
    lip_too_high     boolean,
    geom             geometry(Point, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS curb_ramps_geom_idx ON curb_ramps USING gist (geom);

CREATE TABLE IF NOT EXISTS crossing_ends (
    id               serial PRIMARY KEY,
    crossing_id      bigint NOT NULL,    -- osm_ways.osm_id of the crosswalk
    which            text NOT NULL,      -- start | end
    status           text NOT NULL,      -- ramp | flush | barrier | unknown
    source           text NOT NULL,      -- datasf | osm | none
    osm_kerb         text,
    ramp_id          int,
    ramp_dist_m      real,
    ramp_condition   int,
    ramp_slope_range int,
    geom             geometry(Point, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS crossing_ends_geom_idx ON crossing_ends USING gist (geom);
CREATE INDEX IF NOT EXISTS crossing_ends_crossing_idx ON crossing_ends (crossing_id);
