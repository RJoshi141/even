"""Download pedestrian ways and curb data for an area from OpenStreetMap.

Usage: uv run fetch_osm.py [area]   (default: sf-core)
Writes pipeline/data/osm_<area>.json
"""
import json
import sys
import time
from collections import Counter
from pathlib import Path

import requests

from areas import AREAS

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
DATA_DIR = Path(__file__).parent / "data"
# Overpass asks clients to identify themselves
HEADERS = {"User-Agent": "even-app (https://github.com/RJoshi141/even)"}

QUERY = """
[out:json][timeout:300];
(
  way["highway"="footway"]({bbox});
  way["highway"="pedestrian"]({bbox});
  way["highway"="steps"]({bbox});
  way["highway"="elevator"]({bbox});
  node["kerb"]({bbox});
  node["highway"="crossing"]({bbox});
  node["highway"="elevator"]({bbox});
);
out geom;
"""


def fetch(bbox, retries=4):
    query = QUERY.format(bbox=",".join(str(v) for v in bbox))
    for attempt in range(retries):
        resp = requests.post(OVERPASS_URL, data={"data": query}, headers=HEADERS, timeout=360)
        if resp.status_code in (429, 504):  # rate limited or server busy, back off
            wait = 30 * (attempt + 1)
            print(f"Overpass busy ({resp.status_code}), retrying in {wait}s")
            time.sleep(wait)
            continue
        resp.raise_for_status()
        return resp.json()
    sys.exit("Overpass kept failing, try again in a few minutes")


def main():
    area = sys.argv[1] if len(sys.argv) > 1 else "sf-core"
    if area not in AREAS:
        sys.exit(f"Unknown area '{area}'. Options: {', '.join(AREAS)}")

    print(f"Fetching {area}...")
    data = fetch(AREAS[area])

    DATA_DIR.mkdir(exist_ok=True)
    out = DATA_DIR / f"osm_{area}.json"
    out.write_text(json.dumps(data))

    counts = Counter(e["type"] for e in data["elements"])
    print(f"Saved {out.name}: {counts['way']} ways, {counts['node']} nodes")


if __name__ == "__main__":
    main()
