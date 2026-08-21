#!/usr/bin/env python3
"""Pull recent articles from publisher RSS feeds into Supabase.

Stores only the reference — headline, excerpt, link — never the article text.
The app links out to the publisher.

Environment:
    SUPABASE_URL                 https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY    service role key; bypasses RLS, server-side only
    NEWS_MAX_AGE_HOURS           optional, default 24
    NEWS_PRUNE_DAYS              optional, default 14
    DRY_RUN                      set to any value to skip writing

Usage:
    ./Scripts/ingest_news.py
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

# Publishers to pull from. Each must be a feed the publisher chooses to
# publish — this is syndication, not scraping.
FEEDS = [
    {
        "key": "fantasy_footballers",
        "name": "The Fantasy Footballers",
        # Their only feed. It is hard-capped at 3 items regardless of
        # posts_per_rss, which is fine: they publish roughly that many a day.
        "url": "https://www.thefantasyfootballers.com/feed/",
    },
]

NAMESPACES = {
    "content": "http://purl.org/rss/1.0/modules/content/",
    "dc": "http://purl.org/dc/elements/1.1/",
    "media": "http://search.yahoo.com/mrss/",
}

USER_AGENT = "CommissionersCartel/0.1 (+https://github.com/mykool223/CommissonersCartelFFL)"
TAG_RE = re.compile(r"<[^>]+>")
WHITESPACE_RE = re.compile(r"\s+")


def log(message: str) -> None:
    print(message, flush=True)


def strip_html(raw: str | None, limit: int = 400) -> str | None:
    if not raw:
        return None
    text = WHITESPACE_RE.sub(" ", TAG_RE.sub("", raw)).strip()
    # Feed excerpts are HTML-escaped; unescape after stripping tags so entities
    # inside the text survive but markup does not come back.
    import html

    text = html.unescape(text).strip()
    if not text:
        return None
    return text if len(text) <= limit else text[:limit].rsplit(" ", 1)[0] + "…"


def first_image(item: ET.Element) -> str | None:
    enclosure = item.find("enclosure")
    if enclosure is not None and (enclosure.get("type") or "").startswith("image"):
        return enclosure.get("url")
    thumb = item.find("media:thumbnail", NAMESPACES) or item.find("media:content", NAMESPACES)
    if thumb is not None and thumb.get("url"):
        return thumb.get("url")
    body = item.findtext("content:encoded", namespaces=NAMESPACES) or item.findtext("description") or ""
    match = re.search(r'<img[^>]+src="([^"]+)"', body)
    return match.group(1) if match else None


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def parse_feed(feed: dict, max_age_hours: int) -> list[dict]:
    """Returns article rows recent enough to keep."""
    try:
        raw = fetch(feed["url"])
    except (urllib.error.URLError, TimeoutError) as error:
        log(f"  !! {feed['key']}: could not fetch feed ({error})")
        return []

    try:
        channel = ET.fromstring(raw).find("channel")
    except ET.ParseError as error:
        log(f"  !! {feed['key']}: feed did not parse ({error})")
        return []

    if channel is None:
        log(f"  !! {feed['key']}: no <channel> in feed")
        return []

    cutoff = datetime.now(timezone.utc) - timedelta(hours=max_age_hours)
    rows: list[dict] = []
    skipped_old = 0

    for item in channel.findall("item"):
        link = (item.findtext("link") or "").strip()
        title = (item.findtext("title") or "").strip()
        if not link or not title:
            continue

        published_raw = item.findtext("pubDate")
        try:
            published = parsedate_to_datetime(published_raw) if published_raw else None
        except (TypeError, ValueError):
            published = None
        if published is None:
            continue
        if published.tzinfo is None:
            published = published.replace(tzinfo=timezone.utc)

        if published < cutoff:
            skipped_old += 1
            continue

        # Fall back to the link when a feed omits <guid>; the link is unique
        # per article in practice and the table's unique constraint needs one.
        guid = (item.findtext("guid") or link).strip()

        rows.append({
            "source_key": feed["key"],
            "source_name": feed["name"],
            "guid": guid[:500],
            "title": title[:300],
            "url": link,
            "excerpt": strip_html(item.findtext("description")),
            "author": (item.findtext("dc:creator", namespaces=NAMESPACES) or "").strip() or None,
            "image_url": first_image(item),
            "published_at": published.astimezone(timezone.utc).isoformat(),
        })

    log(f"  {feed['key']}: {len(rows)} within {max_age_hours}h, {skipped_old} older")
    return rows


def supabase_request(method: str, path: str, base: str, key: str,
                     body: bytes | None = None, prefer: str | None = None) -> tuple[int, bytes]:
    request = urllib.request.Request(f"{base}{path}", method=method, data=body)
    request.add_header("apikey", key)
    request.add_header("Authorization", f"Bearer {key}")
    request.add_header("Content-Type", "application/json")
    if prefer:
        request.add_header("Prefer", prefer)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
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

    log(f"Fetching {len(FEEDS)} feed(s), keeping anything newer than {max_age}h")
    rows: list[dict] = []
    for feed in FEEDS:
        rows.extend(parse_feed(feed, max_age))

    if not rows:
        # Not an error: a quiet news day is normal, and failing the job would
        # cry wolf every time a publisher takes a morning off.
        log("Nothing new to store.")
        return 0

    if dry_run:
        log(f"DRY_RUN — would upsert {len(rows)} row(s):")
        for row in rows:
            log(f"  [{row['published_at']}] {row['title'][:70]}")
        return 0

    # on_conflict on the unique (source_key, guid) pair, so re-running the job
    # updates existing rows instead of erroring or duplicating.
    status, body = supabase_request(
        "POST",
        "/rest/v1/external_articles?on_conflict=source_key,guid",
        base, key,
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
        f"/rest/v1/external_articles?published_at=lt.{urllib.parse.quote(cutoff, safe='')}",
        base, key,
        prefer="return=minimal",
    )
    if status >= 300:
        # Pruning is housekeeping; a failure should not fail the run.
        log(f"Prune failed (non-fatal): HTTP {status} {body[:200].decode(errors='replace')}")
    else:
        log(f"Pruned anything published before {cutoff}.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
