#!/usr/bin/env python3
"""Ranks the league on what has actually been played.

By points scored across the completed weeks, which is the one measure nobody
can argue with and nobody can be unlucky in. Record is shown but does not sort:
a team can lose a week having scored the second most points in the league, and
calling that the eleventh best team is how a ranking loses everybody's trust.

It used to rank the strongest lineup each roster could field in the *coming*
week, on expert projections. That is a defensible thing to measure and it read
as broken: the team that had just scored the most points in the league came out
eleventh, because the ranking was answering a question nobody had asked.

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
import json
import os
import sys
import urllib.error
import urllib.parse
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


def arrow(previous: int | None, rank: int) -> str:
    if previous is None:
        return ""
    if previous == rank:
        return " —"
    moved = previous - rank
    return f" {'▲' if moved > 0 else '▼'}{abs(moved)}"


def overall(team: dict) -> dict:
    """ESPN's cumulative record for the completed weeks."""
    return (team.get("record") or {}).get("overall") or {}


def record_of(team: dict) -> str:
    """"2-1", or "2-1-1" when a tie is involved."""
    o = overall(team)
    wins, losses = int(o.get("wins") or 0), int(o.get("losses") or 0)
    ties = int(o.get("ties") or 0)
    return f"{wins}-{losses}-{ties}" if ties else f"{wins}-{losses}"


def compose(week: int, rows: list[dict], previous: dict[int, int]) -> str:
    through = week - 1
    lines = [
        f"Points scored through week {through}. Ranked on what has been put on "
        "the board, not on record — a team can lose a week having scored the "
        "second most points in the league, and the schedule is nobody's doing.",
        "",
    ]
    for row in rows:
        lines.append(
            f"{row['rank']}. {row['team_name']} — {row['score']} ({row['record']})"
            f"{arrow(previous.get(row['espn_team_id']), row['rank'])}")

    movers = [
        (previous[r["espn_team_id"]] - r["rank"], r)
        for r in rows if r["espn_team_id"] in previous
    ]
    climbed = max(movers, default=None, key=lambda m: m[0])
    if climbed and climbed[0] > 0:
        lines += ["", f"{climbed[1]['team_name']} climbed {climbed[0]} "
                      f"{'place' if climbed[0] == 1 else 'places'} this week."]

    lines += ["", "Total points scored, straight from the scoreboard."]
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
                # Records only. The rosters and the league settings were for
                # solving lineups, which this no longer does.
                "view=mTeam")
    week = int(os.environ.get("POWER_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    # Nothing has been played before week 1 is done, and a ranking of nothing
    # is a list of projections dressed up as a verdict. The first one goes out
    # once week 1 is complete, when it has results to stand on.
    if week < 2 and not os.environ.get("POWER_FORCE"):
        log(f"Week {week}: nothing has been played. Nothing to publish.")
        return 0

    log(f"Week {week}: ranking on play through week {week - 1}")

    scored = sorted(
        ({"espn_team_id": t["id"],
          "team_name": (t.get("name") or f"Team {t['id']}").strip(),
          "score": round(float(overall(t).get("pointsFor") or 0.0), 1),
          "record": record_of(t)}
         for t in data.get("teams") or []),
        key=lambda r: -r["score"],
    )
    ranked = [r | {"season": season, "week": week, "rank": i + 1}
              for i, r in enumerate(scored)]
    # The record belongs in the post, not in the table, which has no column
    # for it.
    rows = [{k: v for k, v in r.items() if k != "record"} for r in ranked]

    # A league where nobody has scored means ESPN has given us no results —
    # the ranking would be alphabetical noise published as though it meant
    # something.
    if sum(1 for r in rows if r["score"] > 0) < len(rows) / 2:
        log(f"Week {week}: ESPN reports no points for most teams. "
            "Refusing to publish a ranking of zeros.")
        return 0

    prior = supabase(
        "GET",
        f"power_rankings?select=espn_team_id,rank&season=eq.{season}&week=eq.{week - 1}",
    ) or []
    previous = {r["espn_team_id"]: r["rank"] for r in prior}

    # The title carries the week that was played, not the week we are in —
    # it was "Week 2 Lineup Strength" for a ranking of week 1's results, which
    # reads as a forecast and is how the old measure confused everybody.
    title = f"Power Rankings — through week {week - 1}"
    body = compose(week, ranked, previous)

    if dry_run:
        log(f"DRY_RUN — would publish '{title}':")
        print(body)
        return 0

    # The conflict target has to match a real unique constraint, and the key
    # gained a source column when a second kind of ranking became possible.
    # Without source named here Postgres has nothing to match and refuses the
    # whole write — which nobody had seen, because this job returns early
    # before week 2 and week 2 is the first time it ever got this far.
    supabase("POST", "power_rankings?on_conflict=season,week,source,espn_team_id", rows,
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
