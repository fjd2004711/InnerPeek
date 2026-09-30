#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
binary_path="$(mktemp -d)/file-intelligence-regression"
trap 'rm -rf "${binary_path:h}"' EXIT

swiftc \
  -parse-as-library \
  "$project_root/Shared/FileIntelligence/FileCategory.swift" \
  "$project_root/Shared/FileIntelligence/FileTypeDefinition.swift" \
  "$project_root/Shared/FileIntelligence/FileIntelligence.swift" \
  "$project_root/Shared/FileIntelligence/FileTypeRegistry.swift" \
  "$project_root/Shared/FileIntelligence/FileIntelligenceRecognizer.swift" \
  "$project_root/Shared/FileIntelligence/FolderAnalysis.swift" \
  "$project_root/Shared/FileIntelligence/FolderAnalyzer.swift" \
  "$project_root/Shared/FileIntelligence/ImportantFileDetector.swift" \
  "$project_root/Tests/FileIntelligenceRegression.swift" \
  -o "$binary_path"

"$binary_path"
