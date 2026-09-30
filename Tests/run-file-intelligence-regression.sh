#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
binary_path="$(mktemp -d)/file-intelligence-regression"
trap 'rm -rf "${binary_path:h}"' EXIT

swiftc \
  -parse-as-library \
  "$project_root/Shared/FileIntelligence/FileCategory.swift" \
  "$project_root/Shared/FileIntelligence/SemanticRole.swift" \
  "$project_root/Shared/FileIntelligence/FileTypeDefinition.swift" \
  "$project_root/Shared/FileIntelligence/FileIntelligence.swift" \
  "$project_root/Shared/FileIntelligence/FileTypeRegistry.swift" \
  "$project_root/Shared/FileIntelligence/FileIntelligenceRecognizer.swift" \
  "$project_root/Shared/FileIntelligence/FolderAnalysis.swift" \
  "$project_root/Shared/FileIntelligence/FolderAnalyzer.swift" \
  "$project_root/Shared/FileIntelligence/ImportantFileDetector.swift" \
  "$project_root/Shared/FileIntelligence/MetadataItem.swift" \
  "$project_root/Shared/FileIntelligence/MetadataExtractorRegistry.swift" \
  "$project_root/Shared/FileIntelligence/RelationshipEngine.swift" \
  "$project_root/Shared/FileIntelligence/DeclarativeRelationshipDetector.swift" \
  "$project_root/Shared/FileIntelligence/InsightEngine.swift" \
  "$project_root/Tests/FileIntelligenceRegression.swift" \
  -framework AppKit -framework ImageIO -framework AVFoundation -framework PDFKit \
  -o "$binary_path"

"$binary_path"
