#!/usr/bin/env python3
"""Caches FantasyPros consensus data into Postgres for the coach to read.

FantasyPros allows one call per second and 100 calls per day, and asks that
clients cache rather than poll. This runs once a night, spends about a dozen
calls, and everything else reads from the tables it fills.

Their licence does not grant use of historical player statistics or player
image URLs, so neither is requested, neither is stored, and rows for weeks that
have passed are deleted on each run.

Environment:
    FANTASYPROS_API_KEY          personal API key (HOF subscription)
    SUPABASE_URL                 https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY    service role key
    FP_SEASON, FP_WEEK           override the season and week
    DRY_RUN                      set to any value to print instead of writing

Usage:
    DRY_RUN=1 ./Scripts/sync_fantasypros.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

FP_HOST = "https://api.fantasypros.com/public/v2/json"

# Their published ceiling is 100 calls a day. Stopping well short leaves room
# for a re-run after a failure without locking us out until midnight.
DAILY_BUDGET = 40

# One call per second, so wait slightly longer than that.
CALL_SPACING = 1.2

# The league is full PPR, which decides both the ranking set and the projected
# points column worth storing.
SCORING = "PPR"

# Kickers and defences are ranked separately; ALL does not include them.
POSITIONS = ["QB", "RB", "WR", "TE", "K", "DST"]


def log(message: str) -> None:
    print(message, file=sys.stderr)


def current_season(today: dt.date | None = None) -> int:
    """Matches Season.current() on iOS and Config.currentSeason() on Android."""
    today = today or dt.date.today()
    return today.year if today.month >= 6 else today.year - 1


def current_week(today: dt.date | None = None) -> int:
    """Week 1 begins on the first Tuesday of September; clamped to 1-18."""
    today = today or dt.date.today()
    september = dt.date(current_season(today), 9, 1)
    # weekday() is 0 for Monday, so 1 is Tuesday.
    kickoff = september + dt.timedelta(days=(1 - september.weekday()) % 7)
    if today < kickoff:
        return 1
    return min(18, (today - kickoff).days // 7 + 1)


class Budget:
    """Counts calls so a loop cannot quietly spend the day's allowance."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.spent = 0
        self._last = 0.0

    def take(self) -> None:
        if self.spent >= self.limit:
            raise RuntimeError(
                f"FantasyPros call budget of {self.limit} exhausted; "
                "stopping rather than risking the daily cap")
        wait = CALL_SPACING - (time.monotonic() - self._last)
        if wait > 0:
            time.sleep(wait)
        self._last = time.monotonic()
        self.spent += 1


def fantasypros(budget: Budget, path: str, **params: object) -> dict:
    budget.take()
    query = urllib.parse.urlencode(
        {k: v for k, v in params.items() if v is not None})
    request = urllib.request.Request(
        f"{FP_HOST}{path}?{query}",
        headers={
            "x-api-key": os.environ["FANTASYPROS_API_KEY"],
            "Accept": "application/json",
            "User-Agent": "commissioners-cartel/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:300]
        raise RuntimeError(f"FantasyPros {path} returned {error.code}: {body}") from None


def supabase(method: str, path: str, body: object = None,
             prefer: str | None = None) -> object:
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL']}/rest/v1/{path}",
        method=method,
        headers=headers,
        data=json.dumps(body).encode() if body is not None else None,
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        body_text = error.read().decode("utf-8", "replace")[:400]
        raise RuntimeError(f"Supabase {method} {path} → {error.code}: {body_text}") from None


def to_int(value: object) -> int | None:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def to_float(value: object) -> float | None:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def fetch_players(budget: Budget) -> list[dict]:
    """Their players, carrying the ESPN id that makes the join reliable."""
    data = fantasypros(budget, "/nfl/players", external_ids="espn")
    rows = []
    for player in data.get("players") or []:
        fp_id = to_int(player.get("player_id"))
        if fp_id is None:
            continue
        rows.append({
            "fp_id": fp_id,
            "espn_id": to_int((player.get("external_ids") or {}).get("espn")
                              if isinstance(player.get("external_ids"), dict)
                              else player.get("espn_id")),
            "name": player.get("player_name") or "",
            "team": player.get("team_id"),
            "position": player.get("position_id"),
        })
    return [r for r in rows if r["name"]]


def fetch_rankings(budget: Budget, season: int, week: int,
                   kind: str) -> list[dict]:
    """Consensus rankings, one call per position."""
    rows = []
    for position in POSITIONS:
        data = fantasypros(
            budget,
            f"/nfl/{season}/consensus-rankings",
            position=position,
            scoring=SCORING,
            # Their weekly set is keyed on the week; rest-of-season is its own
            # ranking type and ignores it.
            type="ROS" if kind == "ros" else None,
            week=0 if kind == "ros" else week,
        )
        for player in data.get("players") or []:
            fp_id = to_int(player.get("player_id"))
            if fp_id is None:
                continue
            rows.append({
                "season": season,
                "week": week,
                "kind": kind,
                "fp_id": fp_id,
                "rank_ecr": to_int(player.get("rank_ecr")),
                "pos_rank": player.get("pos_rank"),
                "tier": to_int(player.get("tier")),
                "rank_min": to_int(player.get("rank_min")),
                "rank_max": to_int(player.get("rank_max")),
                "rank_std": to_float(player.get("rank_std")),
                "ecr_delta": to_float(player.get("player_ecr_delta")),
            })
    return rows


def fetch_projections(budget: Budget, season: int, week: int) -> list[dict]:
    """Projected points for the week, in the league's scoring."""
    rows = []
    for position in POSITIONS:
        data = fantasypros(
            budget, f"/nfl/{season}/projections", position=position, week=week)
        for player in data.get("players") or []:
            fp_id = to_int(player.get("fpid"))
            stats = player.get("stats") or []
            if fp_id is None or not stats:
                continue
            entry = stats[0] if isinstance(stats, list) else stats
            points = to_float(entry.get("points_ppr"))
            if points is None:
                points = to_float(entry.get("points"))
            rows.append({
                "season": season,
                "week": week,
                "fp_id": fp_id,
                "points_ppr": points,
            })
    return rows


def fetch_injuries(budget: Budget, season: int, week: int) -> list[dict]:
    """Injuries, including practice-report players without a status yet."""
    data = fantasypros(budget, "/nfl/injuries", year=season, week=week,
                       include_probabilities="true")
    rows = []
    for injury in data.get("injuries") or []:
        fp_id = to_int(injury.get("player_id"))
        if fp_id is None:
            continue
        rows.append({
            "season": season,
            "week": week,
            "fp_id": fp_id,
            "status": injury.get("status"),
            "probability": to_float(injury.get("probability_of_playing")),
            "injury_type": injury.get("injury_type"),
            "comment": injury.get("comment"),
        })
    return rows


def upsert(table: str, rows: list[dict], conflict: str) -> None:
    if not rows:
        log(f"  {table}: nothing to write")
        return
    # PostgREST rejects a payload with duplicate conflict keys in one request.
    seen, unique = set(), []
    for row in rows:
        key = tuple(row[c] for c in conflict.split(","))
        if key in seen:
            continue
        seen.add(key)
        unique.append(row)
    for start in range(0, len(unique), 500):
        supabase(
            "POST",
            f"{table}?on_conflict={conflict}",
            unique[start:start + 500],
            prefer="resolution=merge-duplicates,return=minimal",
        )
    log(f"  {table}: {len(unique)} rows")


def main() -> int:
    for name in ("FANTASYPROS_API_KEY", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 2

    season = int(os.environ.get("FP_SEASON") or current_season())
    week = int(os.environ.get("FP_WEEK") or current_week())
    dry_run = bool(os.environ.get("DRY_RUN"))
    budget = Budget(DAILY_BUDGET)

    log(f"FantasyPros sync: season {season}, week {week}"
        f"{' (dry run)' if dry_run else ''}")

    players = fetch_players(budget)
    matched = sum(1 for p in players if p["espn_id"])
    log(f"  players: {len(players)}, {matched} carrying an ESPN id")

    weekly = fetch_rankings(budget, season, week, "weekly")
    ros = fetch_rankings(budget, season, week, "ros")
    projections = fetch_projections(budget, season, week)
    injuries = fetch_injuries(budget, season, week)
    log(f"  spent {budget.spent} of {budget.limit} calls")

    if dry_run:
        log(f"  would write {len(players)} players, {len(weekly)} weekly and "
            f"{len(ros)} rest-of-season ranks, {len(projections)} projections, "
            f"{len(injuries)} injuries")
        return 0

    upsert("fantasypros_players", players, "fp_id")

    # Only players we know about can be referenced, so drop the rest.
    known = {p["fp_id"] for p in players}
    keep = lambda rows: [r for r in rows if r["fp_id"] in known]

    upsert("fantasypros_rankings", keep(weekly), "season,week,kind,fp_id")
    upsert("fantasypros_rankings", keep(ros), "season,week,kind,fp_id")
    upsert("fantasypros_projections", keep(projections), "season,week,fp_id")
    upsert("fantasypros_injuries", keep(injuries), "season,week,fp_id")

    # Weeks that have been played are of no use to a coach and their licence
    # does not cover historical data, so they do not linger.
    for table in ("fantasypros_rankings", "fantasypros_projections",
                  "fantasypros_injuries"):
        supabase("DELETE", f"{table}?week=lt.{week}", prefer="return=minimal")

    supabase(
        "POST",
        "fantasypros_usage?on_conflict=day",
        [{"day": dt.date.today().isoformat(), "calls": budget.spent,
          "updated_at": dt.datetime.now(dt.timezone.utc).isoformat()}],
        prefer="resolution=merge-duplicates,return=minimal",
    )
    log("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
