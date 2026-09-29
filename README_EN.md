<p align="center">
  <img src="InnerPeek/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="104" alt="InnerPeek icon">
</p>

<h1 align="center">InnerPeek</h1>

<p align="center"><strong>Press Space in Finder. See what's inside folders and ZIP archives.</strong></p>

<p align="center">
  <a href="https://github.com/fjd2004711/InnerPeek/releases/latest">Download</a> ·
  <a href="#installation">Install</a> ·
  <a href="#building-from-source">Build</a> ·
  <a href="README.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/fjd2004711/InnerPeek/releases/latest"><img src="https://img.shields.io/github/v/release/fjd2004711/InnerPeek?display_name=tag&sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26 or later recommended">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/fjd2004711/InnerPeek" alt="MIT license"></a>
</p>

InnerPeek is a lightweight Quick Look extension for macOS. Select a folder or ZIP archive, press Space, and browse its directory tree in Finder's native preview window—without opening another app or extracting the archive first.

## Preview

| Folder | ZIP archive |
| :---: | :---: |
| <img src="docs/demo/innerpeek-folder-light-preview.png" width="420" alt="InnerPeek folder preview"> | <img src="docs/demo/innerpeek-zip-light-preview.png" width="420" alt="InnerPeek ZIP preview"> |

These are actual Finder previews. The repository also includes a [demo folder](docs/demo/InnerPeek-Demo) and a [matching ZIP](docs/demo/InnerPeek-Demo/InnerPeek-ZIP-Demo.zip) that you can try yourself.

## Features

- **Tree browsing:** Expand and collapse folders and directories inside ZIP archives.
- **Useful metadata:** See names, file sizes, modification dates, and file-type icons at a glance.
- **No ZIP extraction:** Reads the ZIP directory index without reading file bodies or writing an extracted copy to disk.
- **On-demand loading:** Reads folders only when expanded, while system file icons are resolved and cached in the background.
- **Native experience:** Built on Quick Look and AppKit's `NSOutlineView` for familiar Finder-style interactions.
- **Local and read-only:** Preview content is not uploaded or modified, and there is no persistent background service.

## Requirements

- macOS 26 or later recommended
- Apple Silicon or Intel Mac

## Installation

1. Download the latest DMG from [GitHub Releases](https://github.com/fjd2004711/InnerPeek/releases/latest).
2. Open the DMG and drag `InnerPeek.app` to **Applications**.
3. Open InnerPeek once so macOS can register the Quick Look extension.
4. Select a folder or ZIP in Finder and press Space.

Click a folder row or its disclosure arrow to expand or collapse it. Press Space again to close the preview.

### Protected locations

Ordinary folders need no extra permission. To preview Desktop, Documents, Downloads, Mail data, or other macOS-protected locations, go to:

**System Settings → Privacy & Security → Full Disk Access → “+” → select `/Applications/InnerPeek.app` → enable it**

Reopen the Finder preview after granting access. Full Disk Access is not required for everyday use; InnerPeek uses it only to read content you explicitly preview.

## How it works

InnerPeek is designed to shorten the “press Space for a quick look” path:

| Scenario | Implementation |
| --- | --- |
| Folders | Reads only the current level, loads subfolders when expanded, and skips hidden files. |
| ZIP archives | Parses the central directory and builds an in-memory tree without extracting files. |
| File icons | Shows lightweight type icons first, then resolves and caches Finder icons for on-disk files in the background. |
| Interface | A Quick Look extension hosts a native `NSOutlineView` for selection, expansion, and scrolling. |

This avoids full archive extraction, eager traversal of an entire directory tree, and large numbers of synchronous icon lookups on the main thread.

## Current limitations

- InnerPeek currently previews folders and ordinary single-volume ZIP archives only.
- ZIP64 and split archives are not supported. Non-UTF-8 names in legacy ZIPs may not display correctly.
- Individual files inside a ZIP cannot be opened or exported from the preview.
- Hidden files are omitted from folder previews by default.

InnerPeek focuses on quickly inspecting content structure; it is not a replacement for a full file manager or archive utility.

## FAQ

<details>
<summary><strong>Why don't I see the directory tree after installing InnerPeek?</strong></summary>

Make sure the app is in **Applications** and has been opened at least once. Close the current Quick Look window and preview the item again. If the item is in a protected location, check Full Disk Access.

</details>

<details>
<summary><strong>Does ZIP preview create temporary extracted files?</strong></summary>

No. InnerPeek reads only metadata such as names, hierarchy, sizes, and dates from the ZIP central directory.

</details>

<details>
<summary><strong>Why do icons inside ZIP archives look slightly different?</strong></summary>

A ZIP entry has no real path that Finder can inspect. InnerPeek uses and caches system type icons based on the filename extension and content type, avoiding temporary files created solely for icons.

</details>

## Building from source

The project has no third-party runtime dependencies.

1. Clone the repository and open [`InnerPeek.xcodeproj`](InnerPeek.xcodeproj) with Xcode 15 or later.
2. Select the `InnerPeek` scheme and `My Mac` as the run destination.
3. If Xcode reports a signing issue, select your own development team for both targets.
4. Build and run the main app once, then test Quick Look in Finder.

The project has three main areas:

| Path | Purpose |
| --- | --- |
| [`InnerPeek/`](InnerPeek) | SwiftUI setup and permission guidance app. |
| [`InnerPeekQL/`](InnerPeekQL) | Quick Look extension and AppKit preview interface. |
| [`Shared/`](Shared) | Read-only folder and ZIP content providers plus shared models. |

When a `v*` tag is pushed, [GitHub Actions](https://github.com/fjd2004711/InnerPeek/actions) builds the DMG, generates `SHA256SUMS`, and publishes a GitHub Release.

## Contributing

Issues and pull requests are welcome. When reporting a bug, include your macOS version, InnerPeek version, file type, and reproducible steps. Please do not upload files containing private data.

For larger features, open an [issue](https://github.com/fjd2004711/InnerPeek/issues) first to discuss scope—especially for new archive formats or changes that may affect Quick Look launch time.

## License

InnerPeek is available under the [MIT License](LICENSE).
