#!/usr/bin/env python3
"""Keeps the pick'em fixtures and results in step with the NFL.

Two jobs in one, because they read the same feed: before the games it stores
the week's fixtures so people have something to pick, and afterwards it marks
the winners so the standings settle themselves.

Scores are never stored — public.pickem_standings computes them from the picks
and the results. A stored total is a total that can disagree with the picks it
came from.

Environment:
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PICKEM_WEEK                  a single week (defaults to the current one)
    PICKEM_WEEKS                 e.g. "1-4", to backfill a range
    PICKEM_SEASON                defaults to the current season
    DRY_RUN                      print instead of writing

Usage:
    DRY_RUN=1 ./Scripts/sync_pickem.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

SCOREBOARD = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"

# ESPN's edge rejects browser-like agents and allows known HTTP clients. The
# same rule the league scoreboard hit.
USER_AGENT = "curl/8.7.1"


def log(message: str) -> None:
    print(message, file=sys.stderr)


def current_season(today: dt.date | None = None) -> int:
    today = today or dt.date.today()
    return today.year if today.month >= 6 else today.year - 1


def current_week(today: dt.date | None = None) -> int:
    """Week 1 begins on the first Tuesday of September; clamped to 1-18."""
    today = today or dt.date.today()
    september = dt.date(current_season(today), 9, 1)
    kickoff = september + dt.timedelta(days=(1 - september.weekday()) % 7)
    if today < kickoff:
        return 1
    return min(18, (today - kickoff).days // 7 + 1)


def weeks_wanted() -> list[int]:
    single = os.environ.get("PICKEM_WEEK")
    if single:
        return [int(single)]
    span = os.environ.get("PICKEM_WEEKS")
    if span:
        first, _, last = span.partition("-")
        return list(range(int(first), int(last or first) + 1))
    return [current_week()]


def scoreboard(season: int, week: int) -> dict:
    query = urllib.parse.urlencode({"dates": season, "seasontype": 2, "week": week})
    request = urllib.request.Request(
        f"{SCOREBOARD}?{query}",
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


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
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/{path}",
        method=method, headers=headers,
        data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def fixtures(season: int, week: int) -> list[dict]:
    rows = []
    for event in scoreboard(season, week).get("events") or []:
        competition = (event.get("competitions") or [{}])[0]
        sides = {c.get("homeAway"): c for c in competition.get("competitors") or []}
        home, away = sides.get("home"), sides.get("away")
        if not (home and away and event.get("id") and event.get("date")):
            continue

        status = ((competition.get("status") or {}).get("type") or {})
        final = bool(status.get("completed"))

        # ESPN reports the winner on the competitor. A tie leaves both false,
        # which is right: a drawn game is worth nothing to anybody.
        winner = None
        if final:
            if home.get("winner"):
                winner = home["team"]["abbreviation"]
            elif away.get("winner"):
                winner = away["team"]["abbreviation"]

        rows.append({
            "season": season,
            "week": week,
            "event_id": str(event["id"]),
            "home_abbr": home["team"]["abbreviation"],
            "home_name": home["team"]["displayName"],
            "away_abbr": away["team"]["abbreviation"],
            "away_name": away["team"]["displayName"],
            "kickoff_at": event["date"],
            "winner_abbr": winner,
            "final": final,
            "updated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        })
    return rows


def main() -> int:
    for name in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 2

    dry_run = bool(os.environ.get("DRY_RUN"))
    season = int(os.environ.get("PICKEM_SEASON") or current_season())

    total, settled = 0, 0
    for week in weeks_wanted():
        rows = fixtures(season, week)
        if not rows:
            log(f"Week {week}: no fixtures returned.")
            continue
        done = sum(1 for r in rows if r["final"])
        total += len(rows)
        settled += done
        log(f"Week {week}: {len(rows)} game(s), {done} final")
        if dry_run:
            for row in rows[:3]:
                result = f" → {row['winner_abbr']}" if row["winner_abbr"] else ""
                log(f"    {row['away_abbr']} at {row['home_abbr']}, "
                    f"{row['kickoff_at'][:16]}{result}")
            continue
        supabase("POST", "pickem_games?on_conflict=season,week,event_id", rows,
                 prefer="resolution=merge-duplicates,return=minimal")

    log(f"{'Would store' if dry_run else 'Stored'} {total} game(s), "
        f"{settled} already decided.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
