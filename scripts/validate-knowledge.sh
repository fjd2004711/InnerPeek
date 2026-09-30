#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
knowledge_dir="${KNOWLEDGE_DIR:-$repo_root/Knowledge}"
file_types="$knowledge_dir/file-types.json"
roles="$knowledge_dir/roles.json"
relationships="$knowledge_dir/relationships.json"
insights="$knowledge_dir/insights.json"
git_recognition="$knowledge_dir/git-recognition.json"

fail() { print -u2 "Knowledge validation failed: $1"; exit 1; }
for file in "$file_types" "$roles" "$relationships" "$insights" "$git_recognition"; do
  [[ -f "$file" ]] || fail "missing $file"
  jq empty "$file" >/dev/null 2>&1 || fail "invalid JSON: $file"
done
for schema in "$repo_root/Schemas/file-types.schema.json" "$repo_root/Schemas/roles.schema.json" "$repo_root/Schemas/relationships.schema.json" "$repo_root/Schemas/insights.schema.json" "$repo_root/Schemas/git-recognition.schema.json"; do
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

role_ids=$(mktemp)
type_roles=$(mktemp)
relationship_roles=$(mktemp)
insight_roles=$(mktemp)
relationship_ids=$(mktemp)
trap 'rm -f "$role_ids" "$type_roles" "$relationship_roles" "$insight_roles" "$relationship_ids"' EXIT
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
