#!/usr/bin/env python3
"""Landry's Tuesday post-mortem: one private message to each manager.

How their week actually went, and the one thing that would have changed it.
Sent as a direct message rather than a notification, for the same reason his
rounds are: a notification is gone the moment it is dismissed, and this is the
kind of thing somebody wants to re-read on Wednesday.

The arithmetic is all done here — result, margin, the best and worst starter,
and what the optimal lineup from the same roster would have scored. He is asked
only to phrase it, so every number in the message is one that was measured.

The lineup he is compared against is the best legal one from the players that
manager already had, scored on what those players actually did. That is a
hindsight number and the message says so: the point is not that they should
have known, it is how much was sitting there.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  for his voice
    RECAP_WEEK                   override the week (defaults to the last finished)
    RECAP_IGNORE_CLOCK           run regardless of the time in Chicago
    DRY_RUN                      print instead of sending

Usage:
    DRY_RUN=1 ./Scripts/landry_recaps.py
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo

_spec = importlib.util.spec_from_file_location(
    "landry_rounds", pathlib.Path(__file__).with_name("landry_rounds.py"))
rounds = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rounds)

coach = rounds.coach              # the lineup solver
supabase = rounds.supabase
in_landrys_words = rounds.in_landrys_words
log = rounds.log
IN_CHARACTER = rounds.IN_CHARACTER

LEAGUE = ZoneInfo("America/Chicago")
# The hour the league is told to expect him. GitHub's cron is UTC only and does
# not move with daylight saving, so the workflow fires twice and this is what
# makes exactly one of those firings the real one.
SEND_HOUR = 14


def scoreboard(season: int, league: str) -> dict:
    return coach.espn(
        f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}",
        "view=mMatchupScore&view=mBoxscore&view=mTeam&view=mSettings")


def entries(side: dict) -> list[dict]:
    """The roster that played this matchup, with what each player scored."""
    roster = side.get("rosterForMatchupPeriod") or {}
    if not (roster.get("entries") or []):
        roster = side.get("rosterForCurrentScoringPeriod") or {}
    out = []
    for entry in roster.get("entries") or []:
        pool = entry.get("playerPoolEntry") or {}
        player = pool.get("player") or {}
        if not player.get("fullName"):
            continue
        out.append({
            "name": player["fullName"],
            "slot": entry.get("lineupSlotId"),
            "eligible": set(player.get("eligibleSlots") or []),
            "points": float(pool.get("appliedStatTotal") or 0.0),
        })
    return out


def review(side: dict, slots: list[int]) -> dict | None:
    """What this side scored, who carried it, and what was left behind."""
    roster = entries(side)
    if not roster:
        return None

    starters = [p for p in roster if p["slot"] not in (coach.BENCH, coach.IR)]
    if not starters:
        return None

    # Injured reserve is not a choice, so it is not held against anybody.
    available = [p for p in roster if p["slot"] != coach.IR]
    best_total, _ = coach.best_lineup(available, slots)
    actual = sum(p["points"] for p in starters)

    ranked = sorted(starters, key=lambda p: p["points"], reverse=True)
    bench = sorted(
        (p for p in roster if p["slot"] == coach.BENCH),
        key=lambda p: p["points"], reverse=True)

    return {
        "actual": round(actual, 1),
        "ideal": round(best_total, 1),
        "left": round(max(best_total - actual, 0.0), 1),
        "best": ranked[0],
        "worst": ranked[-1],
        "bench_top": bench[0] if bench else None,
    }


def brief_for(name: str, mine: dict, result: str, opponent: str,
              their_score: float, week: int) -> tuple[str, str]:
    """The facts for Landry, and the plain version if he cannot be reached."""
    lines = [
        f"Manager: {name}",
        f"Week {week}: {result} {mine['actual']:.1f} to {their_score:.1f} against {opponent}.",
        f"Best starter: {mine['best']['name']} on {mine['best']['points']:.1f}.",
        f"Quietest starter: {mine['worst']['name']} on {mine['worst']['points']:.1f}.",
    ]
    if mine["left"] >= 0.1:
        lines.append(
            f"Their best possible lineup from the same roster was "
            f"{mine['ideal']:.1f}, so {mine['left']:.1f} points sat on the bench.")
        if mine["bench_top"] and mine["bench_top"]["points"] > mine["worst"]["points"]:
            lines.append(
                f"{mine['bench_top']['name']} scored "
                f"{mine['bench_top']['points']:.1f} from the bench, more than "
                f"{mine['worst']['name']} managed as a starter.")
    else:
        lines.append("They started the best lineup available to them.")

    plain = (
        f"Week {week}: {result} {mine['actual']:.1f}-{their_score:.1f} against "
        f"{opponent}. {mine['best']['name']} led you on "
        f"{mine['best']['points']:.1f}."
    )
    if mine["left"] >= 0.1:
        plain += f" {mine['left']:.1f} points were left on your bench."
    return "\n".join(lines), plain


def main() -> int:
    dry_run = bool(os.environ.get("DRY_RUN"))

    for name in ("ESPN_LEAGUE_ID", "ESPN_S2", "SUPABASE_URL",
                 "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 1

    # The workflow fires at both candidate hours so that daylight saving cannot
    # move him; this is where the wrong one is thrown away.
    now = dt.datetime.now(LEAGUE)
    if now.hour != SEND_HOUR and not (dry_run or os.environ.get("RECAP_IGNORE_CLOCK")):
        log(f"It is {now:%H:%M} in Chicago, not {SEND_HOUR}:00. Not his hour.")
        return 0

    league = os.environ["ESPN_LEAGUE_ID"]
    season = coach.current_season()
    data = scoreboard(season, league)

    current = (data.get("status") or {}).get("currentMatchupPeriod") or 1
    week = int(os.environ.get("RECAP_WEEK") or max(current - 1, 0))
    if week < 1:
        log("No finished week to write about yet.")
        return 0

    counts = ((data.get("settings") or {}).get("rosterSettings") or {}) \
        .get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in sorted((int(k), v) for k, v in counts.items()):
        if slot in (coach.BENCH, coach.IR):
            continue
        slots.extend([slot] * int(count))

    names = {t["id"]: (t.get("name") or f"Team {t['id']}").strip()
             for t in data.get("teams") or []}
    owners = {}
    for team in data.get("teams") or []:
        for owner in team.get("owners") or []:
            owners[(owner or "").strip().strip("{}").upper()] = team["id"]

    profiles = supabase("GET", "profiles?select=id,espn_swid,display_name") or []
    by_team = {}
    for profile in profiles:
        swid = (profile.get("espn_swid") or "").strip().strip("{}").upper()
        if swid and swid in owners:
            by_team[owners[swid]] = profile
    landry = next((p["id"] for p in profiles if p["display_name"] == "Landry"), None)
    if not landry:
        log("Landry has no profile; nothing to send from.")
        return 1

    sent = 0
    for game in data.get("schedule") or []:
        if game.get("matchupPeriodId") != week:
            continue
        winner = (game.get("winner") or "").upper()
        if winner in ("", "UNDECIDED"):
            continue

        for here, there in (("home", "away"), ("away", "home")):
            side, other = game.get(here) or {}, game.get(there) or {}
            team_id = side.get("teamId")
            profile = by_team.get(team_id)
            if not profile:
                continue

            mine = review(side, slots)
            if not mine:
                log(f"  no lineup for {names.get(team_id)}; skipping")
                continue

            theirs = float(other.get("totalPoints") or 0.0)
            result = {"TIE": "tied"}.get(
                winner, "won" if winner == here.upper() else "lost")

            brief, plain = brief_for(
                profile["display_name"], mine, result,
                names.get(other.get("teamId"), "their opponent"), theirs, week)

            body = in_landrys_words(
                brief,
                "Write this as a short private message to that manager about "
                "the week just gone. Three or four sentences. Tell them how it "
                "went, then the one thing that would have changed it. Speak to "
                "them directly, no greeting and no sign-off. If points were "
                "left on the bench, be clear it is hindsight — they could not "
                "have known, it is only worth knowing how much was there. "
                + IN_CHARACTER + "Do not invent any number you were not given.",
                plain,
            )

            if dry_run:
                log(f"  to {profile['display_name']} ({names.get(team_id)}):")
                for line in body.splitlines():
                    log(f"    {line}")
                sent += 1
                continue

            supabase("POST", "direct_messages", [{
                "sender_id": landry,
                "recipient_id": profile["id"],
                "body": body[:2000],
            }], prefer="return=minimal")
            # Unique on (user, kind, subject, season, week), so a re-run cannot
            # send the same manager the same week's post-mortem twice.
            supabase("POST", "landry_notes", [{
                "user_id": profile["id"], "kind": "recap",
                "subject": f"week {week}", "season": season, "week": week,
            }], prefer="return=minimal", )
            sent += 1

    log(f"{'Would send' if dry_run else 'Sent'} {sent} recap(s) for week {week}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
