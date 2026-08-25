#!/usr/bin/env python3
"""Pulls FantasyPros articles from their public RSS feed.

Their API has no articles endpoint — only single-player news, which is the
same material the Fantasy Footballers feed already provides. The articles that
are actually worth reading, the sleepers and start/sit and draft advice pieces,
are published as RSS, which exists to be read this way.

Costs nothing against the API allowance: RSS is not the API.

The title, author and excerpt are stored; the app links out for the piece
itself. Somebody else's writing belongs on their site.

Environment:
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    FP_ARTICLES_PRUNE_DAYS       drop items older than this (default 30)
    DRY_RUN                      print instead of writing

Usage:
    DRY_RUN=1 ./Scripts/sync_fantasypros_articles.py
"""

from __future__ import annotations

import datetime as dt
import email.utils
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

FEED_URL = "https://www.fantasypros.com/feed/"

# Honest about who we are, as the news ingest is.
USER_AGENT = "commissioners-cartel/1.0 (league app; contact via GitHub)"

DEFAULT_PRUNE_DAYS = 30

TAG = re.compile(r"<[^>]+>")


def log(message: str) -> None:
    print(message, file=sys.stderr)


def field(block: str, tag: str) -> str | None:
    match = re.search(
        rf"<{tag}>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</{tag}>", block, re.S)
    return html.unescape(match.group(1)).strip() if match else None


def plain(text: str | None) -> str | None:
    """Their excerpt is HTML and ends in a run of navigation links."""
    if not text:
        return None
    stripped = " ".join(TAG.sub(" ", text).split())
    # Everything from the boilerplate trailer onwards is site navigation, not
    # part of the article.
    for marker in ("Fantasy Football Research & Advice",
                   "Fantasy Football Expert Rankings"):
        index = stripped.find(marker)
        if index > 0:
            stripped = stripped[:index]
    stripped = stripped.strip()
    return stripped or None


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
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def main() -> int:
    for name in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 2

    dry_run = bool(os.environ.get("DRY_RUN"))
    prune_days = int(os.environ.get("FP_ARTICLES_PRUNE_DAYS") or DEFAULT_PRUNE_DAYS)

    request = urllib.request.Request(FEED_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        feed = response.read().decode("utf-8", "replace")

    rows = []
    for block in re.findall(r"<item>(.*?)</item>", feed, re.S):
        title, link = field(block, "title"), field(block, "link")
        guid = field(block, "guid") or link
        published = field(block, "pubDate")
        if not (title and link and guid and published):
            continue
        try:
            when = email.utils.parsedate_to_datetime(published)
        except (TypeError, ValueError):
            continue
        categories = [html.unescape(c) for c in
                      re.findall(r"<category>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</category>",
                                 block, re.S)]
        rows.append({
            "guid": guid,
            "title": title,
            "excerpt": plain(field(block, "description")),
            "link": link,
            "author": field(block, "dc:creator"),
            # "Featured Link" and friends are site furniture, not subjects.
            "categories": [c for c in categories
                           if c not in ("Featured", "Featured Link", "Articles", "Discover")],
            "published_at": when.astimezone(dt.timezone.utc).isoformat(),
        })

    log(f"{len(rows)} article(s) in the feed")
    if dry_run:
        for row in rows[:5]:
            log(f"  {row['published_at'][:16]}  {row['title'][:66]}")
        return 0

    if rows:
        supabase("POST", "fantasypros_articles?on_conflict=guid", rows,
                 prefer="resolution=merge-duplicates,return=minimal")
    log(f"Stored {len(rows)}.")

    cutoff = (dt.datetime.now(dt.timezone.utc)
              - dt.timedelta(days=prune_days)).isoformat()
    supabase("DELETE",
             f"fantasypros_articles?published_at=lt.{urllib.parse.quote(cutoff)}",
             prefer="return=minimal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
