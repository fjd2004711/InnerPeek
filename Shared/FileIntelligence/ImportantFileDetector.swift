import Foundation

enum ImportantFileReason: String, Sendable, Hashable {
    case documentation
    case projectManifest
    case projectConfiguration
    case entryPoint
    case license
    case model
    case database
    case scientificData
}

struct ImportantFile: Sendable, Hashable {
    let file: AnalyzedFile
    let reason: ImportantFileReason
    let priority: Int
}

/// Deterministically ranks useful individual files from FolderAnalysis's
/// already-discovered bounded file population. It never reads folders itself.
struct ImportantFileDetector: Sendable {
    static let maximumResults = 5
    let registry: FileTypeRegistry

    init(registry: FileTypeRegistry = .shared) {
        self.registry = registry
    }

    func detect(in analysis: FolderAnalysis) -> [ImportantFile] {
        analysis.analyzedFiles.compactMap(candidate(for:))
            .sorted(by: sort)
            .prefix(Self.maximumResults)
            .map { $0 }
    }

    private func candidate(for file: AnalyzedFile) -> ImportantFile? {
        let filenameDefinition = registry.definition(forFileName: file.intelligence.fileName)
        let typeDefinition = filenameDefinition ?? registry.definition(forExtension: file.intelligence.fileExtension)
        if let importance = typeDefinition?.importance,
           let reason = ImportantFileReason(rawValue: importance.reason) {
            return ImportantFile(file: file, reason: reason, priority: importance.priority)
        }

        let filename = FileTypeRegistry.normalizeFilename(file.intelligence.fileName)
        if filename.hasPrefix("main.") || filename.hasPrefix("index.") {
            return ImportantFile(file: file, reason: .entryPoint, priority: 70)
        }

        switch file.intelligence.category {
        case .aiModel:
            return ImportantFile(file: file, reason: .model, priority: 75)
        case .database:
            return ImportantFile(file: file, reason: .database, priority: 72)
        case .scientificData:
            return ImportantFile(file: file, reason: .scientificData, priority: 68)
        default:
            return nil
        }
    }

    private func sort(_ lhs: ImportantFile, _ rhs: ImportantFile) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.file.intelligence.fileName != rhs.file.intelligence.fileName {
            return lhs.file.intelligence.fileName.localizedStandardCompare(rhs.file.intelligence.fileName) == .orderedAscending
        }
        return lhs.file.url.path < rhs.file.url.path
    }
}
