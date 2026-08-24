#!/usr/bin/env python3
"""Awards the week's trophies once its games are final.

Currently one: the highest score of the week. More can be added to AWARDS
without touching anything else.

ESPN has no history for this league, so the trophy case starts empty and fills
up from here. Awards are unique per season, week and kind, so re-running the
job cannot hand out the same trophy twice.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    TROPHY_WEEK                  override the week (defaults to the last completed one)
    DRY_RUN                      print instead of writing

Usage:
    DRY_RUN=1 ./Scripts/award_trophies.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
USER_AGENT = "curl/8.7.1"


def log(message: str) -> None:
    print(message, file=sys.stderr)


def current_season(today: dt.date | None = None) -> int:
    today = today or dt.date.today()
    return today.year if today.month >= 6 else today.year - 1


def espn(path: str, query: str) -> dict:
    request = urllib.request.Request(
        f"{ESPN_HOST}{path}?{query}",
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Cookie": f"espn_s2={os.environ['ESPN_S2']}; SWID={os.environ['ESPN_SWID']}",
        },
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.load(response)


def performances(data: dict, week: int) -> list[tuple[int, float]]:
    """(teamId, points) for every side of every completed fixture that week."""
    out: list[tuple[int, float]] = []
    for game in data.get("schedule") or []:
        if game.get("matchupPeriodId") != week:
            continue
        winner = (game.get("winner") or "").upper()
        # Only finished fixtures. Ranking teams on a game still being played
        # produces a trophy that has to be taken back.
        if winner in ("", "UNDECIDED"):
            continue
        for side in ("home", "away"):
            entry = game.get(side) or {}
            if entry.get("teamId") is not None:
                out.append((entry["teamId"], float(entry.get("totalPoints") or 0.0)))
    return out


def main() -> int:
    dry_run = bool(os.environ.get("DRY_RUN"))
    league = os.environ.get("ESPN_LEAGUE_ID", "")
    season = current_season()
    if not league or not os.environ.get("ESPN_S2"):
        log("ESPN_LEAGUE_ID, ESPN_S2 and ESPN_SWID are required.")
        return 1

    path = f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}"
    data = espn(path, "view=mMatchupScore&view=mTeam&view=mSettings")

    current = (data.get("status") or {}).get("currentMatchupPeriod") or 1
    # Default to the week just gone: the current one is rarely finished.
    week = int(os.environ.get("TROPHY_WEEK") or max(current - 1, 0))
    if week < 1:
        log("No completed week yet.")
        return 0

    scores = performances(data, week)
    if not scores:
        log(f"Week {week} has no completed fixtures.")
        return 0

    names = {t["id"]: (t.get("name") or f"Team {t['id']}").strip() for t in data.get("teams") or []}
    best = max(scores, key=lambda pair: pair[1])

    rows = [{
        "season": season,
        "week": week,
        "espn_team_id": best[0],
        "kind": "top_score",
        "title": f"Top score, week {week}",
        "detail": f"{names.get(best[0], 'A team')} — {best[1]:.1f} points",
    }]

    if dry_run:
        log(f"DRY_RUN — would award {len(rows)}:")
        for row in rows:
            log(f"  {row['title']}: {row['detail']}")
        return 0

    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    request = urllib.request.Request(
        f"{base}/rest/v1/trophies?on_conflict=season,week,kind",
        data=json.dumps(rows).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal,resolution=ignore-duplicates",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()
    log(f"Awarded {len(rows)} trophy for week {week}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
