import Foundation
import UniformTypeIdentifiers

enum PreviewItemKind: Sendable, Hashable {
    case file
    case folder
}

struct PreviewItem: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let relativePath: String
    let kind: PreviewItemKind
    let size: Int64?
    let modifiedDate: Date?
    let contentTypeIdentifier: String?

    var isFolder: Bool { kind == .folder }

    // Outline rows are identified by their stable node ID. Hashing the
    // display name, relative path and date (the synthesized Hashable
    // implementation) makes AppKit's repeated row/AX lookups normalize and
    // hash strings unnecessarily.
    static func == (lhs: PreviewItem, rhs: PreviewItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(id: UUID = UUID(), name: String, relativePath: String, kind: PreviewItemKind,
         size: Int64?, modifiedDate: Date?, contentTypeIdentifier: String?) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modifiedDate = modifiedDate
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}
