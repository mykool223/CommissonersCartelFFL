#!/usr/bin/env python3
"""Tells a manager when news breaks about a player on their own roster.

The lineup guard warns about a starter who cannot play, but only on Sunday
morning and only once they are already in the lineup. A practice report on
Wednesday, or a season-ending knee on a Tuesday night, reached nobody.

Matching is on name, which is the only thing the news feed and ESPN share.
Names are normalised the same way the FantasyPros join does — punctuation and
suffixes disagree constantly — and anything that does not match is skipped
rather than guessed at.

Environment:
    ESPN_S2, ESPN_SWID, ESPN_LEAGUE_ID
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    PUSH_SECRET                  shared secret for the push function
    ROSTER_NEWS_MAX_AGE_HOURS    only consider news newer than this (default 3)
    ROSTER_NEWS_PER_RUN          most alerts per manager per run (default 3)
    DRY_RUN                      print instead of pushing

Usage:
    DRY_RUN=1 ./Scripts/roster_news.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ESPN_HOST = "https://lm-api-reads.fantasy.espn.com"
USER_AGENT = "curl/8.7.1"

DEFAULT_MAX_AGE_HOURS = 3

# A burst of six alerts in one minute gets an app muted. Beyond this, the app
# itself is the better place to read the rest.
DEFAULT_PER_RUN = 3

SUFFIXES = (" jr", " sr", " ii", " iii", " iv", " v")


def log(message: str) -> None:
    print(message, file=sys.stderr)


def current_season(today: dt.date | None = None) -> int:
    today = today or dt.date.today()
    return today.year if today.month >= 6 else today.year - 1


def normalise(name: str) -> str:
    """Matches the join used for FantasyPros: punctuation and suffixes differ
    between sources far more often than the names themselves do."""
    text = name.lower().replace(".", "").replace("'", "").replace("’", "")
    text = text.replace("-", " ")
    for suffix in SUFFIXES:
        if text.endswith(suffix):
            text = text[: -len(suffix)]
    return " ".join(text.split())


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
    secret = os.environ["PUSH_SECRET"]
    request = urllib.request.Request(
        f"{os.environ['SUPABASE_URL'].rstrip('/')}/functions/v1/push",
        data=json.dumps({"kind": kind, "title": title, "body": body,
                         "only_user": only_user}).encode(),
        method="POST",
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {secret}"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main() -> int:
    for name in ("ESPN_LEAGUE_ID", "ESPN_S2", "SUPABASE_URL",
                 "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 1

    dry_run = bool(os.environ.get("DRY_RUN"))
    max_age = int(os.environ.get("ROSTER_NEWS_MAX_AGE_HOURS") or DEFAULT_MAX_AGE_HOURS)
    per_run = int(os.environ.get("ROSTER_NEWS_PER_RUN") or DEFAULT_PER_RUN)
    season = current_season()

    since = (dt.datetime.now(dt.timezone.utc)
             - dt.timedelta(hours=max_age)).isoformat()
    stories = supabase(
        "GET",
        f"player_news?select=id,player_name,headline,blurb,published_at"
        f"&published_at=gte.{urllib.parse.quote(since)}"
        "&order=published_at.desc&limit=200",
    ) or []
    if not stories:
        log(f"No player news in the last {max_age} hour(s).")
        return 0

    # Only members who have said which team is theirs can be told about it.
    profiles = supabase("GET", "profiles?select=id,espn_swid,display_name") or []
    by_swid = {(p.get("espn_swid") or "").strip().upper(): p
               for p in profiles if p.get("espn_swid")}
    if not by_swid:
        log("Nobody has claimed a team. Nothing to send.")
        return 0

    league = espn(
        f"/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/"
        f"{os.environ['ESPN_LEAGUE_ID']}", "view=mRoster&view=mTeam")

    # Who owns whom, by normalised name.
    owner_of: dict[str, dict] = {}
    for team in league.get("teams") or []:
        owner = next((o for o in team.get("owners") or []
                      if o.strip().upper() in by_swid), None)
        if not owner:
            continue
        profile = by_swid[owner.strip().upper()]
        for entry in (team.get("roster") or {}).get("entries") or []:
            player = (entry.get("playerPoolEntry") or {}).get("player") or {}
            name = player.get("fullName")
            if name:
                owner_of[normalise(name)] = profile

    log(f"{len(stories)} story(ies) in the last {max_age}h; "
        f"{len(owner_of)} rostered player(s) belong to a member")

    # Already-sent, so a re-run does not tell somebody twice about a knee.
    sent = supabase("GET", "roster_news_alerts?select=user_id,news_id") or []
    already = {(row["user_id"], row["news_id"]) for row in sent}

    queued: dict[str, list[dict]] = {}
    for story in stories:
        profile = owner_of.get(normalise(story["player_name"]))
        if not profile:
            continue
        if (profile["id"], story["id"]) in already:
            continue
        queued.setdefault(profile["id"], []).append(story)

    if not queued:
        log("Nothing new about anybody's roster.")
        return 0

    for user_id, items in queued.items():
        name = next((p["display_name"] for p in profiles if p["id"] == user_id), "somebody")
        dropped = max(0, len(items) - per_run)
        for story in items[:per_run]:
            title = f"{story['player_name']}: {story['headline']}"
            body = (story.get("blurb") or "").strip() or "Tap for the details."
            if dry_run:
                log(f"  → {name}: {title}")
                continue
            try:
                push("roster", title, body[:180], user_id)
            except urllib.error.HTTPError as error:
                log(f"  push failed for {name}: {error.code} {error.read()[:120]}")
                continue
            supabase("POST", "roster_news_alerts",
                     [{"user_id": user_id, "news_id": story["id"]}],
                     prefer="return=minimal")
        if dropped:
            log(f"  {name}: {dropped} further story(ies) not sent this run")

    log("Done." if not dry_run else "DRY_RUN — nothing sent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
