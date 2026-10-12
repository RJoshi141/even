# Pipeline

Turns open data into the sidewalk graph Even routes on.

```bash
cd pipeline
uv sync                 # first time only
uv run fetch_osm.py     # download OSM sidewalks, crossings, curbs, elevators
uv run load_osm.py      # load into PostGIS, print coverage, write a GeoJSON preview
uv run elevation.py     # sample USGS elevation, compute slope per segment
uv run fetch_curb_ramps.py  # download DataSF curb ramp inventory
uv run match_curbs.py   # curb status at both ends of every crosswalk
```

Raw downloads go in `pipeline/data/`, which is gitignored.

## Steps

1. **OSM ingest** (done): sidewalks, crossings, steps, elevators, curb nodes.
2. **Curb ramps** (done): DataSF curb ramp inventory matched to both ends of every OSM crosswalk. DataSF wins when it has a definite answer, OSM kerb tags fill the gaps.
3. **Elevation** (done): USGS 10 m DEM sampled at segment ends, paths cut into 15 m+ runs, signed grade per run.
4. **Graph** (next): split ways at intersections, build the pgRouting edge table.
