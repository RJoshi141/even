<p align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Even app icon">
</p>

<h1 align="center">Even</h1>

<p align="center">
  <b>Directions that know the hills.</b><br>
  Step-free routes for wheelchairs, walkers and strollers in San Francisco.
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="Even on iPhone: tapping a sidewalk, a route to Mission Dolores Park, and turn-by-turn directions">
</p>

Regular map apps send everyone the same way. In San Francisco that can mean a 15% hill, a corner with no curb ramp, or a staircase in the middle of the route. Even plans around how you get around: how steep you can go up, how steep you can go down, and whether you need a ramp at every curb. It then shows you why it picked the route it did.

**Status:** early build. iOS first, covering Downtown, SoMa and the Mission.

## The app

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/images/route.png" alt="Route on the map"></td>
    <td align="center" width="33%"><img src="docs/images/trip-info.png" alt="Trip info pop-up"></td>
    <td align="center" width="33%"><img src="docs/images/directions.png" alt="Directions pop-up"></td>
  </tr>
  <tr>
    <td><b>One route, colored by slope.</b> Green is easy, amber is moderate. Square markers flag curb ramps that are steep, worn or unsurveyed.</td>
    <td><b>Trip info.</b> The slope profile against your limits, the steepest climb and descent, and what to watch for on the way.</td>
    <td><b>Directions.</b> Each step lists its length, slope and curb status, so nothing is a surprise at the corner.</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/inspect.png" alt="Inspecting a sidewalk"></td>
    <td align="center"><img src="docs/images/profiles.png" alt="Mobility profile picker"></td>
    <td align="center"><img src="docs/images/slope-layer.png" alt="Slope layer over the neighborhood"></td>
  </tr>
  <tr>
    <td><b>Tap any sidewalk.</b> See its incline, length and surface, and whether it works both ways for you. Start or end a route there.</td>
    <td><b>How you get around.</b> Manual wheelchair, power wheelchair, walker or cane, or stroller. Each one sets its own limits.</td>
    <td><b>Slope layer.</b> Every sidewalk in the area, colored by grade, so you can read the neighborhood at a glance.</td>
  </tr>
</table>

<p align="center">
  <img src="docs/images/legend.png" width="300" alt="Map legend">
</p>

## How it works

1. **Sidewalks.** OpenStreetMap sidewalks, crossings, steps and elevators are loaded into PostGIS.
2. **Slope.** Every path is cut into runs of 15 m or more, and each run gets a signed grade from the USGS 1/3 arc-second elevation model, so uphill and downhill are scored separately.
3. **Curbs.** DataSF's curb ramp inventory is matched to both ends of every crosswalk by corner and bearing. That took curb coverage from 27% to 77%.
4. **Routing.** pgRouting runs Dijkstra with a cost built from your profile. Anything over your limits is impassable, and unknown or worn ramps cost extra. If nothing fits the whole way, Even gets you as close as it can and tells you how far is left.
5. **Directions.** Raw graph edges are merged into readable steps, like "Cross the street, then continue", with the slope and curb details attached.

## Repo

| Folder | What's inside |
| --- | --- |
| `pipeline/` | Python scripts that build the sidewalk graph from open data. See [pipeline/README.md](pipeline/README.md). |
| `db/` | Postgres 16 with PostGIS and pgRouting, plus the schema. |
| `api/` | FastAPI service: routes, sidewalk inspection, the slope layer. See [api/README.md](api/README.md). |
| `ios/` | SwiftUI app with MapKit and Swift Charts. |
| `web/` | Next.js client, later, on the same API. |
| `docs/` | Case study notes, research and README images. |

## Run it locally

Requires Docker, Python 3.12+, [uv](https://github.com/astral-sh/uv) and Xcode 26.

```bash
# database
cp .env.example .env
docker compose up -d db

# build the graph (first time only)
cd pipeline && uv sync
uv run fetch_osm.py && uv run load_osm.py && uv run elevation.py
uv run fetch_curb_ramps.py && uv run match_curbs.py && uv run build_graph.py

# api, at http://localhost:8000/docs
cd ../api && uv sync
DATABASE_URL=postgresql://even:even@localhost:5432/even uv run uvicorn main:app --reload
```

Then open `ios/Even/Even.xcodeproj` and press ⌘R. The simulator talks to the API on localhost.

## Data sources

- Sidewalks and crossings: © OpenStreetMap contributors, under the [ODbL](https://www.openstreetmap.org/copyright)
- Curb ramps: [DataSF](https://datasf.org) curb ramp inventory
- Elevation: USGS 3D Elevation Program
- Elevator status: BART (planned)

## License

Code is MIT licensed. Map data keeps the original licenses listed above.
