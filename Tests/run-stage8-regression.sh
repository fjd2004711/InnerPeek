#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$(mktemp -d /tmp/InnerPeek-Stage8-XXXXXX)"
trap 'rm -rf "$cache"' EXIT
"$repo_root/scripts/run-audit-corpus.sh" "$cache" >/dev/null
report="$cache/audit-report.json"
jq -e '
  .casesExecuted >= 27 and .errors == 0 and .review == 0 and
  .verdictFailures == 0 and .evidenceFailures == 0 and .parityFailures == 0 and
  .visibleInsightViolations == 0 and .forbiddenRelationshipTriggers == 0 and
  .casesWithInsightOverflow == 0
' "$report" >/dev/null
printf 'Stage 8 decision-layer regression checks passed.\n'
