<p align="center">
  <img src="InnerPeek/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="104" alt="InnerPeek icon">
</p>

<h1 align="center">InnerPeek</h1>

<p align="center"><a href="README.md">简体中文</a> · <a href="README_EN.md">English</a></p>

<p align="center"><strong>Make Finder Quick Look understand folders and ZIP archives.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-Apple%20Silicon%20%7C%20Intel-151515?logo=apple&logoColor=white" alt="macOS Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/Quick%20Look-native-24C8DB" alt="Native Quick Look extension">
  <img src="https://img.shields.io/badge/ZIP-zero%20extraction-4C8DFF" alt="ZIP browsing without extraction">
  <img src="https://img.shields.io/badge/License-MIT-60B932" alt="MIT license">
</p>

InnerPeek is a local macOS Quick Look extension. Select a folder or ZIP archive in Finder, press Space, and browse its contents as a tree in the native preview window.

## What it does

Finder previews images, documents, and videos, but it does not show the folder hierarchy or the files inside a ZIP. InnerPeek makes that content easy to inspect without changing your Finder workflow.

| Feature | Details |
| --- | --- |
| Folder tree preview | Browse directory levels, file sizes, and modification dates in the native Quick Look window. |
| ZIP browsing without extraction | Reads the ZIP central directory directly. No extracted copy is written to disk. |
| Click a row to expand or collapse | Click anywhere on a folder row; the native macOS disclosure triangle remains available. |
| Real file icons | Uses system file-type icons for disk items and cached type icons for items inside ZIP archives. |
| Native interactions | Built with AppKit `NSOutlineView`, with keyboard, trackpad, and Quick Look animation support. |
| Minimal background use | The companion app provides setup guidance; the Quick Look extension runs on demand. |

## Get started

1. Download the latest DMG from [GitHub Releases](../../releases).
2. Open the DMG and drag `InnerPeek.app` to **Applications**.
3. Open InnerPeek once to review its permission guidance. Ordinary folders need no additional access.
4. In Finder, select a folder or ZIP archive and press Space.
5. Click a folder row or its disclosure triangle to expand or collapse it.

InnerPeek does not open files, extract archives, or modify your original content.

## Preview examples

The repository includes a reproducible [demo folder](docs/demo/InnerPeek-Demo). Its nested directories contain PDF, JSON, Swift, JavaScript, Python, HTML, CSS, XML, YAML, CSV, RTF, LOG, TXT, Markdown, and PNG files, plus Word (DOCX), Excel (XLSX), and PowerPoint (PPTX) documents. The [ZIP demo](docs/demo/InnerPeek-Demo/InnerPeek-ZIP-Demo.zip) contains the same sample content for comparison.

These screenshots show the Finder Quick Look window with a nested folder expanded. The folder preview is on the left; the ZIP preview is on the right.

| Folder preview | ZIP preview |
| --- | --- |
| <img src="docs/demo/innerpeek-folder-light-preview.png" width="420" alt="Folder preview with Office documents and multiple file types"> | <img src="docs/demo/innerpeek-zip-light-preview.png" width="420" alt="ZIP preview with Office documents and multiple file types"> |

## macOS permissions

Ordinary folders and items Finder passes to Quick Look do not require Full Disk Access. To preview Desktop, Documents, Downloads, Mail data, or other macOS-protected locations, open:

**System Settings → Privacy & Security → Full Disk Access → “+” → select `/Applications/InnerPeek.app` → enable the switch**

Return to Finder and open the preview again. InnerPeek checks access by attempting to read protected locations; no manual confirmation button is needed.

macOS requires you to approve Full Disk Access. InnerPeek uses access only to read content you choose to preview; it does not upload or modify your files.

## Why it is fast

- Folder browsing requests only the directory entries and metadata needed for the preview.
- ZIP browsing reads the central directory and creates no extracted copy or temporary files.
- Subfolders load on demand and use the native outline view for expansion and collapse.
- System icons are resolved asynchronously and cached to keep Launch Services work off the Quick Look main thread.
- Release builds use Swift whole-module optimization and support Apple Silicon and Intel Macs.

## Performance comparison

InnerPeek is designed for a quick look at folder and archive contents. The comparison below describes the implementation approach:

| Scenario | InnerPeek | Finder Quick Look | Extract first | Archive utility |
| --- | --- | --- | --- | --- |
| Browse folder hierarchy | Native tree, subfolders loaded on demand | Usually shows a folder summary | Requires a copy to be created | Full-featured, with a heavier startup path |
| Inspect a ZIP directory | Reads the central directory without extraction | Usually cannot expand the archive tree | Requires full or partial extraction | May create temporary indexes or caches |
| First interaction | Loads the current level; resolves icons asynchronously | Starts quickly, with limited detail | Depends on extraction size | Depends on indexing and caching |
| Disk usage | No extracted copy | No extra copy | Can approach the archive’s uncompressed size | May use caches or temporary files |
| Best for | Quickly checking contents and locating items | Viewing metadata for one file | Editing or using extracted files in bulk | Extracting, compressing, validating, and converting |

InnerPeek avoids full extraction, synchronous icon lookup, and loading every directory level before the first interaction.

## Planned improvements

The roadmap prioritizes a lightweight, reliable Quick Look experience:

- **Deeper on-demand previews:** Enter nested folders without closing Quick Look and return with Space.
- **More archive formats:** Add directory previews for TAR, GZIP, and 7Z where system security boundaries allow.
- **More efficient icon caching:** Add layered extension, UTI, and system-icon caches for large folders.
- **Large-directory virtualization:** Load visible items or pages on demand to control memory use and first-screen latency.
- **Optional preview settings:** Configure columns, sorting, and hidden-file visibility while keeping Finder-style defaults.
- **Accessibility:** Improve VoiceOver, keyboard navigation, Dynamic Type, and localization.

New capabilities will preserve on-demand operation and leave original files unchanged.

## Downloads and verification

The current free distribution uses an Ad-Hoc signature and is not notarized with a Developer ID certificate. If macOS blocks the app, approve it in **System Settings → Privacy & Security**, or—after verifying the download—run:

```sh
xattr -dr com.apple.quarantine /Applications/InnerPeek.app
```

Verify the release DMG:

```sh
shasum -a 256 InnerPeek-1.0.6-macOS.dmg
```

The matching hash is included in `SHA256SUMS` in the same release.

Each push to `main` triggers a GitHub Actions build that creates a macOS DMG and checksum file. Download this 30-day build artifact from the run’s **Artifacts** section on the [Actions page](../../actions/workflows/macos-build.yml). Pushing a `v*` version tag triggers a fresh build from that tagged commit; GitHub Actions then publishes the DMG and `SHA256SUMS` to GitHub Releases. Open the DMG and drag InnerPeek to **Applications** to install it.

## FAQ

<details>
<summary><strong>Why can’t I see the contents of a folder?</strong></summary>

Make sure Finder passed the folder itself to Quick Look. Protected locations require Full Disk Access for InnerPeek; after granting access, reopen the preview.

</details>

<details>
<summary><strong>Does InnerPeek extract ZIP archives?</strong></summary>

No. InnerPeek reads only the ZIP directory index. Items inside the archive have no real filesystem paths, so the preview shows their type icons without starting an external extraction process.

</details>

<details>
<summary><strong>Why is the first preview slower than later previews?</strong></summary>

The first preview initializes the Quick Look extension and reads directory data. Folder contents and icons are then loaded on demand and can benefit from system and application caches.

</details>

<details>
<summary><strong>Why does macOS say it cannot verify the developer?</strong></summary>

InnerPeek is distributed without a paid Apple Developer ID certificate, so the app cannot be Developer ID-signed or notarized. Download it from this repository and approve it in macOS Privacy & Security settings.

</details>

## Privacy and security

- Directory reads, ZIP index parsing, and icon processing happen locally.
- InnerPeek does not connect to a service, upload files, or modify original content.
- It does not run as a login item or persistent background service.
- The Quick Look extension uses App Sandbox. The companion app runs when you open its setup window and checks permissions through actual read attempts.

## Project and feedback

- Project: [github.com/fjd2004711/InnerPeek](https://github.com/fjd2004711/InnerPeek)
- Downloads: [GitHub Releases](../../releases)
- Issues: Include your macOS version, file type, and reproduction steps. Do not upload private files or protected directory contents.

## License

The project is licensed under the [MIT License](LICENSE).
