import Foundation

/// Loads InnerPeek's editable file-type knowledge base and indexes it by extension.
final class FileTypeRegistry: @unchecked Sendable {
    static let shared = FileTypeRegistry()

    let definitions: [FileTypeDefinition]
    private let definitionsByExtension: [String: FileTypeDefinition]
    private let definitionsByFilename: [String: FileTypeDefinition]

    convenience init() {
        let bundle = Bundle(for: FileTypeRegistry.self)
        let data = bundle.url(forResource: "file-types", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            ?? bundle.url(forResource: "file-types", withExtension: "json", subdirectory: "FileTypes")
                .flatMap { try? Data(contentsOf: $0) }
            ?? Data()
        self.init(data: data)
    }

    init(data: Data) {
        let decoded = (try? JSONDecoder().decode([FileTypeDefinition].self, from: data)) ?? []
        definitions = decoded

        var index: [String: FileTypeDefinition] = [:]
        var filenameIndex: [String: FileTypeDefinition] = [:]
        for definition in decoded {
            for fileExtension in definition.extensions {
                let normalized = Self.normalize(fileExtension)
                guard !normalized.isEmpty else { continue }
                // The first declaration wins, keeping accidental duplicate entries deterministic.
                if index[normalized] == nil {
                    index[normalized] = definition
                }
            }
            for filename in definition.filenames {
                let normalized = Self.normalizeFilename(filename)
                guard !normalized.isEmpty else { continue }
                if filenameIndex[normalized] == nil {
                    filenameIndex[normalized] = definition
                }
            }
        }
        definitionsByExtension = index
        definitionsByFilename = filenameIndex
    }

    func definition(forFileName fileName: String) -> FileTypeDefinition? {
        definitionsByFilename[Self.normalizeFilename(fileName)]
    }

    func definition(forExtension fileExtension: String?) -> FileTypeDefinition? {
        guard let fileExtension else { return nil }
        return definitionsByExtension[Self.normalize(fileExtension)]
    }

    static func normalize(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    static func normalizeFilename(_ filename: String) -> String {
        filename.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
