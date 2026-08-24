#!/usr/bin/env python3
"""Pulls league transactions from ESPN into public.league_activity.

ESPN returns a transaction as team ids and player ids with no names, so this
resolves the names in one extra request and stores the result. Re-running is
safe: rows are keyed on ESPN's own transaction id.

Environment:
    ESPN_S2, ESPN_SWID           league cookies (the league is private)
    ESPN_LEAGUE_ID               numeric league id
    SUPABASE_URL                 https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY    service role key
    ACTIVITY_SEASON              defaults to the current fantasy season
    DRY_RUN                      set to any value to print instead of writing

Usage:
    DRY_RUN=1 ./Scripts/ingest_activity.py
"""

# The runner and this machine may be on 3.9, where `X | None` in an
# annotation is a TypeError at import time.
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
# ESPN's edge rejects browser-like and app-like agents and allows known HTTP
# clients through. Same rule the scoreboard hit.
USER_AGENT = "curl/8.7.1"

# Lineup changes and draft picks are excluded deliberately: one is invisible
# noise, the other is 192 rows that say nothing the draft post did not.
INTERESTING = {"WAIVER", "FREEAGENT", "TRADE_ACCEPT"}


def log(message: str) -> None:
    print(message, file=sys.stderr)


def current_season(today: dt.date | None = None) -> int:
    """Matches Season.current() on iOS and Config.currentSeason() on Android."""
    today = today or dt.date.today()
    return today.year if today.month >= 6 else today.year - 1


def espn(path: str, query: str, extra_headers: dict[str, str] | None = None) -> dict:
    swid = os.environ["ESPN_SWID"]
    request = urllib.request.Request(
        f"{ESPN_HOST}{path}?{query}",
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Cookie": f"espn_s2={os.environ['ESPN_S2']}; SWID={swid}",
            **(extra_headers or {}),
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def player_names(season: int, league: str, ids: list[int]) -> dict[int, str]:
    """Resolves player ids to names. Includes D/ST, whose ids are negative."""
    if not ids:
        return {}
    names: dict[int, str] = {}
    # ESPN rejects very large filters, so ask in batches.
    for start in range(0, len(ids), 50):
        batch = ids[start:start + 50]
        payload = json.dumps({"players": {"filterIds": {"value": batch}}})
        data = espn(
            f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}",
            "view=kona_player_info",
            {"X-Fantasy-Filter": payload},
        )
        for entry in data.get("players") or []:
            player = entry.get("player") or {}
            if player.get("id") is not None and player.get("fullName"):
                names[player["id"]] = player["fullName"]
    return names


def team_names(data: dict) -> dict[int, str]:
    return {
        team["id"]: (team.get("name") or f"Team {team['id']}").strip()
        for team in data.get("teams") or []
    }


def describe(transaction: dict, teams: dict[int, str], names: dict[int, str]) -> dict | None:
    """Turns one ESPN transaction into a row, or None if it is not worth one."""
    items = transaction.get("items") or []
    added = [i for i in items if i.get("type") == "ADD"]
    dropped = [i for i in items if i.get("type") == "DROP"]
    traded = [i for i in items if i.get("type") == "TRADE"]

    def who(team_id: int | None) -> str:
        return teams.get(team_id or 0, "Someone")

    def player(item: dict) -> str:
        return names.get(item.get("playerId"), "a player")

    team = transaction.get("teamId")
    kind: str
    headline: str
    detail: str | None = None

    if traded:
        sides = sorted({i.get("fromTeamId") for i in traded if i.get("fromTeamId")})
        if len(sides) < 2:
            return None
        kind = "trade"
        headline = f"{who(sides[0])} and {who(sides[1])} made a trade"
        moves = [f"{player(i)} to {who(i.get('toTeamId'))}" for i in traded]
        detail = "; ".join(moves) or None
    elif added and dropped:
        kind = "waiver" if transaction.get("type") == "WAIVER" else "add"
        headline = f"{who(team)} picked up {player(added[0])}"
        detail = f"Dropped {player(dropped[0])}"
    elif added:
        kind = "waiver" if transaction.get("type") == "WAIVER" else "add"
        headline = f"{who(team)} picked up {player(added[0])}"
    elif dropped:
        kind = "drop"
        headline = f"{who(team)} dropped {player(dropped[0])}"
    else:
        return None

    # ESPN gives epoch milliseconds. processDate is when it actually happened;
    # proposedDate is when it was asked for, which for a waiver is days earlier.
    stamp = transaction.get("processDate") or transaction.get("proposedDate")
    if not stamp:
        return None
    occurred = dt.datetime.fromtimestamp(stamp / 1000, tz=dt.timezone.utc)

    return {
        "espn_transaction_id": str(transaction.get("id")),
        "kind": kind,
        "espn_team_id": team,
        "headline": headline[:200],
        "detail": detail[:400] if detail else None,
        "occurred_at": occurred.isoformat(),
    }


def upsert(base: str, key: str, rows: list[dict]) -> None:
    body = json.dumps(rows).encode()
    request = urllib.request.Request(
        f"{base}/rest/v1/league_activity?on_conflict=season,espn_transaction_id",
        data=body,
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            # ignore-duplicates: a re-run must not re-notify the league about a
            # trade from last week.
            "Prefer": "return=minimal,resolution=ignore-duplicates",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main() -> int:
    dry_run = bool(os.environ.get("DRY_RUN"))
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    league = os.environ.get("ESPN_LEAGUE_ID", "")
    season = int(os.environ.get("ACTIVITY_SEASON") or current_season())

    if not league or not os.environ.get("ESPN_S2") or not os.environ.get("ESPN_SWID"):
        log("ESPN_LEAGUE_ID, ESPN_S2 and ESPN_SWID are required.")
        return 1
    if not dry_run and (not base or not key):
        log("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required (or set DRY_RUN).")
        return 1

    try:
        data = espn(
            f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}",
            "view=mTransactions2&view=mTeam",
        )
    except urllib.error.HTTPError as error:
        log(f"ESPN returned {error.code}: {error.read()[:200]!r}")
        return 1

    transactions = [
        t for t in data.get("transactions") or []
        if t.get("type") in INTERESTING and t.get("status") == "EXECUTED"
    ]
    log(f"{len(transactions)} transaction(s) worth reporting")

    ids = sorted({
        item["playerId"]
        for t in transactions
        for item in t.get("items") or []
        if item.get("playerId")
    })
    names = player_names(season, league, ids)
    teams = team_names(data)

    rows = []
    for transaction in transactions:
        row = describe(transaction, teams, names)
        if row:
            row["season"] = season
            rows.append(row)

    if not rows:
        log("Nothing to write.")
        return 0

    if dry_run:
        log(f"DRY_RUN — would upsert {len(rows)} row(s):")
        for row in rows[:15]:
            log(f"  {row['occurred_at'][:10]}  {row['headline']}"
                + (f" ({row['detail']})" if row["detail"] else ""))
        return 0

    upsert(base, key, rows)
    log(f"Upserted {len(rows)} row(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
