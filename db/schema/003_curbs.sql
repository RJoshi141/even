-- DataSF curb ramp inventory, plus the curb status at both ends of every OSM crosswalk.
-- Both tables are rebuilt by match_curbs.py on every run.

DROP TABLE IF EXISTS crossing_ends;
DROP TABLE IF EXISTS curb_ramps;

-- note: DataSF puts every ramp at its intersection's center point; the corner is a label
CREATE TABLE curb_ramps (
    id               serial PRIMARY KEY,
    locid            text NOT NULL,      -- DataSF key, not unique in their data
    cnn              bigint,             -- city intersection id
    location         text,
    corner           text,               -- N NE E SE S SW W NW
    position         text,               -- Left | Right | Center | Mid-Block | ...
    cr_exist         boolean NOT NULL,   -- is there a ramp at all
    condition_score  int,                -- 1-100 if it exists; 0 = needed but missing; -1/-2 = not needed or not possible
    slope_range      int,                -- 1 <6.67%, 2 6.67-8.33%, 3 8.33-10%, 4 >10%, 5 unknown
    lip_too_high     boolean,
    geom             geometry(Point, 4326) NOT NULL
);
CREATE INDEX curb_ramps_geom_idx ON curb_ramps USING gist (geom);
CREATE INDEX curb_ramps_cnn_idx ON curb_ramps (cnn);

CREATE TABLE crossing_ends (
    id               serial PRIMARY KEY,
    crossing_id      bigint NOT NULL,    -- osm_ways.osm_id of the crosswalk
    which            text NOT NULL,      -- start | end
    status           text NOT NULL,      -- ramp | flush | barrier | unknown
    source           text NOT NULL,      -- datasf | osm | none
    osm_kerb         text,
    cnn              bigint,             -- matched intersection
    corner           text,               -- matched corner
    datasf_corner    text,               -- ramp | missing | mixed | none: what the city says about that corner
    corner_angle     real,               -- degrees between the end's bearing and the corner label
    ramp_condition   int,                -- worst condition score among the corner's ramps
    ramp_slope_range int,                -- steepest slope range among the corner's ramps
    geom             geometry(Point, 4326) NOT NULL
);
CREATE INDEX crossing_ends_geom_idx ON crossing_ends USING gist (geom);
CREATE INDEX crossing_ends_crossing_idx ON crossing_ends (crossing_id);
