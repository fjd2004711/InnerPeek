import Foundation

/// A compact, already-formatted property that can be displayed without the UI
/// knowing how a particular file format was inspected.
struct MetadataItem: Sendable, Hashable {
    enum Key: String, Sendable, Hashable {
        case dimensions, duration, pages, columns, delimiter, jsonShape
        case notebookCells, codeCells, markdownCells, kernel, language
        case references, shape, dataType, arrays, tensors, metadataKeys

        var localizationKey: String { "metadata_\(rawValue)" }
    }

    let key: Key
    let value: String
    let priority: Int
}

protocol MetadataExtracting: Sendable {
    func supports(_ intelligence: FileIntelligence) -> Bool
    func extract(from url: URL, intelligence: FileIntelligence) async throws -> [MetadataItem]
}
