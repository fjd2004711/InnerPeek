#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
knowledge_dir="${KNOWLEDGE_DIR:-$repo_root/Knowledge}"
file_types="$knowledge_dir/file-types.json"
roles="$knowledge_dir/roles.json"
relationships="$knowledge_dir/relationships.json"

fail() { print -u2 "Knowledge validation failed: $1"; exit 1; }
for file in "$file_types" "$roles" "$relationships"; do
  [[ -f "$file" ]] || fail "missing $file"
  jq empty "$file" >/dev/null 2>&1 || fail "invalid JSON: $file"
done
for schema in "$repo_root/Schemas/file-types.schema.json" "$repo_root/Schemas/roles.schema.json" "$repo_root/Schemas/relationships.schema.json"; do
  [[ -f "$schema" ]] || fail "missing $schema"
  jq -e '.["$schema"] | type == "string"' "$schema" >/dev/null 2>&1 || fail "invalid schema: $schema"
done

jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.name.en | type) == "string" and (.name.en | length) > 0 and (.name["zh-Hans"] | type) == "string" and (.name["zh-Hans"] | length) > 0)' "$roles" >/dev/null \
  || fail "roles must have id, en, and zh-Hans"
jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.extensions | type) == "array" and (.filenames | type) == "array" and (.roles | type) == "array" and (.name.en | type) == "string" and (.name.en | length) > 0 and (.name["zh-Hans"] | type) == "string" and (.name["zh-Hans"] | length) > 0 and (.description.en | type) == "string" and (.description.en | length) > 0 and (.description["zh-Hans"] | type) == "string" and (.description["zh-Hans"] | length) > 0)' "$file_types" >/dev/null \
  || fail "file types require extensions, filenames, roles, and localized names"
jq -e 'type == "array" and all(.[]; (.id | type) == "string" and (.relationshipType | type) == "string" and (.confidence | type) == "number" and (.priority | type) == "number")' "$relationships" >/dev/null \
  || fail "relationships have an invalid shape"

duplicate_ids=$(jq -r '.[].id' "$file_types" | sort | uniq -d)
[[ -z "$duplicate_ids" ]] || fail "duplicate file type id: $duplicate_ids"
duplicate_role_ids=$(jq -r '.[].id' "$roles" | sort | uniq -d)
[[ -z "$duplicate_role_ids" ]] || fail "duplicate role id: $duplicate_role_ids"
duplicate_relationship_ids=$(jq -r '.[].id' "$relationships" | sort | uniq -d)
[[ -z "$duplicate_relationship_ids" ]] || fail "duplicate relationship id: $duplicate_relationship_ids"
duplicate_extensions=$(jq -r '.[].extensions[]? | ascii_downcase' "$file_types" | sort | uniq -d)
[[ -z "$duplicate_extensions" ]] || fail "duplicate extension: $duplicate_extensions"

role_ids=$(mktemp)
type_roles=$(mktemp)
relationship_roles=$(mktemp)
trap 'rm -f "$role_ids" "$type_roles" "$relationship_roles"' EXIT
jq -r '.[].id' "$roles" | sort -u > "$role_ids"
jq -r '.[].roles[]?' "$file_types" | sort -u > "$type_roles"
jq -r '.[] | (.optionalRoles[]?, .requiredRoles[]?)' "$relationships" | sort -u > "$relationship_roles"
unknown_type_roles=$(comm -23 "$type_roles" "$role_ids")
[[ -z "$unknown_type_roles" ]] || fail "file type references unknown role: $unknown_type_roles"
unknown_relationship_roles=$(comm -23 "$relationship_roles" "$role_ids")
[[ -z "$unknown_relationship_roles" ]] || fail "relationship references unknown role: $unknown_relationship_roles"

allowed_categories='document|spreadsheet|image|rawImage|audio|video|archive|sourceCode|configuration|database|scientificData|aiModel|threeD|font|executable|project|unknown'
bad_categories=$(jq -r --arg pattern "^($allowed_categories)$" '.[] | select((.category | test($pattern)) | not) | .id' "$file_types")
[[ -z "$bad_categories" ]] || fail "illegal category in: $bad_categories"

print "Knowledge validation passed."
