#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${1:-/tmp/InnerPeek-AuditCorpus}"
mkdir -p "$cache/real-world"
manifest="$repo_root/Tests/AuditCorpus/real-world-sources.json"

for row in ${(f)"$(jq -c '.[]' "$manifest")"}; do
  id="$(jq -r '.id' <<< "$row")"
  url="$(jq -r '.url' <<< "$row")"
  target="$cache/real-world/${id#realworld-}"
  [[ -d "$target" ]] && continue
  archive="$cache/${id}.zip"
  temp="$cache/.${id}.tmp"
  mkdir -p "$temp"
  if ! curl --fail --location --silent --show-error --max-time 45 "$url" -o "$archive"; then
    print -u2 "unavailable: $id"
    rm -rf "$temp" "$archive"
    continue
  fi
  if ! unzip -q "$archive" -d "$temp"; then
    print -u2 "invalid archive: $id"
    rm -rf "$temp" "$archive"
    continue
  fi
  top="$(find "$temp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [[ -z "$top" ]]; then
    print -u2 "empty archive: $id"
    rm -rf "$temp" "$archive"
    continue
  fi
  mv "$top" "$target"
  rm -rf "$temp" "$archive"
  print "fetched: $id"
done
