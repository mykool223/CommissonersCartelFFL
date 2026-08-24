#!/usr/bin/env python3
"""Tells managers when their fixture turns, and how it ended.

Runs through Sunday and Monday night. Pushes on two events only:

  - the lead changes hands
  - the fixture goes final

Anything more often is noise; anything less and the app is something you check
rather than something that tells you. Both managers hear about it, each from
their own side.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PUSH_SECRET
    DRY_RUN                      print instead of pushing

Usage:
    DRY_RUN=1 ./Scripts/live_matchups.py
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
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.load(response)


def rest(method: str, path: str, body: object | None = None, prefer: str = "return=minimal"):
    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    request = urllib.request.Request(
        f"{base}/rest/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": prefer,
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def push(title: str, body: str, only_user: str) -> None:
    url = f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/push"
    request = urllib.request.Request(
        url,
        data=json.dumps({
            "kind": "matchup", "title": title, "body": body, "only_user": only_user,
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

    path = f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}"
    data = espn(path, "view=mMatchupScore&view=mTeam")
    week = (data.get("status") or {}).get("currentMatchupPeriod") or 1

    names = {t["id"]: (t.get("name") or f"Team {t['id']}").strip() for t in data.get("teams") or []}
    owners = {
        t["id"]: next(iter(t.get("owners") or []), None)
        for t in data.get("teams") or []
    }

    profiles = rest("GET", "profiles?select=id,espn_swid") or []
    user_by_swid = {(p.get("espn_swid") or "").strip(): p["id"] for p in profiles if p.get("espn_swid")}

    previous = {
        (row["home_team_id"], row["away_team_id"]): row
        for row in rest("GET", f"matchup_watch?select=*&season=eq.{season}&week=eq.{week}") or []
    }

    events: list[tuple[str, str, str]] = []   # (user_id, title, body)
    rows: list[dict] = []

    for game in data.get("schedule") or []:
        if game.get("matchupPeriodId") != week:
            continue
        home, away = game.get("home") or {}, game.get("away") or {}
        if home.get("teamId") is None or away.get("teamId") is None:
            continue

        hp = float(home.get("totalPoints") or 0)
        ap = float(away.get("totalPoints") or 0)
        final = (game.get("winner") or "").upper() not in ("", "UNDECIDED")

        # Nothing has happened yet; do not announce a 0-0 "lead".
        if hp == 0 and ap == 0 and not final:
            continue

        leader = None
        if hp > ap:
            leader = home["teamId"]
        elif ap > hp:
            leader = away["teamId"]

        key = (home["teamId"], away["teamId"])
        before = previous.get(key)
        rows.append({
            "season": season, "week": week,
            "home_team_id": home["teamId"], "away_team_id": away["teamId"],
            "leader_team_id": leader, "home_points": round(hp, 2),
            "away_points": round(ap, 2), "is_final": final,
            "updated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        })

        def notify(team_id: int, opponent_id: int, title: str, body: str) -> None:
            swid = owners.get(team_id)
            user = user_by_swid.get((swid or "").strip())
            if user:
                events.append((user, title, body))

        if final and not (before or {}).get("is_final"):
            winner = leader
            for team_id, points, other, other_points in (
                (home["teamId"], hp, away["teamId"], ap),
                (away["teamId"], ap, home["teamId"], hp),
            ):
                verdict = "won" if team_id == winner else "lost"
                if winner is None:
                    verdict = "tied"
                notify(
                    team_id, other, "Final",
                    f"You {verdict} {points:.1f} to {other_points:.1f} against {names.get(other, 'them')}.",
                )
        elif not final and before and before.get("leader_team_id") != leader and leader is not None:
            behind = away["teamId"] if leader == home["teamId"] else home["teamId"]
            lead_points, trail_points = (hp, ap) if leader == home["teamId"] else (ap, hp)
            notify(
                leader, behind, "You're ahead",
                f"You've taken the lead over {names.get(behind, 'them')}, "
                f"{lead_points:.1f} to {trail_points:.1f}.",
            )
            notify(
                behind, leader, "You're behind",
                f"{names.get(leader, 'They')} have gone ahead, "
                f"{lead_points:.1f} to {trail_points:.1f}.",
            )

    if dry_run:
        log(f"Week {week}: {len(rows)} live fixture(s), {len(events)} notification(s)")
        for _, title, body in events:
            log(f"  {title}: {body}")
        return 0

    if rows:
        rest("POST", "matchup_watch?on_conflict=season,week,home_team_id,away_team_id",
             rows, prefer="return=minimal,resolution=merge-duplicates")

    for user, title, body in events:
        try:
            push(title, body, user)
        except urllib.error.HTTPError as error:
            log(f"  push failed: {error.code}")

    log(f"Week {week}: {len(events)} notification(s) sent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
