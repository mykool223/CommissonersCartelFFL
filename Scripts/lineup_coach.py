#!/usr/bin/env python3
"""Works out the best legal lineup and says what to change.

Not a guess and not a language model: every player carries a weekly projection
and a list of slots they are eligible for, so the best lineup is a solved
assignment problem. It is provably optimal against those projections and it
can always explain itself.

Projections are ESPN's. They are not gospel — but "start the higher projection"
beats "start whoever you drafted higher", which is what most weeks come down
to.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PUSH_SECRET
    COACH_WEEK                   override the week
    COACH_MIN_GAIN               points below which it stays quiet (default 3)
    DRY_RUN                      print instead of pushing

Usage:
    DRY_RUN=1 ./Scripts/lineup_coach.py
"""

from __future__ import annotations

import datetime as dt
import functools
import json
import os
import sys
import urllib.error
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
USER_AGENT = "curl/8.7.1"

BENCH, IR = 20, 21

SLOT_NAMES = {
    0: "QB", 2: "RB", 4: "WR", 6: "TE", 16: "D/ST", 17: "K", 23: "FLEX",
    BENCH: "Bench", IR: "IR",
}

# Nobody should be started, whatever the projection says.
UNPLAYABLE = {"OUT", "DOUBTFUL", "INJURY_RESERVE", "SUSPENSION", "NOT_ACTIVE"}


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


def projection(player: dict, week: int) -> float:
    """ESPN's projected points for this week. statSourceId 1 is the projection."""
    for row in player.get("stats") or []:
        if row.get("statSourceId") == 1 and row.get("scoringPeriodId") == week:
            return float(row.get("appliedTotal") or 0.0)
    return 0.0


def best_lineup(players: list[dict], slots: list[int]) -> tuple[float, dict[int, int]]:
    """Highest-scoring legal assignment of players to starting slots.

    Exact rather than greedy. Greedy fails the case that matters most: filling
    FLEX first with the best available player can strand a position slot with
    nobody eligible for it.

    Returns the total and a map of slot index -> player index.
    """
    @functools.lru_cache(maxsize=None)
    def solve(slot_index: int, used: int) -> tuple[float, tuple[int, ...]]:
        if slot_index == len(slots):
            return 0.0, ()

        best = (float("-inf"), ())
        slot = slots[slot_index]
        for index, player in enumerate(players):
            if used & (1 << index):
                continue
            if slot not in player["eligible"]:
                continue
            rest, tail = solve(slot_index + 1, used | (1 << index))
            total = player["points"] + rest
            if total > best[0]:
                best = (total, (index,) + tail)

        # A slot with nobody eligible is left empty rather than failing: a
        # short roster is a real situation, not an error.
        empty, tail = solve(slot_index + 1, used)
        if empty > best[0]:
            best = (empty, (-1,) + tail)
        return best

    total, picks = solve(0, 0)
    return total, {i: p for i, p in enumerate(picks) if p >= 0}


def analyse(team: dict, week: int, slots: list[int]) -> dict | None:
    """What this team should change, if anything."""
    players = []
    for entry in (team.get("roster") or {}).get("entries") or []:
        raw = (entry.get("playerPoolEntry") or {}).get("player") or {}
        status = (raw.get("injuryStatus") or "").upper()
        eligible = set(raw.get("eligibleSlots") or [])
        # Someone who cannot play is worth zero, whatever ESPN projects. That
        # makes the optimiser bench them without a special case.
        points = 0.0 if status in UNPLAYABLE else projection(raw, week)
        players.append({
            "id": raw.get("id"),
            "name": raw.get("fullName") or "A player",
            "eligible": eligible,
            "points": points,
            "slot": entry.get("lineupSlotId"),
            "status": status,
        })

    if not players:
        return None

    current = sum(p["points"] for p in players if p["slot"] not in (BENCH, IR))
    total, assignment = best_lineup(players, slots)

    starting = {assignment[i] for i in assignment}
    benched_now = {i for i, p in enumerate(players) if p["slot"] in (BENCH, IR)}

    # Somebody on the bench who should start, and who they replace.
    promotions = [players[i] for i in starting if i in benched_now]
    demotions = [
        p for i, p in enumerate(players)
        if i not in starting and p["slot"] not in (BENCH, IR)
    ]

    return {
        "team": (team.get("name") or f"Team {team['id']}").strip(),
        "team_id": team["id"],
        "owner": next(iter(team.get("owners") or []), None),
        "current": current,
        "best": total,
        "gain": total - current,
        "promotions": promotions,
        "demotions": demotions,
    }


def rest(method: str, path: str, body: object | None = None):
    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    request = urllib.request.Request(
        f"{base}/rest/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            "apikey": key, "Authorization": f"Bearer {key}",
            "Content-Type": "application/json", "Prefer": "return=minimal",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def push(title: str, body: str, only_user: str) -> None:
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/push",
        data=json.dumps({
            "kind": "lineup", "title": title, "body": body, "only_user": only_user,
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
    min_gain = float(os.environ.get("COACH_MIN_GAIN", "3"))

    if not league or not os.environ.get("ESPN_S2"):
        log("ESPN_LEAGUE_ID, ESPN_S2 and ESPN_SWID are required.")
        return 1

    path = f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}"
    data = espn(path, "view=mRoster&view=mTeam&view=mSettings")
    week = int(os.environ.get("COACH_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    counts = ((data.get("settings") or {}).get("rosterSettings") or {}).get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in sorted((int(k), v) for k, v in counts.items()):
        if slot in (BENCH, IR):
            continue
        slots.extend([slot] * int(count))

    log(f"Week {week}; starting slots: {[SLOT_NAMES.get(s, s) for s in slots]}")

    profiles = rest("GET", "profiles?select=id,espn_swid") or []
    user_by_swid = {
        (p.get("espn_swid") or "").strip().upper(): p["id"]
        for p in profiles if p.get("espn_swid")
    }

    sent = 0
    for team in data.get("teams") or []:
        result = analyse(team, week, slots)
        if not result:
            continue

        if dry_run:
            log(f"  {result['team']}: {result['current']:.1f} -> {result['best']:.1f} "
                f"({result['gain']:+.1f})")
            for up, down in zip(result["promotions"], result["demotions"]):
                log(f"      start {up['name']} ({up['points']:.1f}) "
                    f"over {down['name']} ({down['points']:.1f})")
            continue

        if result["gain"] < min_gain or not result["promotions"]:
            continue

        user = user_by_swid.get((result["owner"] or "").strip().upper())
        if not user:
            continue

        swaps = [
            f"{up['name']} over {down['name']}"
            for up, down in zip(result["promotions"], result["demotions"])
        ]
        push(
            "Your lineup could be better",
            f"Worth {result['gain']:.1f} more points: start " + "; ".join(swaps) + ".",
            user,
        )
        sent += 1

    log(f"{sent} suggestion(s) sent." if not dry_run else "Dry run complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
