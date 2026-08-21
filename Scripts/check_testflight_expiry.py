#!/usr/bin/env python3
"""Warn before the TestFlight build expires.

TestFlight builds stop working 90 days after upload, and an expired build does
not degrade — it refuses to launch, for every tester at once. During the season
this never fires, because shipping changes resets the clock. It exists for the
offseason, when the app goes untouched for months.

Prints a GitHub Actions-friendly summary and exits 0 always; the workflow
decides whether to open an issue based on `needs_reminder` in the output.

    ./Scripts/check_testflight_expiry.py
    ./Scripts/check_testflight_expiry.py --days 75   # pretend, to test
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import sys

LIFETIME_DAYS = 90
# Three weeks' notice: enough to act on without becoming background noise.
WARN_AFTER_DAYS = 70

RECORD = pathlib.Path(__file__).resolve().parent.parent / ".testflight" / "last-upload.json"


def emit(name: str, value: str) -> None:
    """Writes a GitHub Actions output, or prints it when run locally."""
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")
    else:
        print(f"  {name}={value}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, help="Override the age, for testing.")
    args = parser.parse_args()

    if not RECORD.exists():
        print("No upload recorded yet; nothing to check.")
        emit("needs_reminder", "false")
        return 0

    record = json.loads(RECORD.read_text())
    build = record.get("build", "unknown")
    uploaded = record.get("uploadedAt", "")

    if args.days is not None:
        age = args.days
    else:
        try:
            when = datetime.datetime.fromisoformat(uploaded.replace("Z", "+00:00"))
        except ValueError:
            print(f"Could not read the upload date {uploaded!r}; skipping.")
            emit("needs_reminder", "false")
            return 0
        age = (datetime.datetime.now(datetime.timezone.utc) - when).days

    remaining = LIFETIME_DAYS - age
    print(f"Build {build} is {age} days old; {remaining} days until it expires.")

    emit("build", build)
    emit("uploaded", uploaded)
    emit("age", str(age))
    emit("remaining", str(remaining))
    emit("needs_reminder", "true" if age >= WARN_AFTER_DAYS else "false")
    return 0


if __name__ == "__main__":
    sys.exit(main())
