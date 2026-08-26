#!/usr/bin/env python3
"""Finds trades that would improve both teams, across the whole league.

Nobody proposes these because spotting one means holding two rosters in your
head at once. A computer can hold twelve.

Value is what a player adds to a team's best legal lineup, not what he
projects — a sixth running back adds nothing to a team with no slot for him,
which is exactly why lopsided-looking swaps can help both sides.

The arithmetic is this week's, because rest-of-season projections are not
served on our FantasyPros tier. Positional surplus tends to persist, so the
shape of these ideas holds up, but the numbers are a week's numbers: they are
offered as trades worth asking about, not as season-long valuations. Ask the
coach about one before sending it — he has the rest-of-season ranks.

Every pair of teams and every one-for-one swap is far too many exact solves to
run, so this does what the waiver coach does: a cheap marginal value for every
player first, which shortlists the pairs worth solving, and then an exact
re-solve of both lineups to confirm. Only confirmed pairs are stored.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  shared secret for the push function
    TRADE_WEEK                   override the week
    TRADE_MIN_GAIN               points each side must gain (default 1.5)
    DRY_RUN                      print instead of writing or notifying

Usage:
    DRY_RUN=1 ./Scripts/trade_finder.py
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import itertools
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
USER_AGENT = "curl/8.7.1"
BENCH_SLOTS = {20, 21}

# Both sides must gain at least this much for the idea to be worth anybody's
# time. Below it, the trade is noise and proposing it wastes goodwill.
DEFAULT_MIN_GAIN = 1.5

# How many candidate pairs to confirm exactly. The shortlist is ordered by the
# cheap estimate, so the real ones are at the top.
CONFIRM_LIMIT = 400

_spec = importlib.util.spec_from_file_location(
    "lineup_coach", pathlib.Path(__file__).with_name("lineup_coach.py"))
lineup_coach = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lineup_coach)


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


def push(kind: str, title: str, body: str, only_user: str) -> None:
    secret = os.environ.get("PUSH_SECRET")
    if not secret:
        return
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/push",
        data=json.dumps({"kind": kind, "title": title, "body": body,
                         "only_user": only_user}).encode(),
        method="POST",
        headers={"Content-Type": "application/json",
                 "x-push-secret": secret},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def consensus_points(season: int, week: int) -> dict[int, float]:
    rows = supabase(
        "GET",
        "fantasypros_projections?select=points_ppr,fantasypros_players!inner(espn_id)"
        f"&season=eq.{season}&week=eq.{week}&limit=2000",
    ) or []
    return {
        int((r.get("fantasypros_players") or {})["espn_id"]): float(r["points_ppr"])
        for r in rows
        if (r.get("fantasypros_players") or {}).get("espn_id") is not None
        and r.get("points_ppr") is not None
    }


def projection(player: dict, week: int) -> float:
    for row in player.get("stats") or []:
        if row.get("statSourceId") == 1 and row.get("scoringPeriodId") == week:
            return float(row.get("appliedTotal") or 0)
    return 0.0


def starting_slots(data: dict) -> list[int]:
    counts = ((data.get("settings") or {}).get("rosterSettings") or {}) \
        .get("lineupSlotCounts") or {}
    slots: list[int] = []
    for slot, count in counts.items():
        if int(slot) in BENCH_SLOTS:
            continue
        slots.extend([int(slot)] * int(count))
    return slots


def roster_of(team: dict, week: int, consensus: dict[int, float]) -> list[dict]:
    players = []
    for entry in (team.get("roster") or {}).get("entries") or []:
        raw = (entry.get("playerPoolEntry") or {}).get("player") or {}
        if raw.get("id") is None:
            continue
        players.append({
            "id": raw["id"],
            "name": raw.get("fullName") or "A player",
            "points": consensus.get(raw["id"], projection(raw, week)),
            "eligible": set(raw.get("eligibleSlots") or []),
        })
    return players


def strength(players: list[dict], slots: list[int]) -> float:
    total, _ = lineup_coach.best_lineup(players, slots)
    return total


def starter_points(players: list[dict], slots: list[int]) -> dict[int, float]:
    """What each starting slot is currently worth, so the gain from adding
    somebody can be estimated without solving the lineup again."""
    _, picks = lineup_coach.best_lineup(players, slots)
    out: dict[int, float] = {}
    for index, slot in enumerate(slots):
        chosen = picks.get(index, -1)
        points = players[chosen]["points"] if chosen >= 0 else 0.0
        # Two RB slots: the one worth displacing is the weaker.
        out[slot] = min(out.get(slot, points), points)
    return out


def gain_estimate(player: dict, starters: dict[int, float]) -> float:
    """An upper bound on what adding a player would add: the most he could
    displace at any slot he is eligible for. Never optimistic, and cheap."""
    best = 0.0
    for slot in player["eligible"]:
        if slot in starters:
            best = max(best, player["points"] - starters[slot])
    return best


def marginal(players: list[dict], slots: list[int],
             base: float) -> dict[int, float]:
    """What losing each player would cost this team.

    A starter with a good replacement behind him costs little; a starter with
    nobody behind him costs everything he projects.
    """
    out = {}
    for player in players:
        without = [p for p in players if p["id"] != player["id"]]
        out[player["id"]] = base - strength(without, slots)
    return out


def main() -> int:
    for name in ("ESPN_LEAGUE_ID", "ESPN_S2", "SUPABASE_URL",
                 "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 1

    dry_run = bool(os.environ.get("DRY_RUN"))
    min_gain = float(os.environ.get("TRADE_MIN_GAIN") or DEFAULT_MIN_GAIN)
    season = current_season()

    data = espn(
        f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/"
        f"{os.environ['ESPN_LEAGUE_ID']}",
        "view=mRoster&view=mTeam&view=mSettings")
    week = int(os.environ.get("TRADE_WEEK")
               or (data.get("status") or {}).get("currentMatchupPeriod") or 1)

    slots = starting_slots(data)
    consensus = consensus_points(season, week)
    teams = data.get("teams") or []
    log(f"Week {week}; {len(teams)} teams, {len(consensus)} consensus projections")

    squads, base, costs, starters = {}, {}, {}, {}
    for team in teams:
        squad = roster_of(team, week, consensus)
        squads[team["id"]] = squad
        base[team["id"]] = strength(squad, slots)
        costs[team["id"]] = marginal(squad, slots, base[team["id"]])
        starters[team["id"]] = starter_points(squad, slots)

    if sum(1 for v in base.values() if v > 0) < len(teams) / 2:
        log("Projections for this week are not out yet. Nothing to suggest.")
        return 0

    names = {t["id"]: (t.get("name") or f"Team {t['id']}").strip() for t in teams}

    # The estimate: a swap helps me if what I gain from their player exceeds
    # what losing mine costs. Losing is exact. Gaining is bounded above by the
    # most the incoming player could displace at a slot he is eligible for —
    # bounding it by his raw projection instead put thirteen thousand swaps on
    # the shortlist and confirmed none of them, because a big projection at a
    # position you are already strong at is worth nothing.
    shortlist = []
    for a, b in itertools.combinations(squads, 2):
        for mine in squads[a]:
            for theirs in squads[b]:
                a_est = gain_estimate(theirs, starters[a]) - costs[a][mine["id"]]
                b_est = gain_estimate(mine, starters[b]) - costs[b][theirs["id"]]
                if a_est > min_gain and b_est > min_gain:
                    shortlist.append((min(a_est, b_est), a, b, mine, theirs))

    shortlist.sort(key=lambda row: -row[0])
    log(f"  {len(shortlist)} candidate swaps; confirming the best "
        f"{min(len(shortlist), CONFIRM_LIMIT)} exactly")

    ideas = []
    for _, a, b, mine, theirs in shortlist[:CONFIRM_LIMIT]:
        a_after = strength(
            [p for p in squads[a] if p["id"] != mine["id"]] + [theirs], slots)
        b_after = strength(
            [p for p in squads[b] if p["id"] != theirs["id"]] + [mine], slots)
        a_gain = a_after - base[a]
        b_gain = b_after - base[b]
        if a_gain <= min_gain or b_gain <= min_gain:
            continue
        ideas.append({
            "season": season, "week": week,
            "team_a": a, "team_a_name": names[a],
            "team_b": b, "team_b_name": names[b],
            "a_sends": mine["name"], "b_sends": theirs["name"],
            "a_gain": round(a_gain, 1), "b_gain": round(b_gain, 1),
        })

    # One idea per pair of teams: the best one. Twelve variations on the same
    # trade is a wall of noise, not twelve opportunities.
    best_per_pair: dict[tuple[int, int], dict] = {}
    for idea in sorted(ideas, key=lambda i: -(i["a_gain"] + i["b_gain"])):
        key = (idea["team_a"], idea["team_b"])
        best_per_pair.setdefault(key, idea)
    ideas = list(best_per_pair.values())

    log(f"  {len(ideas)} trade(s) improve both sides by more than {min_gain}")

    if dry_run:
        for idea in ideas:
            log(f"  {idea['team_a_name']} sends {idea['a_sends']} "
                f"(+{idea['a_gain']}) for {idea['team_b_name']}'s "
                f"{idea['b_sends']} (+{idea['b_gain']})")
        return 0

    if not ideas:
        return 0

    supabase("POST",
             "trade_ideas?on_conflict=season,week,team_a,team_b,a_sends,b_sends",
             ideas, prefer="resolution=merge-duplicates,return=minimal")

    # Storing and notifying are separate acts. Landry's rounds read these
    # ideas and mention them privately, so there are times to record what was
    # found without also interrupting anybody about it.
    if os.environ.get("TRADE_NOTIFY") == "0":
        log(f"Stored {len(ideas)} trade idea(s); notifying nobody.")
        return 0

    # Tell each manager about ideas involving their own roster, and only those.
    profiles = supabase("GET", "profiles?select=id,espn_swid") or []
    by_swid = {(p.get("espn_swid") or "").strip(): p["id"]
               for p in profiles if p.get("espn_swid")}
    owner_of = {}
    for team in teams:
        owner = next((o for o in team.get("owners") or [] if o in by_swid), None)
        if owner:
            owner_of[team["id"]] = by_swid[owner]

    # One notification each, however many ideas involve their roster. A team
    # with a surplus at one position turns up in several pairs, and three
    # notifications on a Wednesday morning is nagging rather than help.
    for_manager: dict[str, tuple[float, str, str]] = {}
    for idea in ideas:
        for side, other, sends, gets, gain in (
            ("team_a", "team_b_name", "a_sends", "b_sends", "a_gain"),
            ("team_b", "team_a_name", "b_sends", "a_sends", "b_gain"),
        ):
            user = owner_of.get(idea[side])
            if not user:
                continue
            # Who sends what, spelled out. "X might take A for B" reads as a
            # riddle at a glance, which is all a notification gets.
            body = (f"Offer {idea[sends]} to {idea[other]} for {idea[gets]}. "
                    f"It would add {idea[gain]} to your lineup this week, and "
                    "improve theirs too.")
            best = for_manager.get(user)
            if best is None or idea[gain] > best[0]:
                for_manager[user] = (idea[gain], "A trade worth asking about", body)

    for user, (_, title, body) in for_manager.items():
        try:
            push("trade", title, body, user)
        except urllib.error.HTTPError as error:
            log(f"  push failed: {error.code}")
    log(f"  notified {len(for_manager)} manager(s)")

    log(f"Stored {len(ideas)} trade idea(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
