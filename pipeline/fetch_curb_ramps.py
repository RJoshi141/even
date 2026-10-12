"""Download San Francisco's curb ramp inventory from DataSF.

Usage: uv run fetch_curb_ramps.py
Writes pipeline/data/curb_ramps.json (citywide, ~50k rows)
Dataset: https://data.sfgov.org/d/ch9w-7kih
"""
import json
from pathlib import Path

import requests

URL = "https://data.sfgov.org/resource/ch9w-7kih.json"
DATA_DIR = Path(__file__).parent / "data"
FIELDS = [
    "locid", "cnn", "locationdescription", "latitude", "longitude",
    "curbreturnloc", "positiononreturn",
    "crexist", "conditionscore", "sloperangeid", "liptoohigh",
]
PAGE = 20_000


def main():
    rows, offset = [], 0
    while True:
        resp = requests.get(URL, params={
            "$select": ",".join(FIELDS),
            "$order": ":id",       # stable order so paging doesn't skip or repeat
            "$limit": PAGE,
            "$offset": offset,
        }, timeout=120)
        resp.raise_for_status()
        page = resp.json()
        rows += page
        print(f"  {len(rows)} rows")
        if len(page) < PAGE:
            break
        offset += PAGE

    DATA_DIR.mkdir(exist_ok=True)
    (DATA_DIR / "curb_ramps.json").write_text(json.dumps(rows))
    print(f"Saved curb_ramps.json: {len(rows)} ramps")


if __name__ == "__main__":
    main()
