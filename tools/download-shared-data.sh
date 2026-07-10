#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# download-shared-data.sh — download the opt-in, anonymised data that users
# have shared with the developer (see Settings ▸ Share data with developers)
# from the app's CloudKit public database, for analysis.
#
# Usage:
#   tools/download-shared-data.sh <TEAM_ID> [development|production]
#
# One-time setup:
#   1. CloudKit Console ▸ Tokens & Keys ▸ create a Management Token.
#   2. xcrun cktool save-token --type management      # paste the token
#
# Requirements: Xcode (provides `xcrun cktool`) and `jq` (`brew install jq`).
# The record types must have a Queryable index on `recordName` (added in the
# CloudKit Console) or the query returns nothing.
#
# Output: cloudkit-export/SharedRating.json and cloudkit-export/SharedModel.json
# (each a single JSON array of records, paginated automatically). Convert to
# CSV with, e.g.:
#   python3 -c 'import json,pandas as pd,sys; \
#     pd.json_normalize(json.load(open(sys.argv[1]))).to_csv(sys.argv[1]+".csv",index=False)' \
#     cloudkit-export/SharedRating.json
#
set -euo pipefail

TEAM_ID="${1:?Usage: $0 <TEAM_ID> [development|production]}"
ENVIRONMENT="${2:-development}"
CONTAINER="iCloud.robotex.MyFeelsLike"
OUTDIR="${OUTDIR:-cloudkit-export}"

command -v jq >/dev/null || { echo "error: jq not found (brew install jq)"; exit 1; }
mkdir -p "$OUTDIR"

fetch_type() {
  local type="$1" out="$OUTDIR/$1.json" token="" page all="[]"
  echo "Fetching $type ($ENVIRONMENT) ..."
  while : ; do
    if [[ -n "$token" ]]; then
      page=$(xcrun cktool query-records --team-id "$TEAM_ID" --container-id "$CONTAINER" \
        --environment "$ENVIRONMENT" --database-type public --record-type "$type" \
        --limit 200 --continuation-token "$token")
    else
      page=$(xcrun cktool query-records --team-id "$TEAM_ID" --container-id "$CONTAINER" \
        --environment "$ENVIRONMENT" --database-type public --record-type "$type" \
        --limit 200)
    fi
    all=$(jq -s '.[0] + (.[1].records // [])' <(printf '%s' "$all") <(printf '%s' "$page"))
    token=$(printf '%s' "$page" | jq -r '.continuationToken // empty')
    [[ -z "$token" ]] && break
  done
  printf '%s\n' "$all" > "$out"
  echo "  $(printf '%s' "$all" | jq 'length') records -> $out"
}

fetch_type SharedRating
fetch_type SharedModel
echo "Done. JSON written to $OUTDIR/"
