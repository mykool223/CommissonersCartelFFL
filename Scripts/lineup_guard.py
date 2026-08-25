#!/usr/bin/env python3
"""Warns a manager when their starting lineup contains someone who cannot play.

Runs on Sunday mornings. Checks every team's starters for players who are out,
doubtful, on injured reserve, suspended, or whose NFL team is on a bye, and
pushes to that manager alone — a warning sent to the league would be worse than
useless.

Each warning is recorded, so running the job repeatedly on a Sunday does not
tell somebody about the same mistake every half hour.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  shared secret for the push function
    LINEUP_WEEK                  override the week (defaults to ESPN's current)
    DRY_RUN                      print instead of pushing

Usage:
    DRY_RUN=1 ./Scripts/lineup_guard.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
USER_AGENT = "curl/8.7.1"

# 20 is the bench, 21 is injured reserve. Everything else is a starting slot.
BENCH_SLOTS = {20, 21}

# Statuses worth interrupting somebody's Sunday for. QUESTIONABLE is
# deliberately absent from this set: half the league is questionable on any
# given week, and a warning that fires constantly gets muted. It is handled
# separately below, on evidence rather than on the label.
BLOCKING = {"OUT", "DOUBTFUL", "INJURY_RESERVE", "SUSPENSION", "NOT_ACTIVE"}

# FantasyPros reads the practice reports and puts a number on whether somebody
# will actually play. Below this, a "questionable" starter is worth a warning
# even though ESPN says nothing is wrong — this is the case that quietly costs
# people games.
UNLIKELY_TO_PLAY = 0.5

REASON_TEXT = {
    "OUT": "is out",
    "DOUBTFUL": "is doubtful",
    "INJURY_RESERVE": "is on injured reserve",
    "SUSPENSION": "is suspended",
    "NOT_ACTIVE": "is not active",
    "BYE": "is on a bye",
}


def projection(player: dict, week: int) -> float:
    """ESPN's projection for the week. statSourceId 1 is the projected line."""
    for row in player.get("stats") or []:
        if row.get("statSourceId") == 1 and row.get("scoringPeriodId") == week:
            return float(row.get("appliedTotal") or 0)
    return 0.0


def best_replacement(team: dict, slot: int, week: int) -> tuple[str, float] | None:
    """The strongest bench player eligible for a slot, so a warning can say
    what to do about it rather than only that something is wrong."""
    best = None
    for entry in (team.get("roster") or {}).get("entries") or []:
        if entry.get("lineupSlotId") not in BENCH_SLOTS:
            continue
        player = (entry.get("playerPoolEntry") or {}).get("player") or {}
        if slot not in (player.get("eligibleSlots") or []):
            continue
        if (player.get("injuryStatus") or "").upper() in BLOCKING:
            continue
        points = projection(player, week)
        if best is None or points > best[1]:
            best = (player.get("fullName") or "somebody", points)
    return best


def play_probabilities(season: int, week: int) -> dict[int, float]:
    """Chance of playing, per ESPN player id, from the FantasyPros cache.

    Empty if the nightly sync has never run, in which case the guard behaves
    exactly as it did before.
    """
    rows = supabase(
        "GET",
        "fantasypros_injuries?select=probability,fantasypros_players!inner(espn_id)"
        f"&season=eq.{season}&week=eq.{week}&probability=not.is.null",
    ) or []
    out: dict[int, float] = {}
    for row in rows:
        espn_id = (row.get("fantasypros_players") or {}).get("espn_id")
        if espn_id is not None and row.get("probability") is not None:
            out[int(espn_id)] = float(row["probability"])
    return out


def log(message: str) -> None:
    print(message, file=sys.stderr)


def in_landrys_words(brief: str, fallback: str) -> str:
    """Asks the coach to say it, and settles for the plain version if he cannot.

    The arithmetic is already done here — who is starting, how likely they are
    to play, who is behind them. He is given those facts and asked only to
    phrase them, which is the one thing he is better at than a format string.
    """
    secret = os.environ.get("PUSH_SECRET")
    if not secret:
        return fallback
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/landry",
        data=json.dumps({
            "brief": brief,
            "instruction": (
                "Write the body of a push notification telling this manager to "
                "fix it. Two sentences at most. No greeting, no sign-off, and "
                "do not invent any number you were not given."),
        }).encode(),
        method="POST",
        headers={"Content-Type": "application/json", "x-cartel-secret": secret},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            said = (json.load(response).get("text") or "").strip()
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as error:
        log(f"  coach unavailable ({error}); sending the plain version")
        return fallback
    # A notification body has a practical ceiling; anything longer is a sign
    # he ignored the instruction, and the plain version is better than a
    # truncated paragraph.
    return said if said and len(said) <= 220 else fallback


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


def supabase(method: str, path: str, body: object | None = None) -> object:
    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        f"{base}/rest/v1/{path}",
        data=data,
        method=method,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal,resolution=ignore-duplicates",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def push(kind: str, title: str, body: str, only_user: str) -> None:
    url = f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/push"
    request = urllib.request.Request(
        url,
        data=json.dumps({
            "kind": kind, "title": title, "body": body, "only_user": only_user,
        }).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {os.environ['PUSH_SECRET']}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main() -> int:
    dry_run = bool(os.environ.get("DRY_RUN"))
    league = os.environ.get("ESPN_LEAGUE_ID", "")
    season = current_season()

    if not league or not os.environ.get("ESPN_S2"):
        log("ESPN_LEAGUE_ID, ESPN_S2 and ESPN_SWID are required.")
        return 1

    league_path = f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}"
    data = espn(league_path, "view=mRoster&view=mTeam&view=mSettings")
    week = int(os.environ.get("LINEUP_WEEK") or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    chances = play_probabilities(season, week)
    log(f"  {len(chances)} player(s) carry a practice-report probability")

    pro = espn(f"/apis/v3/games/ffl/seasons/{season}", "view=proTeamSchedules_wl")
    pro_teams = (pro.get("settings") or {}).get("proTeams") or pro.get("proTeams") or []
    bye = {t["id"]: t.get("byeWeek") for t in pro_teams if t.get("id") is not None}

    # Only members who have said which team is theirs can be warned about it.
    profiles = supabase("GET", "profiles?select=id,espn_swid,display_name") or []
    by_swid = {
        (p.get("espn_swid") or "").strip(): p
        for p in profiles if p.get("espn_swid")
    }

    log(f"Week {week}; {len(by_swid)} member(s) have claimed a team")

    problems: list[dict] = []
    for team in data.get("teams") or []:
        owner = next((o for o in team.get("owners") or [] if o in by_swid), None)
        if not owner:
            continue
        profile = by_swid[owner]

        for entry in (team.get("roster") or {}).get("entries") or []:
            if entry.get("lineupSlotId") in BENCH_SLOTS:
                continue
            player = (entry.get("playerPoolEntry") or {}).get("player") or {}
            name = player.get("fullName") or "A player"
            status = (player.get("injuryStatus") or "").upper()

            reason = None
            detail = None
            if status in BLOCKING:
                reason = status
            elif bye.get(player.get("proTeamId")) == week:
                reason = "BYE"
            else:
                chance = chances.get(player.get("id"))
                if chance is not None and chance < UNLIKELY_TO_PLAY:
                    reason = "UNLIKELY"
                    detail = f"is only {round(chance * 100)}% likely to play"
                    stand_in = best_replacement(
                        team, entry.get("lineupSlotId"), week)
                    if stand_in and stand_in[1] > 0:
                        detail += (f", and {stand_in[0]} projects "
                                   f"{stand_in[1]:.1f} on your bench")
            if not reason:
                continue

            problems.append({
                "season": season,
                "week": week,
                "user_id": profile["id"],
                "espn_team_id": team["id"],
                "player_id": player.get("id") or entry.get("playerId"),
                "reason": reason,
                "detail": detail,
                "name": name,
                "team_name": (team.get("name") or "your team").strip(),
            })

    if not problems:
        log("Every lineup is clean.")
        return 0

    # Already-warned players, so a second run today stays quiet.
    existing = supabase(
        "GET",
        f"lineup_alerts?select=user_id,player_id&season=eq.{season}&week=eq.{week}",
    ) or []
    seen = {(row["user_id"], row["player_id"]) for row in existing}
    fresh = [p for p in problems if (p["user_id"], p["player_id"]) not in seen]

    log(f"{len(problems)} problem(s), {len(fresh)} not yet reported")

    for problem in fresh:
        problem["body"] = in_landrys_words(
            f"{problem['team_name']} is starting {problem['name']}, who "
            f"{problem['detail'] or REASON_TEXT[problem['reason']]}.",
            f"{problem['name']} "
            f"{problem['detail'] or REASON_TEXT[problem['reason']]}"
            " and is in your starting lineup.",
        )

    if dry_run:
        for p in fresh:
            log(f"  to {p['team_name']}:")
            log(f"    {p['body']}")
        return 0

    for problem in fresh:
        body = problem["body"]
        try:
            push("lineup", "Check your lineup", body, problem["user_id"])
        except urllib.error.HTTPError as error:
            log(f"  push failed for {problem['name']}: {error.code}")
            continue
        supabase("POST", "lineup_alerts", [{
            k: problem[k] for k in
            ("season", "week", "user_id", "espn_team_id", "player_id", "reason")
        }])

    log(f"Warned about {len(fresh)} player(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
