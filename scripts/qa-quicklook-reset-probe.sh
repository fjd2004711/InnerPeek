#!/bin/zsh
# Clean-slate Quick Look reset + automated Finder probe for InnerPeek (macOS only).
#
#   scripts/qa-quicklook-reset-probe.sh [/Applications/InnerPeek.app]
#
# 1. Unregisters every InnerPeek LaunchServices/pluginkit record EXCEPT the target app
#    (registration only: no files are deleted).
# 2. Re-registers the target appex, resets Quick Look caches, restarts Finder/Quick Look.
# 3. Creates a sample folder + ZIP, presses Space in Finder on each (needs Accessibility
#    permission for your terminal), captures /usr/bin/log and a screenshot per case.
# Output goes to $OUT (printed at the end). Read SUMMARY.txt first.
set -u
APP="${1:-/Applications/InnerPeek.app}"
APPEX="$APP/Contents/PlugIns/InnerPeekQL.appex"
BID="com.innerpeek.InnerPeek.QuickLook"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
OUT="${TMPDIR:-/tmp}/innerpeek-qa-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"; SUM="$OUT/SUMMARY.txt"
say() { echo "$@" | tee -a "$SUM"; }

[[ -d "$APPEX" ]] || { echo "missing $APPEX"; exit 1; }

say "== 1. audit + unregister stale registrations"
$LSR -dump | grep -E '^path:.*InnerPeek' | sed 's/^path: *//; s/ (0x[0-9a-f]*)$//' | sort -u > "$OUT/ls-paths.txt"
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  case "$p" in "$APP"|"$APP"/*) say "KEEP     $p"; continue;; esac
  [[ -e "$p" ]] && state=EXISTS || state=MISSING
  say "UNREG    [$state] $p"
  $LSR -u "$p" >/dev/null 2>&1
  [[ "$p" == *.appex ]] && pluginkit -r "$p" >/dev/null 2>&1
done < "$OUT/ls-paths.txt"
pluginkit -mAvvv -p com.apple.quicklook.preview 2>/dev/null | grep -i innerpeek > "$OUT/pluginkit-before.txt"

say "== 2. register target + reset caches"
$LSR -f -R -trusted "$APP" >/dev/null 2>&1
pluginkit -a "$APPEX"; pluginkit -e use -i "$BID"
qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1
killall Finder QuickLookUIService quicklookd 2>/dev/null; sleep 3
pluginkit -mAvvv -p com.apple.quicklook.preview 2>/dev/null | grep -i innerpeek | tee "$OUT/pluginkit-after.txt" | tee -a "$SUM"
say "registered appex count: $(pluginkit -m -i $BID -v 2>/dev/null | grep -c innerpeek)"
plutil -p "$APPEX/Contents/Info.plist" > "$OUT/appex-Info.plist.txt"
codesign -dvvv --entitlements - "$APPEX" > "$OUT/appex-codesign.txt" 2>&1
say "appex content types: $(grep -A4 QLSupportedContentTypes "$OUT/appex-Info.plist.txt" | tr -d '\n ')"

say "== 3. Finder probe"
S="$OUT/sample"; mkdir -p "$S/proj/src" "$S/proj/docs"
echo '{"name":"demo","version":"1.0.0"}' > "$S/proj/package.json"
echo 'console.log(1)' > "$S/proj/src/index.js"; echo hi > "$S/proj/docs/README.md"
git -C "$S/proj" init -q 2>/dev/null; git -C "$S/proj" remote add origin https://github.com/octocat/Hello-World.git 2>/dev/null
(cd "$S" && zip -qr sample.zip proj)

probe() { # name path
  local name="$1" path="$2" logf="$OUT/log-$1.txt"
  /usr/bin/log stream --level debug --predicate \
    'process IN {"Finder","quicklookd","QuickLookUIService","extensionkitservice","pkd","InnerPeekQL"} OR eventMessage CONTAINS[c] "innerpeek"' > "$logf" 2>&1 &
  local lp=$!; sleep 2
  osascript -e "tell application \"Finder\" to activate" \
            -e "tell application \"Finder\" to reveal (POSIX file \"$path\" as alias)" \
            -e "delay 1" -e 'tell application "System Events" to key code 49' >/dev/null 2>&1
  sleep 4; screencapture -x "$OUT/shot-$name.png"
  osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1; sleep 1
  kill $lp 2>/dev/null; wait $lp 2>/dev/null
  local fb=$(grep -c "Falling back on Generic" "$logf")
  local ip=$(grep -ci "innerpeek" "$logf")
  say "[$name] fallback-to-generic lines: $fb | innerpeek log lines: $ip | screenshot: shot-$name.png"
  grep -iE "innerpeek|Retrieving extension|Falling back|entitlement|sandbox|invalid|denied" "$logf" | head -15 | sed 's/^/    /' | tee -a "$SUM"
}
probe folder "$S/proj"
probe zip    "$S/sample.zip"

say ""
say "== verdict hints"
say "ZIP shows InnerPeek but folder falls back  -> system does not dispatch public.folder to 3rd-party preview extensions (not an extension bug)."
say "Both fall back + no innerpeek log lines     -> extension never loaded: check pluginkit-after.txt, appex-codesign.txt, Info.plist."
say "Both fall back + innerpeek load errors      -> read the error lines above."
say "Output dir: $OUT   (open shot-*.png to confirm visually)"
