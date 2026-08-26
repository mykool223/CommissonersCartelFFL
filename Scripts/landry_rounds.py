#!/usr/bin/env python3
"""Landry does his rounds: one message to each manager who needs one.

He looks at every claimed team and works out the single most useful thing he
could say — a free agent worth signing, a trade worth proposing, a starter who
may not play — and sends it as a direct message rather than a notification. A
notification is gone the moment it is dismissed; a message is still there on
Thursday when somebody wants to check what he actually said.

Deliberately one message per manager per run. He could send four; a coach who
sends four messages is a coach nobody reads.

The arithmetic is all done here — what a signing would add, what a trade would
do to both lineups — and he is asked only to phrase it. Every player named is
one that was passed to him.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  for his voice, and the DM push
    ROUNDS_WEEK                  override the week
    ROUNDS_MIN_GAIN              points a signing must add (default 1.5)
    DRY_RUN                      print instead of sending

Usage:
    DRY_RUN=1 ./Scripts/landry_rounds.py
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

_spec = importlib.util.spec_from_file_location(
    "waiver_coach", pathlib.Path(__file__).with_name("waiver_coach.py"))
waivers = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(waivers)
coach = waivers.coach  # the lineup solver, imported by the waiver coach

# Said in every instruction, so one job cannot quietly drift into a
# different coach from the others.
IN_CHARACTER = (
    "Stay in character throughout: you run football operations for a cartel and you talk like it — calm, clipped, faintly menacing, never chatty and never apologetic. The league is the outfit, managers are operators, the waiver wire is the street."
)

DEFAULT_MIN_GAIN = 1.5

# Below this, a starter is worth a message even without a blocking status.
UNLIKELY_TO_PLAY = 0.5


def log(message: str) -> None:
    print(message, file=sys.stderr)


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
        method=method, headers=headers,
        data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def in_landrys_words(brief: str, instruction: str, fallback: str) -> str:
    secret = os.environ.get("PUSH_SECRET")
    if not secret:
        return fallback
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/landry",
        data=json.dumps({"brief": brief, "instruction": instruction,
                         "max_tokens": 320}).encode(),
        method="POST",
        headers={"Content-Type": "application/json", "x-cartel-secret": secret})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            said = (json.load(response).get("text") or "").strip()
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as error:
        log(f"  coach unavailable ({error}); sending the plain version")
        return fallback
    return said or fallback


def probabilities(season: int, week: int) -> dict[int, float]:
    rows = supabase(
        "GET",
        "fantasypros_injuries?select=probability,fantasypros_players!inner(espn_id)"
        f"&season=eq.{season}&week=eq.{week}&probability=not.is.null") or []
    out = {}
    for row in rows:
        espn_id = (row.get("fantasypros_players") or {}).get("espn_id")
        if espn_id is not None and row.get("probability") is not None:
            out[int(espn_id)] = float(row["probability"])
    return out


def main() -> int:
    for name in ("ESPN_LEAGUE_ID", "ESPN_S2", "SUPABASE_URL",
                 "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 1

    dry_run = bool(os.environ.get("DRY_RUN"))
    min_gain = float(os.environ.get("ROUNDS_MIN_GAIN") or DEFAULT_MIN_GAIN)
    season = coach.current_season()
    league = os.environ["ESPN_LEAGUE_ID"]

    data = coach.espn(
        f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league}",
        "view=mRoster&view=mTeam&view=mSettings")
    week = int(os.environ.get("ROUNDS_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    counts = ((data.get("settings") or {}).get("rosterSettings") or {}) \
        .get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in sorted((int(k), v) for k, v in counts.items()):
        if slot in (coach.BENCH, coach.IR):
            continue
        slots.extend([slot] * int(count))

    profiles = supabase("GET", "profiles?select=id,espn_swid,display_name") or []
    by_swid = {(p.get("espn_swid") or "").strip().upper(): p
               for p in profiles if p.get("espn_swid")}
    landry = next((p["id"] for p in profiles if p["display_name"] == "Landry"), None)
    if not landry:
        log("Landry has no profile; nothing to send from.")
        return 1

    pool = []
    for entry in waivers.free_agents(season, league):
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

    chances = probabilities(season, week)
    ideas = supabase(
        "GET", f"trade_ideas?select=*&season=eq.{season}&week=eq.{week}") or []

    # Pronouns, by ESPN team id. Anybody not listed is they and them — the
    # league has one woman in it and a coach guessing from names gets her
    # wrong every time.
    pronouns = {
        row["espn_team_id"]: row["manager_pronouns"]
        for row in supabase(
            "GET",
            "team_bios?select=espn_team_id,manager_pronouns"
            f"&season=eq.{season}&manager_pronouns=not.is.null") or []
    }
    already = {
        (row["user_id"], row["kind"], row["subject"])
        for row in supabase(
            "GET",
            f"landry_notes?select=user_id,kind,subject&season=eq.{season}&week=eq.{week}") or []
    }

    log(f"Week {week}; {len(pool)} free agent(s), {len(ideas)} trade idea(s)")
    sent = 0

    for team in data.get("teams") or []:
        owner = next((o for o in team.get("owners") or []
                      if o.strip().upper() in by_swid), None)
        if not owner:
            continue
        profile = by_swid[owner.strip().upper()]
        team_name = (team.get("name") or "your team").strip()
        players = waivers.roster_players(team, week)
        before, _ = coach.best_lineup(players, slots)

        # Everything he could say, most valuable first. He says one of them.
        options: list[tuple[float, str, str, str, str]] = []

        # A starter who may not play. Ranked highest: it expires at kickoff.
        for entry in (team.get("roster") or {}).get("entries") or []:
            if entry.get("lineupSlotId") in (coach.BENCH, coach.IR):
                continue
            raw = (entry.get("playerPoolEntry") or {}).get("player") or {}
            chance = chances.get(raw.get("id"))
            status = (raw.get("injuryStatus") or "").upper()
            if chance is not None and chance < UNLIKELY_TO_PLAY:
                options.append((
                    100.0, "injury", raw.get("fullName") or "A player",
                    f"{team_name} is starting {raw.get('fullName')}, who is "
                    f"{round(chance * 100)}% likely to play this week.",
                    f"{raw.get('fullName')} is only {round(chance * 100)}% "
                    "likely to play and is in your starting lineup.",
                ))
            elif status in ("OUT", "DOUBTFUL", "INJURY_RESERVE", "SUSPENSION"):
                options.append((
                    100.0, "injury", raw.get("fullName") or "A player",
                    f"{team_name} is starting {raw.get('fullName')}, who is "
                    f"listed {status.title()}.",
                    f"{raw.get('fullName')} is {status.lower()} and is in "
                    "your starting lineup.",
                ))

        # The best free agent, measured by what he adds to the best lineup.
        weakest = min((p["points"] for p in players
                       if p.get("slot") not in (coach.BENCH, coach.IR)), default=0)
        best_add = None
        for candidate in pool:
            if waivers.upper_bound(candidate, weakest) <= min_gain:
                continue
            gain = waivers.value_added(players, candidate, slots, before)
            if gain > min_gain and (best_add is None or gain > best_add[0]):
                best_add = (gain, candidate)
        if best_add:
            gain, candidate = best_add
            droppable = sorted(
                (p for p in players if p.get("slot") in (coach.BENCH,)),
                key=lambda p: p["points"])
            drop = droppable[0]["name"] if droppable else "somebody"
            options.append((
                gain, "waiver", candidate["name"],
                f"{team_name} could sign {candidate['name']}, a free agent "
                f"projecting {candidate['points']:.1f} and owned in "
                f"{candidate['owned']}% of leagues. It would add "
                f"{gain:.1f} points to their best lineup. The lowest "
                f"projected player on their bench is {drop}.",
                f"{candidate['name']} is free and would add {gain:.1f} points "
                f"to your lineup. {drop} is your lowest bench piece.",
            ))

        # A trade the finder already confirmed improves both sides.
        for idea in ideas:
            mine = idea["team_a"] == team["id"]
            if not mine and idea["team_b"] != team["id"]:
                continue
            other = idea["team_b_name"] if mine else idea["team_a_name"]
            send = idea["a_sends"] if mine else idea["b_sends"]
            get = idea["b_sends"] if mine else idea["a_sends"]
            gain = float(idea["a_gain"] if mine else idea["b_gain"])
            other_id = idea["team_b"] if mine else idea["team_a"]
            says = pronouns.get(other_id, "they/them")
            options.append((
                gain, "trade", f"{other}:{send}",
                f"{team_name} could offer {send} to {other} for {get}. It "
                f"would add {gain:.1f} points to their lineup and improve "
                f"{other}'s as well, which is why it is worth asking. The "
                f"manager of {other} uses {says}.",
                f"Offer {send} to {other} for {get} — it would add "
                f"{gain:.1f} to your lineup and help theirs too.",
            ))

        options = [o for o in options
                   if (profile["id"], o[1], o[2]) not in already]
        if not options:
            continue
        options.sort(key=lambda o: -o[0])
        _, kind, subject, brief, plain = options[0]

        # Say plainly who is being written to. Without this the brief named
        # two managers — the recipient and the counterparty — and he addressed
        # the wrong one, telling Danny to think it over, Devon.
        body = in_landrys_words(
            f"You are writing privately to {profile['display_name']}, who "
            f"manages {team_name}. Nobody else will see this message.\n\n"
            + brief,
            "Write this as a short private message to that manager — the "
            "one named at the top, not anybody else mentioned. Two or three "
            "sentences. Speak to them directly, no greeting and no sign-off. "
            + IN_CHARACTER + "Do not invent any number you were not given.",
            plain,
        )

        if dry_run:
            log(f"  to {profile['display_name']} ({kind}):")
            log(f"    {body}")
            sent += 1
            continue

        supabase("POST", "direct_messages", [{
            "sender_id": landry,
            "recipient_id": profile["id"],
            "body": body[:2000],
        }], prefer="return=minimal")
        supabase("POST", "landry_notes", [{
            "user_id": profile["id"], "kind": kind, "subject": subject,
            "season": season, "week": week,
        }], prefer="return=minimal")
        sent += 1

    log(f"{'Would send' if dry_run else 'Sent'} {sent} message(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
