#!/usr/bin/env python3
"""Writes the week's recap into league news, in the Cartel's voice.

Runs Tuesday mornings, after Monday night has settled. Computes the same
awards the apps compute — highest and lowest score, biggest blowout, closest
game — plus a power ranking, and posts one article.

Only completed fixtures count. A recap of a week still being played is wrong
by Tuesday lunchtime.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    RECAP_WEEK                   override the week
    DRY_RUN                      print the post instead of publishing

Usage:
    DRY_RUN=1 ./Scripts/post_recap.py
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


def completed(data: dict, week: int) -> list[dict]:
    out = []
    for game in data.get("schedule") or []:
        if game.get("matchupPeriodId") != week:
            continue
        if (game.get("winner") or "").upper() in ("", "UNDECIDED"):
            continue
        out.append(game)
    return out


def in_landrys_words(brief: str, fallback: str) -> str:
    """Asks the coach to write the recap from the week's facts.

    Every number in the brief was worked out here. He is asked to write it up,
    not to work anything out, which is the only arrangement in which he cannot
    be wrong about the score.
    """
    secret = os.environ.get("PUSH_SECRET")
    if not secret:
        return fallback
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/landry",
        data=json.dumps({
            "brief": brief,
            "instruction": (
                "Write this week's recap for the league news feed. Three or "
                "four short paragraphs. Name the highest and lowest scores and "
                "the biggest beating, and say something worth reading about "
                "each. No greeting, no sign-off, no headings. Stay in "
                "character throughout: the league is the outfit, managers are "
                "operators, and you are its football man. Do not invent a "
                "number you were not given."),
            "max_tokens": 700,
        }).encode(),
        method="POST",
        headers={"Content-Type": "application/json", "x-cartel-secret": secret},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            said = (json.load(response).get("text") or "").strip()
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as error:
        log(f"  coach unavailable ({error}); posting the plain recap")
        return fallback
    return said or fallback


def compose(week: int, games: list[dict], names: dict[int, str], teams: list[dict]) -> str:
    sides: list[tuple[int, float, bool]] = []
    for game in games:
        home, away = game.get("home") or {}, game.get("away") or {}
        hp = float(home.get("totalPoints") or 0)
        ap = float(away.get("totalPoints") or 0)
        if home.get("teamId") is not None:
            sides.append((home["teamId"], hp, hp > ap))
        if away.get("teamId") is not None:
            sides.append((away["teamId"], ap, ap > hp))

    def who(team_id: int) -> str:
        return names.get(team_id, f"Team {team_id}")

    best = max(sides, key=lambda s: s[1])
    worst = min(sides, key=lambda s: s[1])

    margins = []
    for game in games:
        home, away = game.get("home") or {}, game.get("away") or {}
        hp = float(home.get("totalPoints") or 0)
        ap = float(away.get("totalPoints") or 0)
        if home.get("teamId") is None or away.get("teamId") is None:
            continue
        winner = home["teamId"] if hp >= ap else away["teamId"]
        loser = away["teamId"] if hp >= ap else home["teamId"]
        margins.append((abs(hp - ap), winner, loser))

    lines = [f"Week {week} is in the books. Here is who did what to whom."]
    lines.append("")
    lines.append(f"HIGHEST SCORE — {who(best[0])}, {best[1]:.1f}. "
                 "Nobody else came close, and they will not let anyone forget it.")
    lines.append("")
    lines.append(f"LOWEST SCORE — {who(worst[0])}, {worst[1]:.1f}. "
                 "Somebody has to be down here. This week it was them.")

    if margins:
        blowout = max(margins, key=lambda m: m[0])
        closest = min(margins, key=lambda m: m[0])
        lines.append("")
        lines.append(f"BIGGEST BLOWOUT — {who(blowout[1])} beat {who(blowout[2])} "
                     f"by {blowout[0]:.1f}. That is not a fixture, that is a formality.")
        lines.append("")
        lines.append(f"CLOSEST GAME — {who(closest[1])} edged {who(closest[2])} "
                     f"by {closest[0]:.1f}. Somewhere a bench player is being blamed.")

    # Power ranking: record first, then points scored. Points are what a team
    # controls; record is what the schedule handed them.
    ranked = sorted(
        teams,
        key=lambda t: (
            -((t.get("record") or {}).get("overall") or {}).get("wins", 0),
            -((t.get("record") or {}).get("overall") or {}).get("pointsFor", 0.0),
        ),
    )
    lines.append("")
    lines.append("THE PECKING ORDER")
    for index, team in enumerate(ranked, start=1):
        overall = ((team.get("record") or {}).get("overall") or {})
        wins, losses = overall.get("wins", 0), overall.get("losses", 0)
        points = overall.get("pointsFor", 0.0)
        lines.append(f"{index}. {(team.get('name') or '').strip()} ({wins}-{losses}, {points:.1f})")

    lines.append("")
    lines.append("Nothing here is up for discussion.")
    lines.append("")
    lines.append("— The Commissioner")
    return "\n".join(lines)


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
    week = int(os.environ.get("RECAP_WEEK") or max(current - 1, 0))
    if week < 1:
        log("No completed week yet.")
        return 0

    games = completed(data, week)
    if not games:
        log(f"Week {week} has no completed fixtures.")
        return 0

    teams = data.get("teams") or []
    names = {t["id"]: (t.get("name") or f"Team {t['id']}").strip() for t in teams}
    title = f"Week {week} Recap"
    plain = compose(week, games, names, teams)
    # The facts, worked out here; the writing, his. If he is unreachable the
    # plain recap still goes out — a templated recap beats no recap.
    body = in_landrys_words(
        f"Week {week} of the Commissioner's Cartel is finished. The results:\n\n"
        + plain,
        plain,
    )

    if dry_run:
        log(f"DRY_RUN — would publish '{title}':")
        print(body)
        return 0

    base = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    # Skip if this week's recap is already up: the job may run twice and the
    # league does not need telling twice.
    check = urllib.request.Request(
        f"{base}/rest/v1/news_posts?select=id&season=eq.{season}"
        f"&title=eq.{urllib.parse.quote(title)}",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(check, timeout=30) as response:
        if json.load(response):
            log(f"'{title}' is already published.")
            return 0

    request = urllib.request.Request(
        f"{base}/rest/v1/news_posts",
        data=json.dumps([{
            "title": title,
            "body": body,
            "author_name": "The Commissioner",
            "season": season,
            "week": week,
        }]).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()
    log(f"Published '{title}'.")
    return 0


if __name__ == "__main__":
    import urllib.parse  # noqa: E402  (only needed in the write path)
    sys.exit(main())
