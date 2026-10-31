#!/usr/bin/env python3
"""Landry's Thursday scouting report: a private look at this week's opponent.

Every manager with a game this week gets one, about the team across from them:
both projected totals, where the opponent is strong and where they are thin,
which of their starters is carrying an injury, and the position most likely to
decide it. Thursday morning, because Thursday is still early enough to do
something about it — a claim, a swap, an offer — and late enough that the
week's injury reports mean something.

Sent as a direct message, like his rounds and the post-mortem: a report on
somebody's weaknesses is between Landry and the man who has to play them.

The arithmetic is all done here, in scout(), and he is asked only to phrase
it. Both totals are the best legal lineup from each roster on this week's ESPN
projections — what each side can do if it sets its lineup properly, which is
the honest comparison when one of them has not set it yet.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  for his voice
    SCOUT_WEEK                   override the week (defaults to ESPN's current)
    SCOUT_ONLY                   send to this manager alone, by display name
    SCOUT_RESEND                 send again to somebody who already has it
    DRY_RUN                      print instead of sending

Usage:
    DRY_RUN=1 ./Scripts/landry_scouting.py
"""

from __future__ import annotations

import importlib.util
import os
import pathlib
import sys

_spec = importlib.util.spec_from_file_location(
    "landry_rounds", pathlib.Path(__file__).with_name("landry_rounds.py"))
rounds = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rounds)

coach = rounds.coach              # the lineup solver
waivers = rounds.waivers          # roster_players
supabase = rounds.supabase
in_landrys_words = rounds.in_landrys_words
log = rounds.log
IN_CHARACTER = rounds.IN_CHARACTER

# The positions a starter is counted under. FLEX is a slot, not a position: a
# running back in the FLEX is running-back strength, and adding him to a
# "FLEX" column would hide that a team is deep at the position.
POSITIONS = {0: "QB", 2: "RB", 4: "WR", 6: "TE", 16: "D/ST", 17: "K"}

# An opponent's starter worth naming, short of a status that rules him out.
FLAGGED = {"QUESTIONABLE", "DOUBTFUL", "OUT", "INJURY_RESERVE", "SUSPENSION"}
UNLIKELY_TO_PLAY = 0.5


def position_of(player: dict) -> str | None:
    """The one real position a player is eligible at."""
    for slot, name in POSITIONS.items():
        if slot in player["eligible"]:
            return name
    return None


def by_position(players: list[dict], slots: list[int]) -> tuple[float, dict[str, float], dict[str, dict]]:
    """The best lineup's total, its points per position, and its top player at each."""
    total, picks = coach.best_lineup(players, slots)
    points: dict[str, float] = {}
    top: dict[str, dict] = {}
    for index in picks.values():
        player = players[index]
        position = position_of(player)
        if position is None:
            continue
        points[position] = points.get(position, 0.0) + player["points"]
        if position not in top or player["points"] > top[position]["points"]:
            top[position] = player
    return total, points, top


def scout(mine: list[dict], theirs: list[dict], slots: list[int]) -> dict:
    """Everything the report says, measured. Landry is given this and nothing else.

    Gaps are theirs minus mine, by position, over both best lineups: positive
    is where they out-project you, negative where you out-project them. The
    deciding position is whichever gap is biggest either way, because a report
    that only lists strengths cannot tell a man where the game will turn.
    """
    my_total, my_points, my_top = by_position(mine, slots)
    their_total, their_points, their_top = by_position(theirs, slots)

    gaps = {
        position: round(their_points.get(position, 0.0) - my_points.get(position, 0.0), 1)
        for position in sorted(set(my_points) | set(their_points))
    }
    strong = max(gaps.items(), key=lambda kv: kv[1], default=None)
    thin = min(gaps.items(), key=lambda kv: kv[1], default=None)
    deciding = max(gaps.items(), key=lambda kv: abs(kv[1]), default=None)

    def face_off(position: str) -> dict:
        return {
            "position": position,
            "gap": gaps[position],
            "theirs": (their_top.get(position) or {}).get("name"),
            "yours": (my_top.get(position) or {}).get("name"),
        }

    return {
        "mine": round(my_total, 1),
        "theirs": round(their_total, 1),
        "margin": round(my_total - their_total, 1),
        # Only a real edge: a position where they lead is not "thin".
        "strong": face_off(strong[0]) if strong and strong[1] > 0 else None,
        "thin": face_off(thin[0]) if thin and thin[1] < 0 else None,
        "deciding": face_off(deciding[0]) if deciding and deciding[1] != 0 else None,
    }


def injured_starters(team: dict, chances: dict[int, float]) -> list[str]:
    """The opponent's starters, as they set them, who are carrying a flag."""
    out = []
    for entry in (team.get("roster") or {}).get("entries") or []:
        if entry.get("lineupSlotId") in (coach.BENCH, coach.IR):
            continue
        raw = (entry.get("playerPoolEntry") or {}).get("player") or {}
        name = raw.get("fullName") or "A player"
        chance = chances.get(raw.get("id"))
        status = (raw.get("injuryStatus") or "").upper()
        if chance is not None and chance < UNLIKELY_TO_PLAY:
            out.append(f"{name} ({round(chance * 100)}% likely to play)")
        elif status in FLAGGED:
            out.append(f"{name} (listed {status.replace('_', ' ').title()})")
    return out


def brief_for(report: dict, mine: str, theirs: str, injuries: list[str],
              pronouns: str) -> str:
    """The facts, in sentences, for Landry to phrase."""
    lines = [
        f"{mine} plays {theirs} this week. The manager of {theirs} uses {pronouns}.",
        f"If both set their best lineup, {mine} projects {report['mine']:.1f} "
        f"and {theirs} projects {report['theirs']:.1f}.",
    ]
    if report["strong"]:
        s = report["strong"]
        lines.append(
            f"{theirs} is strongest at {s['position']}, out-projecting {mine} "
            f"there by {s['gap']:.1f}" + (f", led by {s['theirs']}." if s["theirs"] else "."))
    if report["thin"]:
        t = report["thin"]
        lines.append(
            f"{theirs} is thinnest at {t['position']}, where {mine} is ahead by "
            f"{-t['gap']:.1f}" + (f" with {t['yours']}." if t["yours"] else "."))
    if injuries:
        lines.append(f"Starters {theirs} has in their lineup with an injury flag: "
                     + "; ".join(injuries) + ".")
    else:
        lines.append(f"None of {theirs}'s starters is carrying an injury flag.")
    if report["deciding"]:
        d = report["deciding"]
        lines.append(f"The position most likely to decide it is {d['position']}.")
    return "\n".join(lines)


def plain_for(report: dict, theirs: str, injuries: list[str]) -> str:
    """Sent verbatim when he cannot be reached."""
    text = (f"{theirs} projects {report['theirs']:.1f} to your "
            f"{report['mine']:.1f} if both lineups are set right.")
    if report["strong"]:
        text += f" They are strongest at {report['strong']['position']}."
    if report["thin"]:
        text += f" They are thinnest at {report['thin']['position']}."
    if injuries:
        text += " Flagged starters: " + "; ".join(injuries) + "."
    return text


def starting_slots(data: dict) -> list[int]:
    counts = ((data.get("settings") or {}).get("rosterSettings") or {}) \
        .get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in sorted((int(k), v) for k, v in counts.items()):
        if slot in (coach.BENCH, coach.IR):
            continue
        slots.extend([slot] * int(count))
    return slots


def main() -> int:
    for name in ("ESPN_LEAGUE_ID", "ESPN_S2", "SUPABASE_URL",
                 "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 1

    dry_run = bool(os.environ.get("DRY_RUN"))
    season = coach.current_season()
    league = os.environ["ESPN_LEAGUE_ID"]

    data = coach.espn(
        f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}",
        "view=mRoster&view=mTeam&view=mSettings&view=mMatchupScore")
    week = int(os.environ.get("SCOUT_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)
    slots = starting_slots(data)
    teams = {team["id"]: team for team in data.get("teams") or []}

    profiles = supabase("GET", "profiles?select=id,espn_swid,display_name") or []
    by_swid = {(p.get("espn_swid") or "").strip().upper(): p
               for p in profiles if p.get("espn_swid")}
    landry = next((p["id"] for p in profiles if p["display_name"] == "Landry"), None)
    if not landry:
        log("Landry has no profile; nothing to send from.")
        return 1

    chances = rounds.probabilities(season, week)
    pronouns = {
        row["espn_team_id"]: row["manager_pronouns"]
        for row in supabase(
            "GET",
            "team_bios?select=espn_team_id,manager_pronouns"
            f"&season=eq.{season}&manager_pronouns=not.is.null") or []
    }

    only = os.environ.get("SCOUT_ONLY", "").strip()
    if only:
        log(f"Restricted to managers matching '{only}'.")

    # Who already has this week's report. Read before anything is sent, since
    # the note is written after the message. A dry run ignores it: nothing is
    # sent, and hiding the preview because the real one went out would make
    # the preview useless for checking a change.
    already = set() if (dry_run or os.environ.get("SCOUT_RESEND")) else {
        (row["user_id"], row["subject"])
        for row in supabase(
            "GET",
            f"landry_notes?select=user_id,subject&kind=eq.scout"
            f"&season=eq.{season}&week=eq.{week}") or []
    }

    sent = 0
    for game in data.get("schedule") or []:
        if game.get("matchupPeriodId") != week:
            continue
        for here, there in (("home", "away"), ("away", "home")):
            # A bye has no away side, and nobody to scout.
            mine = teams.get((game.get(here) or {}).get("teamId"))
            theirs = teams.get((game.get(there) or {}).get("teamId"))
            if not mine or not theirs:
                continue
            owner = next((o for o in mine.get("owners") or []
                          if o.strip().upper() in by_swid), None)
            if not owner:
                continue
            profile = by_swid[owner.strip().upper()]
            if only and only.lower() not in profile["display_name"].lower():
                continue
            subject = str(theirs["id"])
            if (profile["id"], subject) in already:
                continue

            my_name = (mine.get("name") or "your team").strip()
            their_name = (theirs.get("name") or "their opponent").strip()
            report = scout(waivers.roster_players(mine, week),
                           waivers.roster_players(theirs, week), slots)
            injuries = injured_starters(theirs, chances)

            # Who is being written to, said plainly, for the same reason the
            # rounds say it: a brief that names two managers gets the wrong one
            # addressed.
            body = in_landrys_words(
                f"You are writing privately to {profile['display_name']}, who "
                f"manages {my_name}. Nobody else will see this message.\n\n"
                + brief_for(report, my_name, their_name, injuries,
                            pronouns.get(theirs["id"], "they/them")),
                "Write this as a scouting report on this week's opponent, sent "
                "privately to the manager named at the top. One short "
                "paragraph, five or six sentences: the projected totals, where "
                "the opponent is strong and where they are thin, any flagged "
                "starter, and the position most likely to decide it. If the "
                "projections are far apart, say so plainly. Speak to them "
                "directly, no greeting and no sign-off. " + IN_CHARACTER
                + " Do not invent any number or player you were not given.",
                plain_for(report, their_name, injuries),
                max_tokens=450,
            )

            if dry_run:
                log(f"  to {profile['display_name']} (vs {their_name}):")
                log(f"    {body}")
                sent += 1
                continue

            supabase("POST", "direct_messages", [{
                "sender_id": landry,
                "recipient_id": profile["id"],
                "body": body[:2000],
            }], prefer="return=minimal")
            # Ignoring a duplicate, as the post-mortem does: a deliberate resend
            # collides with the note from the first, and the message has gone
            # by now, so failing would turn a delivered report red.
            supabase(
                "POST",
                "landry_notes?on_conflict=user_id,kind,subject,season,week",
                [{
                    "user_id": profile["id"], "kind": "scout", "subject": subject,
                    "season": season, "week": week,
                }],
                prefer="return=minimal,resolution=ignore-duplicates")
            sent += 1

    log(f"Week {week}: {'would send' if dry_run else 'sent'} {sent} report(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
