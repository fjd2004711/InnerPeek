import Foundation

/// Interface strings for the preview, honouring the language chosen in settings.
/// With "system" the standard bundle lookup applies; otherwise the matching
/// `.lproj` is used and missing keys fall back to English, then to the key.
enum UILanguage {
    static func bundle(for locale: Locale?) -> Bundle {
        let base = Bundle(for: PreviewViewController.self)
        guard let locale else { return base }
        for tag in LanguageResolver.candidates(for: locale) {
            if let path = base.path(forResource: tag, ofType: "lproj"), let bundle = Bundle(path: path) { return bundle }
        }
        return base
    }
}

func localizedUI(_ key: String, comment: String = "") -> String {
    UILanguage.bundle(for: LocaleOverride.locale).localizedString(forKey: key, value: nil, table: nil)
}

/// Formats with the preview's language so counts and separators match the text.
func localizedFormat(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: LocaleOverride.effective, arguments: arguments)
}
