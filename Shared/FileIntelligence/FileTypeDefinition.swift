import Foundation

struct FileTypeDefinition: Codable, Sendable, Hashable {
    struct LocalizedText: Codable, Sendable, Hashable {
        let english: String
        let simplifiedChinese: String

        enum CodingKeys: String, CodingKey {
            case english = "en"
            case simplifiedChinese = "zh-Hans"
        }

        func value(for locale: Locale = .current) -> String {
            let languageCode = locale.language.languageCode?.identifier ?? "en"
            return languageCode == "zh" ? simplifiedChinese : english
        }
    }

    let id: String
    let extensions: [String]
    let category: FileCategory
    let name: LocalizedText
    let description: LocalizedText
    let purposeText: LocalizedText?
    let isText: Bool
    let isBinary: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case extensions
        case category
        case name
        case description
        case purposeText = "purpose"
        case isText
        case isBinary
    }

    var displayName: String { name.value() }
    var localizedDescription: String { description.value() }
    var purpose: String? { purposeText?.value() }

    func displayName(for locale: Locale) -> String { name.value(for: locale) }
    func localizedDescription(for locale: Locale) -> String { description.value(for: locale) }
    func purpose(for locale: Locale) -> String? { purposeText?.value(for: locale) }
}
