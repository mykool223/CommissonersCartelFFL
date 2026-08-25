#!/usr/bin/env python3
"""Ranks the league by the best lineup each team could actually field.

Not by record — in September nobody has one worth reading, and a team can win
on a bad week from a weak roster. This scores the strongest legal lineup each
roster could put out, on the FantasyPros expert consensus where we have a
number and ESPN's projection where we do not, using the same solver the coach
uses. Everybody is measured the same way.

Each week is stored so the next one can show movement, and the result is posted
to league news.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  shared secret for the push function
    POWER_WEEK                   override the week
    DRY_RUN                      print instead of publishing

Usage:
    DRY_RUN=1 ./Scripts/power_rankings.py
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
USER_AGENT = "curl/8.7.1"

BENCH_SLOTS = {20, 21}

# The lineup solver lives with the Sunday coach. Importing it rather than
# copying it is the only way two rankings cannot disagree about what a lineup
# is worth.
_spec = importlib.util.spec_from_file_location(
    "lineup_coach", pathlib.Path(__file__).with_name("lineup_coach.py"))
lineup_coach = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lineup_coach)


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
        method=method,
        headers=headers,
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def consensus_points(season: int, week: int) -> dict[int, float]:
    """Consensus projections keyed by ESPN player id."""
    rows = supabase(
        "GET",
        "fantasypros_projections?select=points_ppr,fantasypros_players!inner(espn_id)"
        f"&season=eq.{season}&week=eq.{week}&limit=2000",
    ) or []
    out: dict[int, float] = {}
    for row in rows:
        espn_id = (row.get("fantasypros_players") or {}).get("espn_id")
        if espn_id is not None and row.get("points_ppr") is not None:
            out[int(espn_id)] = float(row["points_ppr"])
    return out


def projection(player: dict, week: int) -> float:
    for row in player.get("stats") or []:
        if row.get("statSourceId") == 1 and row.get("scoringPeriodId") == week:
            return float(row.get("appliedTotal") or 0)
    return 0.0


def starting_slots(data: dict) -> list[int]:
    counts = ((data.get("settings") or {}).get("rosterSettings") or {}) \
        .get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in counts.items():
        if int(slot) in BENCH_SLOTS:
            continue
        slots.extend([int(slot)] * int(count))
    return slots


def score(team: dict, slots: list[int], week: int,
          consensus: dict[int, float]) -> float:
    players = []
    for entry in (team.get("roster") or {}).get("entries") or []:
        raw = (entry.get("playerPoolEntry") or {}).get("player") or {}
        if raw.get("id") is None:
            continue
        players.append({
            "id": raw["id"],
            "name": raw.get("fullName") or "A player",
            # Consensus where we have it, ESPN where we do not.
            "points": consensus.get(raw["id"], projection(raw, week)),
            "eligible": set(raw.get("eligibleSlots") or []),
        })
    total, _ = lineup_coach.best_lineup(players, slots)
    return round(total, 1)


def arrow(previous: int | None, rank: int) -> str:
    if previous is None:
        return ""
    if previous == rank:
        return " —"
    moved = previous - rank
    return f" {'▲' if moved > 0 else '▼'}{abs(moved)}"


def compose(week: int, rows: list[dict], previous: dict[int, int]) -> str:
    lines = [
        f"Strength of the best lineup each team could field in week {week}, "
        "on the expert consensus. Not record — records in September say very "
        "little, and a bad team can win a good week.",
        "",
        "This measures one Sunday, not how good a roster is. FantasyPros' own "
        "league analyzer scores whole rosters against draft rankings and will "
        "often say something different. Both are true; they are answering "
        "different questions.",
        "",
    ]
    for row in rows:
        lines.append(
            f"{row['rank']}. {row['team_name']} — {row['score']}"
            f"{arrow(previous.get(row['espn_team_id']), row['rank'])}")

    movers = [
        (previous[r["espn_team_id"]] - r["rank"], r)
        for r in rows if r["espn_team_id"] in previous
    ]
    climbed = max(movers, default=None, key=lambda m: m[0])
    if climbed and climbed[0] > 0:
        lines += ["", f"{climbed[1]['team_name']} climbed {climbed[0]} "
                      f"{'place' if climbed[0] == 1 else 'places'} this week."]

    lines += ["", "Our own arithmetic, built on consensus data from "
                  "FantasyPros. Not a FantasyPros ranking."]
    return "\n".join(lines)


def main() -> int:
    for name in ("ESPN_LEAGUE_ID", "ESPN_S2", "SUPABASE_URL",
                 "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 1

    dry_run = bool(os.environ.get("DRY_RUN"))
    season = current_season()
    league = os.environ["ESPN_LEAGUE_ID"]

    data = espn(f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}",
                "view=mRoster&view=mTeam&view=mSettings")
    week = int(os.environ.get("POWER_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    # Nothing has been played before week 1 is done, so a ranking then is
    # just a list of preseason projections dressed up as a verdict. The first
    # one goes out after week 1, when it can show movement and mean something.
    if week < 2 and not os.environ.get("POWER_FORCE"):
        log(f"Week {week}: too early to rank anybody. Nothing to publish.")
        return 0

    slots = starting_slots(data)
    consensus = consensus_points(season, week)
    log(f"Week {week}; {len(consensus)} consensus projections available")

    scored = sorted(
        ({"espn_team_id": t["id"],
          "team_name": (t.get("name") or f"Team {t['id']}").strip(),
          "score": score(t, slots, week, consensus)}
         for t in data.get("teams") or []),
        key=lambda r: -r["score"],
    )
    rows = [{**r, "season": season, "week": week, "rank": i + 1}
            for i, r in enumerate(scored)]

    # Projections for a week do not exist until close to it. Without them every
    # team scores zero and the ranking is alphabetical noise — which would be
    # published to the whole league as though it meant something.
    if sum(1 for r in rows if r["score"] > 0) < len(rows) / 2:
        log(f"Week {week}: projections are not out yet, so every team scores "
            "nothing. Refusing to publish a ranking of zeros.")
        return 0

    prior = supabase(
        "GET",
        f"power_rankings?select=espn_team_id,rank&season=eq.{season}&week=eq.{week - 1}",
    ) or []
    previous = {r["espn_team_id"]: r["rank"] for r in prior}

    title = f"Week {week} Lineup Strength"
    body = compose(week, rows, previous)

    if dry_run:
        log(f"DRY_RUN — would publish '{title}':")
        print(body)
        return 0

    supabase("POST", "power_rankings?on_conflict=season,week,espn_team_id", rows,
             prefer="resolution=merge-duplicates,return=minimal")

    existing = supabase(
        "GET",
        f"news_posts?select=id&season=eq.{season}"
        f"&title=eq.{urllib.parse.quote(title)}") or []
    if existing:
        log(f"'{title}' is already published; rankings updated.")
        return 0

    supabase("POST", "news_posts", [{
        "title": title, "body": body, "author_name": "The Commissioner",
        "season": season, "week": week,
    }], prefer="return=minimal")
    log(f"Published '{title}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
