import Foundation

/// How the preview speaks. `system` follows the user's macOS language.
enum PreviewLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
}

enum PreviewIconStyle: String, CaseIterable, Sendable {
    case brandColor
    case monochrome
}

/// User preferences shared between the settings window (InnerPeek.app) and the
/// sandboxed Quick Look extension. They live in the app's preference domain; the
/// extension reads that domain through a read-only sandbox exception, so nothing
/// is sent anywhere and no background process is needed. Every value is validated
/// on read, so a hand-edited or corrupt preference can only fall back to defaults.
struct PreviewSettings: Equatable, Sendable {
    static let domain = "com.innerpeek.InnerPeek"

    enum Key {
        static let showSummary = "preview.showSummary"
        static let showInsights = "preview.showInsights"
        static let showTechStack = "preview.showTechStack"
        static let showBrandIcons = "preview.showBrandIcons"
        static let showHiddenFiles = "preview.showHiddenFiles"
        static let expandReasons = "preview.expandReasons"
        static let scanDepth = "analysis.scanDepth"
        static let maximumEntries = "analysis.maximumEntries"
        static let language = "appearance.language"
        static let iconStyle = "appearance.iconStyle"
    }

    static let depthRange = 1...4
    /// Offered limits; anything else is snapped to the nearest one.
    static let entryLimits = [500, 1_000, 2_000, 5_000, 10_000]

    var showSummary = true
    var showInsights = true
    var showTechStack = true
    var showBrandIcons = true
    var showHiddenFiles = false
    var expandReasons = false
    var scanDepth = 2
    var maximumEntries = 2_000
    var language = PreviewLanguage.system
    var iconStyle = PreviewIconStyle.brandColor

    static let standard = PreviewSettings()

    /// Reads the current preferences, always returning a valid configuration.
    static func load(domain: String = PreviewSettings.domain) -> PreviewSettings {
        CFPreferencesAppSynchronize(domain as CFString)
        func value(_ key: String) -> CFPropertyList? { CFPreferencesCopyAppValue(key as CFString, domain as CFString) }
        func flag(_ key: String, _ fallback: Bool) -> Bool { (value(key) as? NSNumber)?.boolValue ?? fallback }
        func integer(_ key: String) -> Int? { (value(key) as? NSNumber)?.intValue }

        var settings = PreviewSettings()
        settings.showSummary = flag(Key.showSummary, settings.showSummary)
        settings.showInsights = flag(Key.showInsights, settings.showInsights)
        settings.showTechStack = flag(Key.showTechStack, settings.showTechStack)
        settings.showBrandIcons = flag(Key.showBrandIcons, settings.showBrandIcons)
        settings.showHiddenFiles = flag(Key.showHiddenFiles, settings.showHiddenFiles)
        settings.expandReasons = flag(Key.expandReasons, settings.expandReasons)
        settings.scanDepth = integer(Key.scanDepth).map(clampDepth) ?? settings.scanDepth
        settings.maximumEntries = integer(Key.maximumEntries).map(snapEntries) ?? settings.maximumEntries
        settings.language = (value(Key.language) as? String).flatMap(PreviewLanguage.init(rawValue:)) ?? .system
        settings.iconStyle = (value(Key.iconStyle) as? String).flatMap(PreviewIconStyle.init(rawValue:)) ?? .brandColor
        return settings
    }

    static func clampDepth(_ value: Int) -> Int { min(max(value, depthRange.lowerBound), depthRange.upperBound) }

    static func snapEntries(_ value: Int) -> Int {
        entryLimits.min { abs($0 - value) < abs($1 - value) } ?? standard.maximumEntries
    }
}

/// The language the preview was asked to use, applied to every text lookup. It is
/// set once when a preview starts, before any analysis runs.
enum LocaleOverride {
    nonisolated(unsafe) static var locale: Locale?
    static var effective: Locale { locale ?? .current }

    /// File sizes in the chosen language. `ByteCountFormatter` cannot take a locale, so the
    /// format style is used instead.
    static func byteCount(_ size: Int64) -> String {
        ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false,
                             includesActualByteCount: false, locale: effective).format(size)
            // Finder writes "KB"; the format style says "kB".
            .replacingOccurrences(of: "kB", with: "KB")
    }
}

/// Sizes and dates follow the language chosen in Settings, not just the system locale, so an
/// English preview on a Chinese system does not show "字节" or "今天". Formatters are cached per
/// locale because creating a `DateFormatter` per table row would be wasteful.
enum UIFormatters {
    enum DateKind: String {
        case table, header, detail
    }

    private static let lock = NSLock()
    private static var cache: [String: Formatter] = [:]

    static func bytes(_ count: Int64) -> String { LocaleOverride.byteCount(count) }

    static func date(_ date: Date, _ kind: DateKind) -> String {
        let locale = LocaleOverride.effective
        let formatter: DateFormatter = cached("\(kind.rawValue)|\(locale.identifier)") {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = kind == .header ? .medium : .short
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = kind != .detail
            return formatter
        }
        return formatter.string(from: date)
    }

    private static func cached<T: Formatter>(_ key: String, make: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        if let existing = cache[key] as? T { return existing }
        let created = make()
        cache[key] = created
        return created
    }
}
