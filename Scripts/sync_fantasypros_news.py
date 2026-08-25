#!/usr/bin/env python3
"""Pulls player news and analysis from FantasyPros into Supabase.

Their news endpoint carries a headline, a short factual description and an
"impact" paragraph explaining what it means for fantasy. The first two are
stored and the app links out for the rest: the analysis is their editorial
work, our licence covers personal use, and a link is the honest way to pass
somebody else's writing along.

One call per run, sharing the same hundred-a-day allowance as the rankings
sync — which is read before starting rather than assumed.

Environment:
    FANTASYPROS_API_KEY          personal API key (HOF subscription)
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    FP_NEWS_LIMIT                items to request (default 50, their max 100)
    FP_NEWS_PRUNE_DAYS           drop items older than this (default 21)
    DRY_RUN                      print instead of writing

Usage:
    DRY_RUN=1 ./Scripts/sync_fantasypros_news.py
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

# The budget guard, the caller and the Supabase helper all live with the
# rankings sync. Importing them means one implementation of "how many calls
# have we spent today", rather than two that can disagree.
_spec = importlib.util.spec_from_file_location(
    "sync_fantasypros", pathlib.Path(__file__).with_name("sync_fantasypros.py"))
sync = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sync)

DEFAULT_LIMIT = 50
DEFAULT_PRUNE_DAYS = 21


def log(message: str) -> None:
    print(message, file=sys.stderr)


def parse_when(raw: str | None) -> str | None:
    """Their timestamps are "2025-05-12 07:29:02", UTC, without a zone."""
    if not raw:
        return None
    try:
        when = dt.datetime.strptime(raw.strip(), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    return when.replace(tzinfo=dt.timezone.utc).isoformat()


def main() -> int:
    for name in ("FANTASYPROS_API_KEY", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
        if not os.environ.get(name):
            log(f"{name} is required.")
            return 2

    dry_run = bool(os.environ.get("DRY_RUN"))
    limit = int(os.environ.get("FP_NEWS_LIMIT") or DEFAULT_LIMIT)
    prune_days = int(os.environ.get("FP_NEWS_PRUNE_DAYS") or DEFAULT_PRUNE_DAYS)

    today = dt.date.today().isoformat()
    prior = sync.supabase("GET", f"fantasypros_usage?select=calls&day=eq.{today}")
    spent_today = (prior or [{}])[0].get("calls", 0) if prior else 0
    if spent_today >= sync.HARD_DAILY_CAP - sync.DAILY_RESERVE:
        log(f"{spent_today} calls already spent today; leaving the rest alone.")
        return 0

    budget = sync.Budget(1)
    data = sync.fantasypros(budget, "/nfl/news", limit=limit)
    items = data.get("items") or []
    log(f"{len(items)} item(s) returned")

    # Their news carries a player id, not a name. We already hold the mapping
    # from the rankings sync, so resolve it rather than showing a number.
    wanted = {sync.to_int(i.get("player_id")) for i in items}
    wanted.discard(None)
    names: dict[int, str] = {}
    if wanted:
        ids = ",".join(str(i) for i in wanted)
        for row in sync.supabase(
                "GET", f"fantasypros_players?select=fp_id,name&fp_id=in.({ids})") or []:
            names[row["fp_id"]] = row["name"]

    rows = []
    for item in items:
        published = parse_when(item.get("created"))
        link = item.get("link")
        source_id = sync.to_int(item.get("id"))
        if not (published and link and source_id and item.get("title")):
            continue
        rows.append({
            "source_id": source_id,
            "title": item["title"],
            "description": (item.get("desc") or "").strip() or None,
            "impact": (item.get("impact") or "").strip() or None,
            "link": link,
            "player_name": names.get(sync.to_int(item.get("player_id"))),
            "team": item.get("team_id") or None,
            "author": item.get("author") or None,
            "categories": item.get("categories") or [],
            "published_at": published,
        })

    if dry_run:
        log(f"DRY_RUN — would store {len(rows)}:")
        for row in rows[:5]:
            log(f"  {row['published_at'][:16]}  {row['title'][:70]}")
        return 0

    if rows:
        sync.supabase(
            "POST", "fantasypros_news?on_conflict=source_id", rows,
            prefer="resolution=merge-duplicates,return=minimal")
    log(f"Stored {len(rows)} item(s).")

    cutoff = (dt.datetime.now(dt.timezone.utc)
              - dt.timedelta(days=prune_days)).isoformat()
    sync.supabase("DELETE",
                  f"fantasypros_news?published_at=lt.{urllib.parse.quote(cutoff)}",
                  prefer="return=minimal")

    sync.supabase(
        "POST", "fantasypros_usage?on_conflict=day",
        [{"day": today, "calls": spent_today + budget.spent,
          "updated_at": dt.datetime.now(dt.timezone.utc).isoformat()}],
        prefer="resolution=merge-duplicates,return=minimal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
