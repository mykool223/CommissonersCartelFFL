#!/usr/bin/env bash
#
# Regenerates CommissionersCartel.xcodeproj from project.yml.
#
# The .xcodeproj is committed so the repo opens without extra tooling, but
# project.yml is the source of truth. Re-run this after adding a target,
# changing the bundle id, or bumping the deployment target.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it with:  brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml
echo "==> Regenerated CommissionersCartel.xcodeproj"
