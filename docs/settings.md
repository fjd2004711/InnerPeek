# Settings and diagnostics

Open InnerPeek.app and click the gear in the header (or press ⌘,). Changes apply the next time a Quick Look preview
opens; no restart is needed.

## What can be changed

| Tab | Option | Default | Effect |
|---|---|---|---|
| Display | Summary | on | Project type and repository rows |
| Display | Tech stack | on | The technology line inside the summary |
| Display | Insights | on | Gaps and anomalies (README, tests, concentration…) |
| Display | Brand icons | on | Logos in the summary rows |
| Display | Show hidden files | off | Dotfiles in the file list (folders only) |
| Display | Expand "why this conclusion" | off | Opens the supporting evidence of each summary row |
| Analysis | Scan depth | 2 | How many folder levels are analysed (1–4) |
| Analysis | Maximum items analysed | 2,000 | 500 / 1,000 / 2,000 / 5,000 / 10,000 |
| Language & Look | Preview language | follow system | Follow system, 简体中文, English |
| Language & Look | Icon style | brand colour | Brand colour or a single colour |

A larger analysis scope finds deeper projects and fuller statistics but makes big folders slower. Results beyond the
scope are marked "≥" or "partial". Analysis is always local and read-only.

## How the settings reach the preview

The preview is a sandboxed Quick Look extension, separate from the app. The app stores preferences in its own domain
(`com.innerpeek.InnerPeek`) and the extension reads that domain through a **read-only** sandbox exception
(`com.apple.security.temporary-exception.shared-preference.read-only` in `InnerPeekQL.entitlements`). Nothing is sent
anywhere, no background service runs, and the extension cannot write preferences. Every value is validated when read, so a
corrupt or hand-edited preference falls back to defaults and an out-of-range number is clamped (depth 1–4, entry counts
snapped to the offered limits).

Power users can set the same keys with `defaults`:

```sh
defaults write com.innerpeek.InnerPeek analysis.scanDepth -int 3
defaults write com.innerpeek.InnerPeek appearance.language -string en
defaults delete com.innerpeek.InnerPeek analysis.scanDepth      # back to default
```

Keys: `preview.showSummary`, `preview.showTechStack`, `preview.showInsights`, `preview.showBrandIcons`,
`preview.showHiddenFiles`, `preview.expandReasons`, `analysis.scanDepth`, `analysis.maximumEntries`,
`appearance.language` (`en`, `zh-Hans`), `appearance.iconStyle` (`brandColor`, `monochrome`).

The extension logs the settings it loaded for each preview (no file names) under the subsystem
`com.innerpeek.InnerPeek`:

```sh
/usr/bin/log show --last 1m --info --predicate 'subsystem == "com.innerpeek.InnerPeek"'
```

## Diagnostics tab

Shows whether the Quick Look extension is healthy and offers a repair.

- **Healthy**: registered at this app's location, enabled, no stale records.
- **Not registered / registered at another location / switched off**: Finder may show its default folder card.
- **Cleanup recommended**: records point at deleted or trashed copies of InnerPeek. macOS keeps these in LaunchServices
  even after `pluginkit` forgets them, and they can make Finder fall back to its default card.

**Repair Quick Look** removes records of deleted or trashed copies, registers and enables this app's extension and resets
the Quick Look caches. Optionally it restarts Finder (which closes its windows). It never deletes files and never touches
another copy you still keep.

**Copy Diagnostics** puts a short report on the clipboard (versions, install path, extension registrations, Full Disk
Access status and these settings). It contains no file contents and shows your home folder as `~`, so it is safe to paste
into an issue.

The same repair by hand:

```sh
/usr/bin/pluginkit -a /Applications/InnerPeek.app/Contents/PlugIns/InnerPeekQL.appex
/usr/bin/pluginkit -e use -i com.innerpeek.InnerPeek.QuickLook
/usr/bin/qlmanage -r && /usr/bin/qlmanage -r cache
killall Finder
```
