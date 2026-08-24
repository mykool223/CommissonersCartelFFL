#!/usr/bin/env python3
"""Finds free agents who would actually improve your lineup.

Not "best available", which is how people end up with a fourth running back
they will never start. The measure is what a player adds to your *best legal
lineup* — sign them, re-solve, and see whether the total moves. A brilliant
tight end is worth nothing to a team that already has a better one.

Runs before waivers process. Nothing here claims a player; it only says who is
worth a claim.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PUSH_SECRET
    WAIVER_WEEK                  override the week
    WAIVER_MIN_GAIN              points below which it stays quiet (default 2)
    DRY_RUN                      print instead of pushing

Usage:
    DRY_RUN=1 ./Scripts/waiver_coach.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.request

import importlib.util
import pathlib

_spec = importlib.util.spec_from_file_location(
    "coach", pathlib.Path(__file__).with_name("lineup_coach.py")
)
coach = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(coach)

# Only the slots worth a waiver claim. Kickers and defences churn weekly and
# suggesting them every week is how this becomes noise.
CLAIMABLE_SLOTS = [0, 2, 4, 6]


def log(message: str) -> None:
    print(message, file=sys.stderr)


def free_agents(season: int, league: str, limit: int = 75) -> list[dict]:
    payload = json.dumps({
        "players": {
            "filterStatus": {"value": ["FREEAGENT", "WAIVERS"]},
            "filterSlotIds": {"value": CLAIMABLE_SLOTS},
            "limit": limit,
            "sortPercOwned": {"sortAsc": False, "sortPriority": 1},
        }
    })
    request = urllib.request.Request(
        f"{coach.ESPN_HOST}/apis/v3/games/ffl/seasons/{season}"
        f"/segments/0/leagues/{league}?view=kona_player_info",
        headers={
            "User-Agent": coach.USER_AGENT,
            "Accept": "application/json",
            "Cookie": f"espn_s2={os.environ['ESPN_S2']}; SWID={os.environ['ESPN_SWID']}",
            "X-Fantasy-Filter": payload,
        },
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        return (json.load(response).get("players") or [])


def roster_players(team: dict, week: int) -> list[dict]:
    out = []
    for entry in (team.get("roster") or {}).get("entries") or []:
        raw = (entry.get("playerPoolEntry") or {}).get("player") or {}
        status = (raw.get("injuryStatus") or "").upper()
        out.append({
            "id": raw.get("id"),
            "name": raw.get("fullName") or "A player",
            "eligible": set(raw.get("eligibleSlots") or []),
            "points": 0.0 if status in coach.UNPLAYABLE else coach.projection(raw, week),
            "slot": entry.get("lineupSlotId"),
        })
    return out


def value_added(
    roster: list[dict], candidate: dict, slots: list[int], before: float
) -> float:
    """What this player would add to the best legal lineup, in points."""
    after, _ = coach.best_lineup(roster + [candidate], slots)
    return after - before


def upper_bound(candidate: dict, weakest_starter: float) -> float:
    """The most this player could possibly add.

    Signing somebody can only help by displacing a starter, and the best case
    is displacing the weakest one — even allowing for a chain of moves through
    FLEX, nobody worse than that leaves the lineup. Candidates that cannot beat
    the threshold on their best day are skipped without solving for them, which
    is the difference between this job taking ninety seconds and taking five.

    Clamped at zero: signing somebody can never make a lineup worse, since you
    are not obliged to start them. Without the clamp the bound reads negative
    for a player nobody would want, which is a smaller number than the real
    gain of zero — an upper bound that understates is not an upper bound.
    """
    return max(0.0, candidate["points"] - weakest_starter)


def main() -> int:
    dry_run = bool(os.environ.get("DRY_RUN"))
    league = os.environ.get("ESPN_LEAGUE_ID", "")
    season = coach.current_season()
    min_gain = float(os.environ.get("WAIVER_MIN_GAIN", "2"))

    if not league or not os.environ.get("ESPN_S2"):
        log("ESPN_LEAGUE_ID, ESPN_S2 and ESPN_SWID are required.")
        return 1

    path = f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}"
    data = coach.espn(path, "view=mRoster&view=mTeam&view=mSettings")
    week = int(os.environ.get("WAIVER_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    counts = ((data.get("settings") or {}).get("rosterSettings") or {}).get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in sorted((int(k), v) for k, v in counts.items()):
        if slot in (coach.BENCH, coach.IR):
            continue
        slots.extend([slot] * int(count))

    pool = []
    for entry in free_agents(season, league):
        raw = entry.get("player") or {}
        points = coach.projection(raw, week)
        if points <= 0:
            continue
        pool.append({
            "id": raw.get("id"),
            "name": raw.get("fullName") or "A player",
            "eligible": set(raw.get("eligibleSlots") or []),
            "points": points,
            "owned": round((raw.get("ownership") or {}).get("percentOwned") or 0, 1),
            "slot": coach.BENCH,
        })

    log(f"Week {week}; {len(pool)} free agent(s) with a projection")

    profiles = None
    if not dry_run:
        request = urllib.request.Request(
            f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/profiles?select=id,espn_swid",
            headers={
                "apikey": os.environ["SUPABASE_SERVICE_ROLE_KEY"],
                "Authorization": f"Bearer {os.environ['SUPABASE_SERVICE_ROLE_KEY']}",
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            profiles = json.load(response)
    user_by_swid = {
        (p.get("espn_swid") or "").strip().upper(): p["id"]
        for p in (profiles or []) if p.get("espn_swid")
    }

    sent = 0
    for team in data.get("teams") or []:
        roster = roster_players(team, week)
        if not roster:
            continue

        before, assignment = coach.best_lineup(roster, slots)
        starters = [roster[i]["points"] for i in assignment.values()]
        weakest = min(starters) if starters else 0.0

        candidates = [
            player for player in pool
            if upper_bound(player, weakest) >= min_gain
        ]
        ranked = sorted(
            ((value_added(roster, player, slots, before), player) for player in candidates),
            key=lambda pair: pair[0],
            reverse=True,
        )[:3]
        worth_it = [(gain, player) for gain, player in ranked if gain >= min_gain]

        name = (team.get("name") or f"Team {team['id']}").strip()
        if dry_run:
            if worth_it:
                log(f"  {name}:")
                for gain, player in worth_it:
                    log(f"      {player['name']:24} +{gain:.1f}  ({player['owned']}% owned)")
            else:
                log(f"  {name}: nobody worth claiming")
            continue

        if not worth_it:
            continue
        user = user_by_swid.get((next(iter(team.get("owners") or []), "") or "").strip().upper())
        if not user:
            continue

        best_gain, best_player = worth_it[0]
        others = ", ".join(p["name"] for _, p in worth_it[1:])
        body = f"{best_player['name']} would add {best_gain:.1f} points to your lineup."
        if others:
            body += f" Also worth a look: {others}."

        request = urllib.request.Request(
            f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/push",
            data=json.dumps({
                "kind": "lineup", "title": "Worth a waiver claim",
                "body": body, "only_user": user,
            }).encode(),
            method="POST",
            headers={
                "Authorization": f"Bearer {os.environ['PUSH_SECRET']}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            response.read()
        sent += 1

    log("Dry run complete." if dry_run else f"{sent} suggestion(s) sent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
