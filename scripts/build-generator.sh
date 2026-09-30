#!/bin/zsh
# Builds (and optionally installs) InnerPeek.qlgenerator, the legacy Quick Look
# generator that serves ordinary-folder previews.
#
#   scripts/build-generator.sh            # build into build/InnerPeek.qlgenerator
#   scripts/build-generator.sh --install  # also install to ~/Library/QuickLook and reset Quick Look
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/InnerPeek.qlgenerator"
obj="$root/build/obj"
rm -rf "$out" "$obj"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources" "$obj"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
if [[ ! -f "$sdk/System/Library/Frameworks/QuickLook.framework/Headers/QLGenerator.h" ]]; then
  echo "error: QLGenerator.h is missing from the SDK at $sdk; the legacy generator API is unavailable." >&2
  exit 1
fi

clang -c -arch "$(uname -m)" -mmacosx-version-min=14.0 -isysroot "$sdk" -O2 \
  "$root/Generator/main.c" -o "$obj/main.o"

swiftc -emit-library -parse-as-library -wmo -O \
  -module-name InnerPeekGenerator -target "$(uname -m)-apple-macos14.0" \
  "$root"/Shared/FileIntelligence/*.swift \
  "$root/Generator/HTMLPreview.swift" \
  "$obj/main.o" \
  -framework CoreServices -framework QuickLook -framework AppKit \
  -framework ImageIO -framework AVFoundation -framework PDFKit \
  -o "$out/Contents/MacOS/InnerPeek"

cp "$root/Generator/Info.plist" "$out/Contents/Info.plist"
cp "$root"/Knowledge/*.json "$out/Contents/Resources/"
codesign --force --sign - "$out"
echo "Built $out"

if [[ "${1:-}" == "--install" ]]; then
  dest="$HOME/Library/QuickLook"
  mkdir -p "$dest"
  rm -rf "$dest/InnerPeek.qlgenerator"
  cp -R "$out" "$dest/"
  qlmanage -r
  qlmanage -r cache
  echo "Installed to $dest. Test: qlmanage -p <folder>   (or select a folder in Finder and press Space)"
fi
