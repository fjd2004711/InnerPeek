import Foundation

struct FileTypeDefinition: Codable, Sendable, Hashable {
    struct Importance: Codable, Sendable, Hashable {
        let reason: String
        let priority: Int
    }
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
    let filenames: [String]
    let category: FileCategory
    let roles: [SemanticRole]
    let name: LocalizedText
    let description: LocalizedText
    let purposeText: LocalizedText?
    let isText: Bool
    let isBinary: Bool
    let importance: Importance?

    enum CodingKeys: String, CodingKey {
        case id
        case extensions
        case filenames
        case category
        case roles
        case name
        case description
        case purposeText = "purpose"
        case isText
        case isBinary
        case importance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        extensions = try container.decodeIfPresent([String].self, forKey: .extensions) ?? []
        filenames = try container.decodeIfPresent([String].self, forKey: .filenames) ?? []
        category = try container.decode(FileCategory.self, forKey: .category)
        roles = try container.decodeIfPresent([SemanticRole].self, forKey: .roles) ?? []
        name = try container.decode(LocalizedText.self, forKey: .name)
        description = try container.decode(LocalizedText.self, forKey: .description)
        purposeText = try container.decodeIfPresent(LocalizedText.self, forKey: .purposeText)
        isText = try container.decode(Bool.self, forKey: .isText)
        isBinary = try container.decode(Bool.self, forKey: .isBinary)
        importance = try container.decodeIfPresent(Importance.self, forKey: .importance)
    }

    var displayName: String { name.value() }
    var localizedDescription: String { description.value() }
    var purpose: String? { purposeText?.value() }

    func displayName(for locale: Locale) -> String { name.value(for: locale) }
    func localizedDescription(for locale: Locale) -> String { description.value(for: locale) }
    func purpose(for locale: Locale) -> String? { purposeText?.value(for: locale) }
}
