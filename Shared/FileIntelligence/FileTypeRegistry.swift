import Foundation

/// Loads InnerPeek's editable file-type knowledge base and indexes it by extension.
final class FileTypeRegistry: @unchecked Sendable {
    static let shared = FileTypeRegistry()

    let definitions: [FileTypeDefinition]
    private let definitionsByExtension: [String: FileTypeDefinition]
    private let definitionsByFilename: [String: FileTypeDefinition]
    private let filenamePatterns: [(pattern: [Character], definition: FileTypeDefinition)]

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
        var patterns: [(pattern: [Character], definition: FileTypeDefinition)] = []
        for definition in decoded {
            for pattern in definition.filenamePatterns {
                let normalized = Self.normalizeFilename(pattern)
                if !normalized.isEmpty { patterns.append((Array(normalized), definition)) }
            }
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
        filenamePatterns = patterns
    }

    func definition(forFileName fileName: String) -> FileTypeDefinition? {
        let normalized = Self.normalizeFilename(fileName)
        if let exact = definitionsByFilename[normalized] { return exact }
        guard !filenamePatterns.isEmpty else { return nil }
        let characters = Array(normalized)
        return filenamePatterns.first { Self.glob($0.pattern, characters) }?.definition
    }

    /// `*` matches any run of characters; everything else matches literally.
    private static func glob(_ pattern: [Character], _ name: [Character]) -> Bool {
        var pi = 0, ni = 0, star = -1, mark = 0
        while ni < name.count {
            if pi < pattern.count, pattern[pi] == name[ni] { pi += 1; ni += 1 }
            else if pi < pattern.count, pattern[pi] == "*" { star = pi; mark = ni; pi += 1 }
            else if star != -1 { pi = star + 1; mark += 1; ni = mark }
            else { return false }
        }
        while pi < pattern.count, pattern[pi] == "*" { pi += 1 }
        return pi == pattern.count
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
