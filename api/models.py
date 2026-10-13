from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class Point(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class Profile(BaseModel):
    max_uphill: float = Field(5, ge=0, le=30, description="Steepest uphill allowed, percent")
    max_downhill: float = Field(8, ge=0, le=30, description="Steepest downhill allowed, percent")
    avoid_steps: bool = True
    require_ramps: bool = True
    speed_mps: float = Field(1.0, gt=0, le=3, description="Travel speed on flat ground")


PresetName = Literal["manual_wheelchair", "power_wheelchair", "walker", "stroller"]

# starting points, to be tuned with real users
PRESETS: dict[str, Profile] = {
    "manual_wheelchair": Profile(max_uphill=5, max_downhill=8, speed_mps=1.0),
    "power_wheelchair": Profile(max_uphill=8, max_downhill=8, speed_mps=1.3),
    "walker": Profile(max_uphill=8, max_downhill=5, speed_mps=0.8),
    "stroller": Profile(max_uphill=12, max_downhill=8, require_ramps=False, speed_mps=1.2),
}


class RouteRequest(BaseModel):
    # what /docs prefills: Civic Center BART to Dolores Park, preset only
    model_config = ConfigDict(json_schema_extra={"examples": [{
        "origin": {"lat": 37.7796, "lon": -122.4138},
        "destination": {"lat": 37.7596, "lon": -122.4269},
        "preset": "manual_wheelchair",
    }]})

    origin: Point
    destination: Point
    preset: PresetName = "manual_wheelchair"
    profile: Profile | None = Field(None, description="Overrides the preset when given")


class Segment(BaseModel):
    kind: str                                     # sidewalk | crossing | footway | steps ...
    slope: Literal["easy", "moderate", "over"]    # relative to the profile
    grade: float                                  # steepest grade in the run, signed in travel direction
    length_m: float
    curb: str | None = None                       # crossings: ramp | flush | barrier | unknown
    ramp_issue: bool = False                      # crossing with a steep or worn ramp
    coordinates: list[list[float]]                # [lon, lat] pairs, in travel order


class RouteSummary(BaseModel):
    distance_m: float
    duration_s: float
    max_uphill: float
    max_downhill: float
    steps: int
    barrier_curbs: int
    unknown_curbs: int
    steep_ramps: int
    poor_ramps: int


class Route(BaseModel):
    kind: Literal["fits_profile", "shortest"]
    reaches_destination: bool
    gap_m: float | None = None                    # how far short it stops, when it can't reach
    fits_profile: bool
    breaks: list[str]                             # uphill | downhill | steps | curb
    summary: RouteSummary
    segments: list[Segment]


class RouteResponse(BaseModel):
    profile: Profile
    origin_snap_m: float
    destination_snap_m: float
    identical: bool                               # both routes are the same path
    routes: list[Route]


class InspectResponse(BaseModel):
    """What's at a tapped spot on the map."""
    found: bool                                   # false = no path within reach of the tap
    point: Point
    kind: str | None = None                       # sidewalk | crossing | footway | pedestrian | steps | elevator
    name: str | None = None
    surface: str | None = None
    grade: float | None = None                    # steepness, percent, unsigned
    length_m: float | None = None
    curb: str | None = None
    ramp_issue: bool = False
    access: Literal["both_ways", "one_way", "none"] | None = None
    verdict: str | None = None                    # plain words for this profile
    coordinates: list[list[float]] = []


class NetworkLine(BaseModel):
    cls: Literal["easy", "moderate", "over", "steps", "barrier"]
    coordinates: list[list[float]]


class NetworkResponse(BaseModel):
    too_large: bool                               # view too big, zoom in
    lines: list[NetworkLine]
