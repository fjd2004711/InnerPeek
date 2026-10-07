#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
knowledge_dir="${KNOWLEDGE_DIR:-$repo_root/Knowledge}"
file_types="$knowledge_dir/file-types.json"
roles="$knowledge_dir/roles.json"
relationships="$knowledge_dir/relationships.json"
insights="$knowledge_dir/insights.json"
git_recognition="$knowledge_dir/git-recognition.json"
project_recognition="$knowledge_dir/project-recognition.json"
icon_registry="$knowledge_dir/icon-registry.json"
icon_dir="$knowledge_dir/Icons"

fail() { print -u2 "Knowledge validation failed: $1"; exit 1; }
for file in "$file_types" "$roles" "$relationships" "$insights" "$git_recognition" "$project_recognition" "$icon_registry"; do
  [[ -f "$file" ]] || fail "missing $file"
  jq empty "$file" >/dev/null 2>&1 || fail "invalid JSON: $file"
done
for schema in "$repo_root/Schemas/file-types.schema.json" "$repo_root/Schemas/roles.schema.json" "$repo_root/Schemas/relationships.schema.json" "$repo_root/Schemas/insights.schema.json" "$repo_root/Schemas/git-recognition.schema.json" "$repo_root/Schemas/project-recognition.schema.json" "$repo_root/Schemas/icon-registry.schema.json"; do
  [[ -f "$schema" ]] || fail "missing $schema"
  jq -e '.["$schema"] | type == "string"' "$schema" >/dev/null 2>&1 || fail "invalid schema: $schema"
done

jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.name.en | type) == "string" and (.name.en | length) > 0 and (.name["zh-Hans"] | type) == "string" and (.name["zh-Hans"] | length) > 0)' "$roles" >/dev/null \
  || fail "roles must have id, en, and zh-Hans"
jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.extensions | type) == "array" and (.filenames | type) == "array" and (.roles | type) == "array" and (.name.en | type) == "string" and (.name.en | length) > 0 and (.name["zh-Hans"] | type) == "string" and (.name["zh-Hans"] | length) > 0 and (.description.en | type) == "string" and (.description.en | length) > 0 and (.description["zh-Hans"] | type) == "string" and (.description["zh-Hans"] | length) > 0)' "$file_types" >/dev/null \
  || fail "file types require extensions, filenames, roles, and localized names"
jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.relationshipType | type) == "string" and (.confidence | type) == "number" and (.priority | type) == "number")' "$relationships" >/dev/null \
  || fail "relationships have an invalid shape"
jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.relationshipType | type) == "string" and (.requiredRoles | type) == "array" and (.requiredRoles | length) > 0 and (.recommendedRoles | type) == "array" and (.messages | type) == "object")' "$insights" >/dev/null \
  || fail "insights require a relationship, required roles, and messages"
jq -e '(.version == 1) and (.hosts | type == "array") and (.metadataPaths | type == "array") and (all(.hosts[]; (.host | type == "string" and test("^[A-Za-z0-9.-]+$")) and (.provider | IN("github", "gitlab", "bitbucket")))) and (all(.metadataPaths[]; ((.path | type) == "string") and ((.path | startswith("/")) | not) and ((.path | contains("..")) | not) and (.kind | IN("file", "directory", "any"))))' "$git_recognition" >/dev/null \
  || fail "git recognition declarations are malformed"

duplicate_ids=$(jq -r '.[].id' "$file_types" | sort | uniq -d)
[[ -z "$duplicate_ids" ]] || fail "duplicate file type id: $duplicate_ids"
duplicate_role_ids=$(jq -r '.[].id' "$roles" | sort | uniq -d)
[[ -z "$duplicate_role_ids" ]] || fail "duplicate role id: $duplicate_role_ids"
duplicate_relationship_ids=$(jq -r '.[].id' "$relationships" | sort | uniq -d)
[[ -z "$duplicate_relationship_ids" ]] || fail "duplicate relationship id: $duplicate_relationship_ids"
duplicate_insight_ids=$(jq -r '.[].id' "$insights" | sort | uniq -d)
[[ -z "$duplicate_insight_ids" ]] || fail "duplicate insight id: $duplicate_insight_ids"
duplicate_git_hosts=$(jq -r '.hosts[].host | ascii_downcase' "$git_recognition" | sort | uniq -d)
[[ -z "$duplicate_git_hosts" ]] || fail "duplicate Git host: $duplicate_git_hosts"
duplicate_git_metadata_paths=$(jq -r '.metadataPaths[].path' "$git_recognition" | sort | uniq -d)
[[ -z "$duplicate_git_metadata_paths" ]] || fail "duplicate Git metadata path: $duplicate_git_metadata_paths"
duplicate_extensions=$(jq -r '.[].extensions[]? | ascii_downcase' "$file_types" | sort | uniq -d)
[[ -z "$duplicate_extensions" ]] || fail "duplicate extension: $duplicate_extensions"

# Project recognition: declarative evidence rules for project kinds, languages, frameworks, build systems and package managers.
jq -e '
  def valid_weight: type == "number" and . > 0 and . <= 1;
  def safe_path: type == "string" and length > 0 and (startswith("/") | not) and (contains("..") | not) and (contains("\u0000") | not)
    and ((contains("*") | not) or (contains("/") | not)) and ((split("/") | length) <= 3);
  def valid_evidence:
    if .type == "path_exists" then (.path | safe_path) and (.weight | valid_weight) and (keys - ["type","path","weight"] | length == 0)
    elif .type == "manifest_dependency" then (.file | IN("package.json","requirements.txt","pyproject.toml","Cargo.toml","go.mod")) and (.key | type == "string" and length > 0) and (.weight | valid_weight) and (keys - ["type","file","key","weight"] | length == 0)
    elif .type == "manifest_key" then (.file | IN("package.json","pyproject.toml","Cargo.toml")) and (.key | type == "string" and length > 0) and (.weight | valid_weight) and (keys - ["type","file","key","weight"] | length == 0)
    elif .type == "manifest_text" then (.file | type == "string" and length > 0 and (contains("/") | not)) and (.contains | type == "string" and length > 0) and (.weight | valid_weight) and (keys - ["type","file","contains","weight"] | length == 0)
    elif .type == "extension_share" then (.extensions | type == "array" and length > 0 and all(.[]; type == "string" and test("^[a-z0-9]+$"))) and ((.minimumFiles // 1) | type == "number" and . >= 1 and . == floor) and ((.minimumShare // 0) | type == "number" and . >= 0 and . <= 1) and (.weight | valid_weight) and (keys - ["type","extensions","minimumFiles","minimumShare","weight"] | length == 0)
    else false end;
  (.version == 1) and (.detectionThreshold | type == "number" and . > 0 and . <= 1) and (.conflictMargin | type == "number" and . >= 0 and . <= 1)
  and (.facts | type == "array" and length > 0)
  and all(.facts[]; (.id | type == "string" and test("^(projectKind|language|framework|buildSystem|packageManager)\\.[a-z0-9][a-z0-9.-]*$"))
      and (.kind | IN("projectKind","language","framework","buildSystem","packageManager"))
      and ((.id | split(".")[0]) == .kind)
      and (.name.en | type == "string" and length > 0) and (.name["zh-Hans"] | type == "string" and length > 0)
      and (.evidence | type == "array") and all(.evidence[]; valid_evidence)
      and ((.group // "x") | type == "string" and test("^[A-Za-z0-9.-]+$"))
      and ((.supersedes // []) | type == "array") and ((.implies // []) | type == "array"))
' "$project_recognition" >/dev/null || fail "project recognition declarations are malformed"
duplicate_fact_ids=$(jq -r '.facts[].id' "$project_recognition" | sort | uniq -d)
[[ -z "$duplicate_fact_ids" ]] || fail "duplicate project fact id: $duplicate_fact_ids"
unknown_fact_refs=$(jq -r '[.facts[].id] as $ids | .facts[] | (.supersedes[]?, .implies[]?) | select(. as $r | $ids | index($r) | not)' "$project_recognition")
[[ -z "$unknown_fact_refs" ]] || fail "project fact references unknown fact: $unknown_fact_refs"
self_fact_refs=$(jq -r '.facts[] | select(.id as $id | ((.supersedes // []) + (.implies // [])) | index($id)) | .id' "$project_recognition")
[[ -z "$self_fact_refs" ]] || fail "project fact references itself: $self_fact_refs"
mutual_supersedes=$(jq -r '.facts as $f | $f[] | .id as $a | (.supersedes // [])[] as $b | select($f[] | select(.id == $b) | (.supersedes // []) | index($a)) | "\($a)<->\($b)"' "$project_recognition")
[[ -z "$mutual_supersedes" ]] || fail "project facts supersede each other: $mutual_supersedes"
mixed_group_kinds=$(jq -r '[.facts[] | select(.group != null)] | group_by(.group)[] | select((map(.kind) | unique | length) > 1) | .[0].group' "$project_recognition")
[[ -z "$mixed_group_kinds" ]] || fail "project fact group mixes kinds: $mixed_group_kinds"
cross_kind_supersedes=$(jq -r '.facts as $f | $f[] | .kind as $k | .id as $id | (.supersedes // [])[] as $b | select($f[] | select(.id == $b and .kind != $k)) | $id' "$project_recognition")
[[ -z "$cross_kind_supersedes" ]] || fail "project fact supersedes a different kind: $cross_kind_supersedes"
unreachable_facts=$(jq -r '[.facts[].implies[]?] as $implied | .facts[] | select((.evidence | length) == 0 and (.id as $id | $implied | index($id) | not)) | .id' "$project_recognition")
[[ -z "$unreachable_facts" ]] || fail "project fact has no evidence and is never implied: $unreachable_facts"

# Visual identity: every referenced icon key resolves to a bundled, safe SVG; unreferenced icons are reported.
jq -e '(.version == 1) and (.icons | type == "object" and length > 0)
  and all(.icons | to_entries[]; (.key | test("^brand\\.[a-z0-9-]+$")) and (.value.asset | type == "string" and test("^[a-z0-9-]+$"))
      and (.value.source == "simple-icons") and (.value.sourceVersion | type == "string") and (.value.upstream | type == "string" and length > 0) and (.value.monochrome | type == "boolean"))
  and (.repositoryProviders | type == "object" and has("github") and has("gitlab") and has("bitbucket") and has("other"))' "$icon_registry" >/dev/null \
  || fail "icon registry is malformed"
registry_keys=$(mktemp); used_keys=$(mktemp);
jq -r '.icons | keys[]' "$icon_registry" | sort -u > "$registry_keys"
{ jq -r '.facts[].visual.icon? // empty' "$project_recognition"; jq -r '.repositoryProviders[]' "$icon_registry"; } | sort -u > "$used_keys"
unknown_icons=$(comm -13 "$registry_keys" "$used_keys")
[[ -z "$unknown_icons" ]] || fail "icon key is not in the icon registry: $unknown_icons"
for asset in $(jq -r '.icons[].asset' "$icon_registry" | sort -u); do
  svg="$icon_dir/brands/$asset.svg"
  [[ -f "$svg" ]] || fail "icon asset missing: $svg"
  [[ "$(head -c 4 "$svg")" == "<svg" ]] || fail "icon asset is not an SVG: $svg"
  (( $(wc -c < "$svg") <= 8192 )) || fail "icon asset too large: $svg"
  if grep -qiE '<script|<image|foreignObject|href=|xlink:|onload=|@import|url\(' "$svg"; then fail "icon asset contains active or external content: $svg"; fi
done
duplicate_assets=$(jq -r '.icons[].asset' "$icon_registry" | sort | uniq -d)
[[ -z "$duplicate_assets" ]] || fail "two icon keys share an asset: $duplicate_assets"
orphan_svgs=$(comm -13 <(jq -r '.icons[].asset' "$icon_registry" | sort -u) <(ls "$icon_dir/brands" | sed 's/\.svg$//' | sort -u))
[[ -z "$orphan_svgs" ]] || fail "bundled SVG not in the registry: $orphan_svgs"
unreferenced_icons=$(comm -23 "$registry_keys" "$used_keys")
[[ -z "$unreferenced_icons" ]] || print -u2 "warning: icon is bundled but no fact references it: $unreferenced_icons"
for asset in $(jq -r '.icons[].asset' "$icon_registry" | sort -u); do
  grep -q "brands/$asset.svg" "$icon_dir/LICENSES.md" || fail "icon not listed in Icons/LICENSES.md: $asset"
done

role_ids=$(mktemp)
type_roles=$(mktemp)
relationship_roles=$(mktemp)
insight_roles=$(mktemp)
relationship_ids=$(mktemp)
trap 'rm -f "$role_ids" "$type_roles" "$relationship_roles" "$insight_roles" "$relationship_ids" "$registry_keys" "$used_keys"' EXIT
jq -r '.[].id' "$roles" | sort -u > "$role_ids"
jq -r '.[].roles[]?' "$file_types" | sort -u > "$type_roles"
jq -r '.[] | (.optionalRoles[]?, .requiredRoles[]?)' "$relationships" | sort -u > "$relationship_roles"
jq -r '.[].relationshipType' "$relationships" | sort -u > "$relationship_ids"
printf '%s\n' shapefile transformer latex xcode >> "$relationship_ids"
sort -u "$relationship_ids" -o "$relationship_ids"
jq -r '.[].requiredRoles[]?, .[].recommendedRoles[]?' "$insights" | sort -u > "$insight_roles"
unknown_type_roles=$(comm -23 "$type_roles" "$role_ids")
[[ -z "$unknown_type_roles" ]] || fail "file type references unknown role: $unknown_type_roles"
unknown_relationship_roles=$(comm -23 "$relationship_roles" "$role_ids")
[[ -z "$unknown_relationship_roles" ]] || fail "relationship references unknown role: $unknown_relationship_roles"
unknown_insight_roles=$(comm -23 "$insight_roles" "$role_ids")
[[ -z "$unknown_insight_roles" ]] || fail "insight references unknown role: $unknown_insight_roles"
unknown_insight_relationships=$(jq -r '.[].relationshipType' "$insights" | sort -u | comm -23 - "$relationship_ids")
[[ -z "$unknown_insight_relationships" ]] || fail "insight references unknown relationship: $unknown_insight_relationships"

bad_insight_severity=$(jq -r '.[] | .completeSeverity, .missingRequiredSeverity, .missingRecommendedSeverity' "$insights" | grep -Ev '^(info|positive|notice|warning)$' || true)
[[ -z "$bad_insight_severity" ]] || fail "invalid insight severity: $bad_insight_severity"

allowed_categories='document|spreadsheet|image|rawImage|audio|video|archive|sourceCode|configuration|database|scientificData|aiModel|threeD|font|executable|project|unknown'
bad_categories=$(jq -r --arg pattern "^($allowed_categories)$" '.[] | select((.category | test($pattern)) | not) | .id' "$file_types")
[[ -z "$bad_categories" ]] || fail "illegal category in: $bad_categories"

print "Knowledge validation passed."
