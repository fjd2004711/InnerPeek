#!/bin/zsh
# Regenerates the README screenshots from fictional demo projects.
# The images are rendered offscreen by the real preview view controller (no Finder, no screen
# recording permission needed), once per language and appearance.
# Usage: scripts/render-screenshots.sh [output-directory]    (default: docs/screenshots)
set -euo pipefail

repo_root="${0:A:h:h}"
out="${1:-$repo_root/docs/screenshots}"
domain="com.innerpeek.InnerPeek"
work="$(mktemp -d)"
cleanup() {
  defaults delete "$domain" appearance.language 2>/dev/null || true
  case "${work:-}" in /var/*|/tmp/*|/private/*) rm -rf "${work:?}" ;; esac
}
trap cleanup EXIT

# A fake app bundle so Bundle(for:) finds the knowledge files, icons and strings.
app="$work/RenderPreview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.innerpeek.RenderPreview</string><key>CFBundleExecutable</key><string>RenderPreview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cp "$repo_root"/Knowledge/*.json "$app/Contents/Resources/"
cp -R "$repo_root/Knowledge/Icons" "$app/Contents/Resources/Icons"
for lproj in "$repo_root"/InnerPeekQL/*.lproj; do cp -R "$lproj" "$app/Contents/Resources/"; done

swiftc -parse-as-library -O \
  "$repo_root"/Shared/*.swift "$repo_root"/Shared/FileIntelligence/*.swift \
  "$repo_root"/InnerPeekQL/*.swift "$repo_root/Tools/RenderPreview.swift" \
  -framework AppKit -framework Quartz -framework ImageIO -framework AVFoundation -framework PDFKit \
  -o "$app/Contents/MacOS/RenderPreview"

"$repo_root/scripts/make-demo-fixtures.sh" "$(mkdir -p "$work/demo" && print -r -- "$work/demo")"

render() { "$app/Contents/MacOS/RenderPreview" "$1" "$2" "${@:3}"; }

for language in en zh-Hans; do
  defaults write "$domain" appearance.language "$language"
  dir="$out/$language"; mkdir -p "$dir"
  render "$work/demo/acme-dashboard"   "$dir/web-project.png"   900 640 light
  render "$work/demo/acme-dashboard"   "$dir/web-project-dark.png" 900 640 dark
  render "$work/demo/weather-bot"      "$dir/python-service.png" 900 520 light
  render "$work/demo/tiny-llama-chat"  "$dir/model-package.png"  900 520 light
  render "$work/demo/acme-site-release.zip" "$dir/zip-archive.png" 900 560 light
done
print "Screenshots written to $out"
