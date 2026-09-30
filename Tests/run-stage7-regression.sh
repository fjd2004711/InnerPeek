#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$(mktemp -d /tmp/InnerPeek-Stage7-XXXXXX)"
trap 'rm -rf "$cache"' EXIT
"$repo_root/scripts/run-audit-corpus.sh" "$cache" >/dev/null
report="$cache/audit-report.json"
jq -e '.casesExecuted >= 21 and .errors == 0 and .review == 0 and .forbiddenRelationshipTriggers == 0 and .casesWithInsightOverflow == 0' "$report" >/dev/null
printf 'Stage 7 ZIP and audit regression checks passed.\n'
