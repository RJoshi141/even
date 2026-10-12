# API

FastAPI service that routes on the graph built by `pipeline/`.

```bash
cd api
uv sync
uv run uvicorn main:app --reload     # http://localhost:8000/docs to try it
uv run pytest                        # needs the db up and the pipeline run
```

## Endpoints

- `GET /health`: db check
- `GET /profiles`: mobility presets (manual_wheelchair, power_wheelchair, walker, stroller)
- `POST /route`: origin, destination, preset or custom profile. Returns two routes, `fits_profile` and `shortest`, each with a summary, what rules it breaks, and segments colored by slope for the map. When nothing fits the profile all the way, `fits_profile` stops at the closest reachable point and reports `gap_m`.

```bash
curl -s localhost:8000/route -H 'content-type: application/json' -d '{
  "origin": {"lat": 37.7796, "lon": -122.4138},
  "destination": {"lat": 37.7596, "lon": -122.4269},
  "preset": "manual_wheelchair"
}'
```
