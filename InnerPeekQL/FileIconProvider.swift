import AppKit
import UniformTypeIdentifiers

final class FileIconProvider: @unchecked Sendable {
    static let shared = FileIconProvider()
    private let cache = NSCache<NSString, NSImage>()

    func prewarm() {
        let symbols = ["folder.fill", "doc", "doc.text", "doc.richtext", "photo", "archivebox",
                       "chevron.left.forwardslash.chevron.right", "curlybraces", "film", "waveform"]
        for symbol in symbols {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                cache.setObject(image, forKey: ("symbol:" + symbol) as NSString)
            }
        }
        if let folder = systemFolderIcon() {
            cache.setObject(folder, forKey: "type:\(UTType.folder.identifier)" as NSString)
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        if let cached = cache.object(forKey: ("symbol:" + name) as NSString) { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if let image { cache.setObject(image, forKey: ("symbol:" + name) as NSString) }
        return image
    }

    func icon(for item: PreviewItem) -> NSImage {
        let extensionName = (item.name as NSString).pathExtension
        let key = (item.isFolder ? "folder:" : "file:") + (item.contentTypeIdentifier ?? extensionName)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image: NSImage
        if item.isFolder {
            image = systemFolderIcon()
                ?? symbol("folder.fill")
                ?? NSImage(size: NSSize(width: 18, height: 18))
        } else {
            // NSWorkspace icon resolution can synchronously hit LaunchServices
            // and stall Quick Look while a row is being selected. Use semantic
            // SF Symbols for the hot path; they are local and deterministic.
            let symbol: String
            switch (item.contentTypeIdentifier ?? "").lowercased() {
            case let value where value.contains("image"): symbol = "photo"
            case let value where value.contains("movie") || value.contains("video"): symbol = "film"
            case let value where value.contains("audio"): symbol = "waveform"
            case let value where value.contains("pdf"): symbol = "doc.richtext"
            case let value where value.contains("archive") || ["zip", "rar", "7z"].contains(extensionName.lowercased()): symbol = "archivebox"
            case let value where value.contains("json"): symbol = "curlybraces"
            case let value where value.contains("source") || value.contains("script"): symbol = "chevron.left.forwardslash.chevron.right"
            case let value where value.contains("text") || value.contains("source-code"): symbol = "doc.text"
            default:
                switch extensionName.lowercased() {
                case "swift", "m", "mm", "h", "c", "cpp", "js", "ts", "py", "rb", "go", "rs", "sh":
                    symbol = "chevron.left.forwardslash.chevron.right"
                case "json", "plist", "yaml", "yml": symbol = "curlybraces"
                case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff": symbol = "photo"
                case "mp4", "mov", "m4v", "avi": symbol = "film"
                case "mp3", "m4a", "wav", "flac": symbol = "waveform"
                default: symbol = "doc"
                }
            }
            image = self.symbol(symbol)
                ?? NSImage(size: NSSize(width: 18, height: 18))
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Resolve a real Finder icon off the preview's hot path. This may consult
    /// LaunchServices, so callers must invoke it from a utility task and only
    /// for visible on-disk rows. ZIP entries intentionally never use it.
    func realIcon(at url: URL) -> NSImage {
        let key = ("real:" + url.path) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Resolve the system icon for a file *type* without requiring an
    /// on-disk file. This is the ZIP fast path: archive entries are metadata
    /// only, so we never extract them or create temporary files just to obtain
    /// an icon. The result is cached once per UTI/extension.
    func typeIcon(for item: PreviewItem) -> NSImage {
        // ZIP directories are metadata-only entries and have no filename
        // extension. Passing an empty UTI to NSWorkspace can return a blank
        // image, so resolve every archive folder through the canonical folder
        // UTI instead of treating its name as a file type.
        if item.isFolder {
            let key = "type:" + UTType.folder.identifier
            if let cached = cache.object(forKey: key as NSString) { return cached }
            let image = systemFolderIcon()
                ?? NSWorkspace.shared.icon(for: .folder)
            cache.setObject(image, forKey: key as NSString)
            return image
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        let contentType = UTType(filenameExtension: ext) ?? .data
        let key = ("type:" + contentType.identifier) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(for: contentType)
        cache.setObject(image, forKey: key)
        return image
    }

    private func systemFolderIcon() -> NSImage? {
        // NSImage.folderName is the Finder/AppKit resource, rather than an
        // SF Symbol template. Keeping it non-template preserves the native
        // folder color inside Quick Look's vibrancy view.
        let image = NSImage(named: NSImage.folderName)
        image?.isTemplate = false
        return image
    }
}
