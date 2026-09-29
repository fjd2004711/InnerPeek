# InnerPeek

InnerPeek is a macOS Quick Look extension for fast folder and ZIP tree previews.

## Install the free, ad-hoc build

This project is distributed without a paid Apple Developer account. The release is ad-hoc signed (not Developer ID notarized), so macOS may require the first launch to be approved in **System Settings → Privacy & Security → Open Anyway**.

1. Download the release ZIP from GitHub Releases.
2. Unzip it and move `InnerPeek.app` to `/Applications`.
3. If macOS shows a quarantine warning, run:

```sh
xattr -dr com.apple.quarantine /Applications/InnerPeek.app
```

4. Open Finder and press Space on a folder or ZIP file.

The Quick Look extension is on-demand; the main app does not stay resident.

## Verify the download

Compare the SHA-256 hash with `SHA256SUMS` from the same release:

```sh
shasum -a 256 InnerPeek-1.0.2-adhoc.zip
```

## Permission guide

InnerPeek uses the standard macOS sandbox and only reads the item that Finder asks it to preview. Normal folders work without extra setup. macOS may protect Desktop, Documents, Downloads, Mail data, and other locations; for those locations, optionally enable **System Settings → Privacy & Security → Full Disk Access**, click **+**, choose `/Applications/InnerPeek.app`, and turn it on. Reopen Finder after changing the setting.

macOS does not allow an app to grant itself Full Disk Access. InnerPeek never runs in the background and never uploads or modifies your files.
