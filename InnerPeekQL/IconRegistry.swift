import AppKit

/// Turns registry keys into images. This is the only place that touches AppKit
/// for logos; a missing key, asset or symbol degrades to a glyph and never throws.
final class IconRegistry {
    private let catalog: IconCatalog
    private let bundle: Bundle
    private var cache: [String: NSImage] = [:]

    init(catalog: IconCatalog = IconCatalog(), bundle: Bundle = Bundle(for: IconRegistry.self)) {
        self.catalog = catalog
        self.bundle = bundle
    }

    /// The brand logo for `key`, or `nil` when the key or its bundled SVG is unavailable.
    func brandImage(for key: String) -> NSImage? {
        if let cached = cache[key] { return cached }
        guard let entry = catalog.entry(for: key),
              let url = bundle.url(forResource: entry.asset, withExtension: "svg", subdirectory: "Icons/brands")
                ?? bundle.url(forResource: entry.asset, withExtension: "svg"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        // Coloured logos keep their brand colour; near-black ones are templates so Dark Mode can tint them.
        image.isTemplate = entry.monochrome
        cache[key] = image
        return image
    }

    /// Always returns an image: brand logo, else the SF Symbol for the fallback, else `folder`.
    func image(for identity: VisualIdentity) -> NSImage {
        if let key = identity.primaryIconKey, let image = brandImage(for: key) { return image }
        return symbol(IconCatalog.fallbackSymbol(for: identity.fallback)) ?? symbol("folder") ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
