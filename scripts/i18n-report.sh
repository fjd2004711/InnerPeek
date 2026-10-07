#!/bin/zsh
# Translation coverage for one language.
#   scripts/i18n-report.sh zh-Hans            summary
#   scripts/i18n-report.sh fr --missing       also list every untranslated English text
set -euo pipefail

repo_root="${0:A:h:h}"
lang="${1:?usage: i18n-report.sh <language-tag, e.g. fr or zh-Hant> [--missing]}"
show_missing="${2:-}"
command -v jq >/dev/null || { print -u2 "jq is required (brew install jq)"; exit 1; }
[[ "$lang" == "en" ]] && { print "English is the source language; nothing to translate."; exit 0; }
knowledge="$repo_root/Knowledge"

typeset -i grand_total=0 grand_done=0
report() { # label total done
  local label="$1" total="$2" done_="$3"
  grand_total+=total; grand_done+=done_
  printf '  %-34s %4d / %-4d  %3d%%\n' "$label" "$done_" "$total" $(( total == 0 ? 100 : done_ * 100 / total ))
}

print "Translation coverage for: $lang"

# Interface strings (standard .strings files)
ui_en="$repo_root/InnerPeekQL/en.lproj/Localizable.strings"
ui_target="$repo_root/InnerPeekQL/$lang.lproj/Localizable.strings"
ui_total=$(grep -cE '^"[^"]+"' "$ui_en")
if [[ -f "$ui_target" ]]; then ui_done=$(comm -12 <(grep -oE '^"[^"]+"' "$ui_en" | sort) <(grep -oE '^"[^"]+"' "$ui_target" | sort) | wc -l | tr -d ' '); else ui_done=0; fi
report "Interface (InnerPeekQL/$lang.lproj)" $ui_total $ui_done
if [[ "$show_missing" == "--missing" ]]; then
  comm -23 <(grep -oE '^"[^"]+"' "$ui_en" | sort) <( [[ -f "$ui_target" ]] && grep -oE '^"[^"]+"' "$ui_target" | sort || true ) | sed 's/^/    missing UI key: /'
fi

# Messages written in the code (keys are the English text)
msg_total=$(jq '.messages | length' "$knowledge/messages.json")
msg_done=$(jq --arg l "$lang" '[.messages[] | select(has($l))] | length' "$knowledge/messages.json")
report "Messages (Knowledge/messages.json)" $msg_total $msg_done
[[ "$show_missing" == "--missing" ]] && jq -r --arg l "$lang" '.messages | to_entries[] | select(.value | has($l) | not) | "    missing message: \(.key)"' "$knowledge/messages.json"

# Texts embedded in knowledge files: any object that has an "en" string
for file in file-types roles insights project-recognition repository-health; do
  total=$(jq '[.. | objects | select(has("en") and (.en | type == "string"))] | length' "$knowledge/$file.json")
  done_=$(jq --arg l "$lang" '[.. | objects | select(has("en") and (.en | type == "string") and has($l))] | length' "$knowledge/$file.json")
  report "Knowledge ($file.json)" $total $done_
  [[ "$show_missing" == "--missing" ]] && jq -r --arg l "$lang" '.. | objects | select(has("en") and (.en | type == "string") and (has($l) | not)) | "    missing \(input_filename): \(.en)"' "$knowledge/$file.json" | sed "s#\\(missing \\)[^:]*#\\1$file#"
done
print "  ---"
printf '  %-34s %4d / %-4d  %3d%%\n' "Total" $grand_done $grand_total $(( grand_total == 0 ? 100 : grand_done * 100 / grand_total ))
