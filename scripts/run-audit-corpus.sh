#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${1:-/tmp/InnerPeek-AuditCorpus}"
manifest="$repo_root/Tests/AuditCorpus/manifest.json"
report="${AUDIT_REPORT:-$cache/audit-report.json}"
mkdir -p "$cache"
"$repo_root/scripts/generate-audit-corpus.sh" "$cache"
"$repo_root/scripts/fetch-audit-corpus.sh" "$cache" >/dev/null 2>&1 || true

binary_dir="$(mktemp -d)"
trap 'rm -rf "$binary_dir"' EXIT
swiftc -parse-as-library \
  "$repo_root/Shared/FileIntelligence/FileCategory.swift" \
  "$repo_root/Shared/FileIntelligence/SemanticRole.swift" \
  "$repo_root/Shared/FileIntelligence/FileTypeDefinition.swift" \
  "$repo_root/Shared/FileIntelligence/FileIntelligence.swift" \
  "$repo_root/Shared/FileIntelligence/FileTypeRegistry.swift" \
  "$repo_root/Shared/FileIntelligence/FileIntelligenceRecognizer.swift" \
  "$repo_root/Shared/FileIntelligence/FolderAnalysis.swift" \
  "$repo_root/Shared/FileIntelligence/FolderAnalyzer.swift" \
  "$repo_root/Shared/FileIntelligence/ImportantFileDetector.swift" \
  "$repo_root/Shared/FileIntelligence/MetadataItem.swift" \
  "$repo_root/Shared/FileIntelligence/MetadataExtractorRegistry.swift" \
  "$repo_root/Shared/FileIntelligence/RelationshipEngine.swift" \
  "$repo_root/Shared/FileIntelligence/DeclarativeRelationshipDetector.swift" \
  "$repo_root/Shared/FileIntelligence/InsightEngine.swift" \
  "$repo_root/Shared/PreviewItem.swift" \
  "$repo_root/Shared/PreviewContentProvider.swift" \
  "$repo_root/Shared/ZIPContentProvider.swift" \
  "$repo_root/Tests/AuditCorpusRunner.swift" \
  -framework AppKit -framework ImageIO -framework AVFoundation -framework PDFKit \
  -o "$binary_dir/audit-runner"

"$binary_dir/audit-runner" "$cache" "$manifest" "$repo_root/Knowledge/file-types.json" "$repo_root/Knowledge/insights.json" > "$report"
printf 'Audit report: %s\n' "$report"
jq -r '"Cases: \(.casesExecuted) executed, \(.casesUnavailable) unavailable", "PASS: \(.pass)", "REVIEW: \(.review)", "ERROR: \(.errors)", "Insights: \(.totalInsights)", "Quiet-folder success: \(.quietFolderSuccess)/\(.quietFolderCandidates)"' "$report"
