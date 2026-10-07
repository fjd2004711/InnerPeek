import Foundation

/// Chooses which translation to show. The order is: the user's language with its
/// script and region, the bare language, a sibling script (Traditional Chinese
/// falls back to Simplified, which is far more readable than English), then English.
enum LanguageResolver {
    static func candidates(for locale: Locale) -> [String] {
        let language = locale.language.languageCode?.identifier ?? "en"
        var script = locale.language.script?.identifier
        let region = locale.region?.identifier ?? locale.language.region?.identifier
        if language == "zh", script == nil {
            script = ["TW", "HK", "MO"].contains(region ?? "") ? "Hant" : "Hans"
        }
        var result: [String] = []
        func add(_ tag: String) { if !result.contains(tag) { result.append(tag) } }
        if let script, let region { add("\(language)-\(script)-\(region)") }
        if let script { add("\(language)-\(script)") }
        if let region { add("\(language)-\(region)") }
        add(language)
        if language == "zh" { add(script == "Hant" ? "zh-Hans" : "zh-Hant") }
        add("en")
        return result
    }
}

/// One user-visible sentence in any number of languages, keyed by BCP 47 tag.
/// English is the source language and the final fallback, so a translation can
/// be added or left out without touching code.
struct LocalizedText: Codable, Sendable, Hashable {
    let translations: [String: String]

    init(translations: [String: String]) { self.translations = translations }

    /// Kept for call sites that still build a two-language pair.
    init(english: String, simplifiedChinese: String? = nil) {
        var table = ["en": english]
        if let simplifiedChinese { table["zh-Hans"] = simplifiedChinese }
        translations = table
    }

    init(from decoder: Decoder) throws {
        translations = try decoder.singleValueContainer().decode([String: String].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(translations)
    }

    var english: String { translations["en"] ?? translations.keys.sorted().first.flatMap { translations[$0] } ?? "" }
    var simplifiedChinese: String { translations["zh-Hans"] ?? english }

    func value(for locale: Locale = LocaleOverride.effective, arguments: [String] = []) -> String {
        let template = LanguageResolver.candidates(for: locale).lazy.compactMap { translations[$0] }.first ?? english
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: locale, arguments: arguments.map { $0 as CVarArg })
    }

    /// Fills `%@` placeholders in every language with the same arguments.
    func formatted(_ arguments: [String]) -> LocalizedText {
        LocalizedText(translations: translations.mapValues {
            String(format: $0, arguments: arguments.map { $0 as CVarArg })
        })
    }

    /// Joins parts language by language (falling back to English per part).
    static func joined(_ parts: [LocalizedText], separator: String = " · ") -> LocalizedText {
        let tags = Set(parts.flatMap { $0.translations.keys }).union(["en"])
        return LocalizedText(translations: Dictionary(uniqueKeysWithValues: tags.map { tag in
            (tag, parts.map { $0.translations[tag] ?? $0.english }.joined(separator: separator))
        }))
    }

    /// Fills the single `%@` of each language with the names written in that same
    /// language (falling back to English), joined with that language's separator.
    static func fill(_ template: LocalizedText, names: [LocalizedText]) -> LocalizedText {
        LocalizedText(translations: Dictionary(uniqueKeysWithValues: template.translations.map { tag, text in
            let separator = ["zh", "ja"].contains(String(tag.prefix(2))) ? "、" : ", "
            let joined = names.map { $0.translations[tag] ?? $0.english }.joined(separator: separator)
            return (tag, text.replacingOccurrences(of: "%@", with: joined))
        }))
    }
}

typealias InsightLocalizedText = LocalizedText

/// Translations for messages written in English inside the code, looked up by
/// their English text (gettext style). Missing entries simply show English.
final class MessageCatalog: @unchecked Sendable {
    static let shared = MessageCatalog()

    private struct Document: Decodable { let messages: [String: [String: String]] }
    private let table: [String: [String: String]]

    init(data: Data? = nil) {
        let bundled = Bundle(for: MessageCatalog.self).url(forResource: "messages", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Knowledge/messages.json")
        table = (data ?? bundled ?? (try? Data(contentsOf: sourceURL))).flatMap {
            try? JSONDecoder().decode(Document.self, from: $0)
        }?.messages ?? [:]
    }

    func text(_ english: String) -> LocalizedText {
        var translations = table[english] ?? [:]
        translations["en"] = english
        return LocalizedText(translations: translations)
    }

    func string(_ english: String, locale: Locale = LocaleOverride.effective) -> String {
        text(english).value(for: locale)
    }
}
