# Even

Step-free directions for wheelchairs, walkers and strollers. Even routes around steep hills, missing curb ramps and broken elevators, and tells you why.

**Status:** early build. San Francisco first (Downtown, SoMa, Mission).

## How it works

- **pipeline/**: Python scripts that pull SF sidewalks, crossings, curb ramps and elevation, then compute the slope of every sidewalk segment in both directions.
- **db/**: Postgres with PostGIS and pgRouting. Holds the sidewalk graph.
- **api/**: FastAPI service. Turns a mobility profile (max uphill, max downhill, needs ramps, no stairs) into a route, plus the reasons behind it.
- **ios/**: SwiftUI app with MapKit. The first client.
- **web/**: Next.js app. Later, on the same API.
- **docs/**: case study notes and user research.

## Local setup

Requires Docker Desktop, Python 3.12+ and [uv](https://github.com/astral-sh/uv).

```bash
cp .env.example .env
docker compose up -d
docker compose exec db psql -U even -c "SELECT postgis_version(), pgr_version();"
```

## Data sources

- Sidewalks and crossings: © OpenStreetMap contributors, available under the [ODbL](https://www.openstreetmap.org/copyright)
- Curb ramps: [DataSF](https://datasf.org)
- Elevation: USGS 3D Elevation Program
- Elevator status: BART

## License

Code is MIT licensed. Map data keeps its original licenses listed above.
