#!/usr/bin/env python3
"""Awards the week's trophies once its games are final.

Two of them: the highest fantasy score of the week, and the best pick'em
board. They come from different places — the first from ESPN, the second from
the confidence pool in Supabase — and either can be skipped without affecting
the other.

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


def supabase_get(path: str) -> list[dict]:
    """Reads with the service role key, so row level security does not apply.

    The pick'em standings are deliberately private until kickoff — you cannot
    read another member's picks — so an anon read here would see almost
    nothing and hand out the trophy to whoever happened to be visible.
    """
    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    request = urllib.request.Request(
        f"{base}/rest/v1/{path}",
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def normalise_swid(swid: str | None) -> str:
    """ESPN writes a SWID as '{1A2B-...}'. Compare without the braces or case."""
    return (swid or "").strip().strip("{}").upper()


def teams_by_swid(data: dict) -> dict[str, int]:
    """SWID -> ESPN team id, for every owner of every team."""
    out: dict[str, int] = {}
    for team in data.get("teams") or []:
        for owner in team.get("owners") or []:
            key = normalise_swid(owner)
            if key:
                out[key] = team["id"]
    return out


def pickem_awards(
    standings: list[dict],
    swid_by_user: dict[str, str],
    team_by_swid: dict[str, int],
    season: int,
    week: int,
) -> tuple[list[dict], list[str]]:
    """Trophy rows for the best pick'em board, plus anything worth logging.

    Everyone tied at the top wins: a confidence pool ends level often enough
    that dropping a co-winner would be noticed, and argued about.

    A member who has never told the app which ESPN team is theirs cannot be
    given a trophy — the case is keyed by team, not by account — so they are
    named in the notes rather than silently passed over.
    """
    scored = [row for row in standings if (row.get("points") or 0) > 0]
    if not scored:
        return [], ["nobody scored in the pick'em; no trophy"]

    best = max(row["points"] for row in scored)
    winners = [row for row in scored if row["points"] == best]

    rows: list[dict] = []
    notes: list[str] = []
    for winner in sorted(winners, key=lambda r: str(r.get("display_name") or "")):
        name = winner.get("display_name") or "Someone"
        swid = normalise_swid(swid_by_user.get(winner["user_id"]))
        team = team_by_swid.get(swid) if swid else None
        if team is None:
            notes.append(f"{name} won the pick'em but has no ESPN team claimed; not awarded")
            continue
        rows.append({
            "season": season,
            "week": week,
            "espn_team_id": team,
            "kind": "pickem_top",
            "title": f"Best pick'em, week {week}",
            "detail": f"{name} — {best} points, "
                      f"{winner.get('correct', 0)} of {winner.get('decided', 0)} right",
        })
    if len(rows) > 1:
        notes.append(f"{len(rows)} tied on {best} points; all awarded")
    return rows, notes


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


def pickem_rows(data: dict, season: int, week: int) -> list[dict]:
    """The week's pick'em trophy, or nothing if the week cannot be settled yet.

    The pick'em runs on the NFL's week and is settled by its own sync, not by
    ESPN's fantasy matchup period. Awarding it while a game is still going
    would hand the trophy to whoever happened to be ahead at the time.
    """
    if not os.environ.get("SUPABASE_URL") or not os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        log("No Supabase credentials; skipping the pick'em trophy.")
        return []

    games = supabase_get(f"pickem_games?season=eq.{season}&week=eq.{week}&select=final")
    if not games:
        log(f"Week {week} has no pick'em fixtures to settle.")
        return []
    if not all(game["final"] for game in games):
        done = sum(1 for game in games if game["final"])
        log(f"Pick'em week {week} is still going ({done}/{len(games)} final); "
            "leaving that trophy until it is settled.")
        return []

    standings = supabase_get(
        f"pickem_standings?season=eq.{season}&week=eq.{week}"
        "&select=user_id,display_name,correct,decided,points"
    )
    profiles = supabase_get("profiles?select=id,espn_swid")
    rows, notes = pickem_awards(
        standings,
        {profile["id"]: profile.get("espn_swid") for profile in profiles},
        teams_by_swid(data),
        season,
        week,
    )
    for note in notes:
        log(f"  {note}")
    return rows


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

    rows: list[dict] = []

    scores = performances(data, week)
    if not scores:
        log(f"Week {week} has no completed fixtures.")
    else:
        names = {
            t["id"]: (t.get("name") or f"Team {t['id']}").strip()
            for t in data.get("teams") or []
        }
        best = max(scores, key=lambda pair: pair[1])
        rows.append({
            "season": season,
            "week": week,
            "espn_team_id": best[0],
            "kind": "top_score",
            "title": f"Top score, week {week}",
            "detail": f"{names.get(best[0], 'A team')} — {best[1]:.1f} points",
        })

    rows.extend(pickem_rows(data, season, week))

    if not rows:
        log(f"Nothing to award for week {week}.")
        return 0

    if dry_run:
        log(f"DRY_RUN — would award {len(rows)}:")
        for row in rows:
            log(f"  {row['title']}: {row['detail']}")
        return 0

    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    request = urllib.request.Request(
        f"{base}/rest/v1/trophies?on_conflict=season,week,kind,espn_team_id",
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
    log(f"Awarded {len(rows)} trophy/trophies for week {week}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
