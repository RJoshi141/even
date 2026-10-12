# Pipeline

Turns open data into the sidewalk graph Even routes on.

```bash
cd pipeline
uv sync                 # first time only
uv run fetch_osm.py     # download OSM sidewalks, crossings, curbs, elevators
uv run load_osm.py      # load into PostGIS, print coverage, write a GeoJSON preview
```

Raw downloads go in `pipeline/data/`, which is gitignored.

## Steps

1. **OSM ingest** (done): sidewalks, crossings, steps, elevators, curb nodes.
2. **Curb ramps**: DataSF curb ramp inventory, matched to crossing ends.
3. **Elevation**: USGS elevation sampled along every segment, slope computed in both directions.
4. **Graph**: split ways at intersections, build the pgRouting edge table.
