#!/usr/bin/env python3
"""Pull player news blurbs from The Fantasy Footballers into Supabase.

Their news page renders server-side and carries everything needed in a single
document: player, position, team, headshot, timestamp, headline and the short
blurb. One request a day covers it — no per-article fetching.

Stores the short factual blurb only. The extended analysis paragraph on each
item is deliberately skipped, and every row keeps its source URL so the app can
link back.

Environment:
    SUPABASE_URL                 https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY    service role key; bypasses RLS, server-side only
    NEWS_MAX_AGE_HOURS           optional, default 24
    NEWS_PRUNE_DAYS              optional, default 14
    DRY_RUN                      set to any value to skip writing

Usage:
    DRY_RUN=1 ./Scripts/ingest_news.py
"""

from __future__ import annotations

import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

SOURCE_NAME = "The Fantasy Footballers"
NEWS_URL = "https://www.thefantasyfootballers.com/fantasy-football-news/"

# Identify honestly rather than pretending to be a browser.
USER_AGENT = (
    "CommissionersCartelBot/0.1 "
    "(+https://github.com/mykool223/CommissonersCartelFFL; league app, once daily)"
)

ARTICLE_RE = re.compile(r"<article[^>]*>(.*?)</article>", re.S)
TIME_RE = re.compile(r'<time[^>]*datetime="([^"]+)"', re.S)
LINK_RE = re.compile(r'href="(https://www\.thefantasyfootballers\.com/news/(\d+)/[^"]*)"')
PLAYER_RE = re.compile(r'ffb-news--grid--player--info.*?<h3[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</h3>', re.S)
POSITION_RE = re.compile(r'<span class="pos[^"]*">(.*?)</span>', re.S)
TEAM_RE = re.compile(r'<span class="team">(.*?)</span>', re.S)
HEADLINE_RE = re.compile(r'ffb-news--grid--article.*?<h2[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</h2>', re.S)
# The blurb is the bolded lead paragraph. The <p class="expand"> that follows is
# their own analysis and is left alone on purpose.
BLURB_RE = re.compile(r"<p><strong>(.*?)</strong></p>", re.S)
# Lazy-loading swaps the real image into data-src, so prefer that.
HEADSHOT_RE = re.compile(r'data-src="(https://[^"]+/headshots/[^"]+)"')
TAG_RE = re.compile(r"<[^>]+>")
WHITESPACE_RE = re.compile(r"\s+")


def log(message: str) -> None:
    print(message, flush=True)


def clean(raw: str | None, limit: int | None = None) -> str | None:
    if not raw:
        return None
    text = html.unescape(WHITESPACE_RE.sub(" ", TAG_RE.sub("", raw))).strip()
    if not text:
        return None
    if limit and len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0] + "…"
    return text


def first(pattern: re.Pattern[str], block: str, group: int = 1) -> str | None:
    match = pattern.search(block)
    return match.group(group) if match else None


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8", errors="replace")


def parse(document: str, max_age_hours: int) -> list[dict]:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=max_age_hours)
    rows: dict[int, dict] = {}
    too_old = 0
    incomplete = 0

    for block in ARTICLE_RE.findall(document):
        link_match = LINK_RE.search(block)
        published_raw = first(TIME_RE, block)
        # The mega-menu repeats a few items in a stripped-down form with no
        # timestamp. Those are skipped rather than stored undated.
        if not link_match or not published_raw:
            incomplete += 1
            continue

        try:
            published = datetime.fromisoformat(published_raw.replace("Z", "+00:00"))
        except ValueError:
            incomplete += 1
            continue
        if published.tzinfo is None:
            published = published.replace(tzinfo=timezone.utc)
        if published < cutoff:
            too_old += 1
            continue

        headline = clean(first(HEADLINE_RE, block), 300)
        player = clean(first(PLAYER_RE, block), 120)
        if not headline or not player:
            incomplete += 1
            continue

        source_id = int(link_match.group(2))
        # Keyed by id, so the duplicate menu copies collapse rather than
        # fighting each other in the upsert.
        rows[source_id] = {
            "source_id": source_id,
            "source_name": SOURCE_NAME,
            "player_name": player,
            "player_position": clean(first(POSITION_RE, block), 8),
            "player_team": clean(first(TEAM_RE, block), 8),
            "headshot_url": first(HEADSHOT_RE, block),
            "headline": headline,
            "blurb": clean(first(BLURB_RE, block), 600),
            "url": link_match.group(1),
            "published_at": published.astimezone(timezone.utc).isoformat(),
        }

    log(f"  {len(rows)} within {max_age_hours}h, {too_old} older, {incomplete} skipped")
    return sorted(rows.values(), key=lambda r: r["published_at"], reverse=True)


def supabase_request(method: str, path: str, base: str, key: str,
                     body: bytes | None = None, prefer: str | None = None) -> tuple[int, bytes]:
    request = urllib.request.Request(f"{base}{path}", method=method, data=body)
    request.add_header("apikey", key)
    request.add_header("Authorization", f"Bearer {key}")
    request.add_header("Content-Type", "application/json")
    if prefer:
        request.add_header("Prefer", prefer)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def main() -> int:
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    max_age = int(os.environ.get("NEWS_MAX_AGE_HOURS", "24"))
    prune_days = int(os.environ.get("NEWS_PRUNE_DAYS", "14"))
    dry_run = bool(os.environ.get("DRY_RUN"))

    if not dry_run and (not base or not key):
        log("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required (or set DRY_RUN).")
        return 1

    log(f"Fetching {NEWS_URL}")
    try:
        document = fetch(NEWS_URL)
    except (urllib.error.URLError, TimeoutError) as error:
        log(f"Could not fetch the news page: {error}")
        return 1

    rows = parse(document, max_age)
    if not rows:
        # A quiet news day is normal; failing here would cry wolf.
        log("Nothing new to store.")
        return 0

    if dry_run:
        log(f"DRY_RUN — would upsert {len(rows)} row(s):")
        for row in rows[:12]:
            who = f"{row['player_name']} ({row['player_position'] or '?'}, {row['player_team'] or '?'})"
            log(f"  {row['published_at'][11:16]}  {who}")
            log(f"          {row['headline']}")
            if row["blurb"]:
                log(f"          {row['blurb'][:100]}...")
        if len(rows) > 12:
            log(f"  ... and {len(rows) - 12} more")
        return 0

    status, body = supabase_request(
        "POST", "/rest/v1/player_news?on_conflict=source_id", base, key,
        body=json.dumps(rows).encode(),
        prefer="resolution=merge-duplicates,return=minimal",
    )
    if status >= 300:
        log(f"Upsert failed: HTTP {status} {body[:300].decode(errors='replace')}")
        return 1
    log(f"Upserted {len(rows)} row(s).")

    cutoff = (datetime.now(timezone.utc) - timedelta(days=prune_days)).isoformat()
    # The "+" in a "+00:00" offset decodes to a space in a query string, which
    # Postgres then rejects as an invalid timestamp. Encode it.
    status, body = supabase_request(
        "DELETE",
        f"/rest/v1/player_news?published_at=lt.{urllib.parse.quote(cutoff, safe='')}",
        base, key, prefer="return=minimal",
    )
    if status >= 300:
        log(f"Prune failed (non-fatal): HTTP {status} {body[:200].decode(errors='replace')}")
    else:
        log(f"Pruned anything published before {cutoff}.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
