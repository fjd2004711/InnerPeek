import Foundation

protocol PreviewContentProvider: AnyObject, Sendable {
    func loadRoot() async throws -> [PreviewItem]
    func loadRoot(onUpdate: @escaping @Sendable ([PreviewItem]) -> Void) async throws -> [PreviewItem]
    func loadChildren(of item: PreviewItem) async throws -> [PreviewItem]
    func cancel()
}

extension PreviewContentProvider {
    func loadRoot(onUpdate: @escaping @Sendable ([PreviewItem]) -> Void) async throws -> [PreviewItem] {
        let items = try await loadRoot()
        onUpdate(items)
        return items
    }
}

enum PreviewContentError: LocalizedError {
    case notExpandable
    case invalidArchive
    case unsupportedArchive

    var errorDescription: String? {
        switch self {
        case .notExpandable: return "This item cannot be expanded."
        case .invalidArchive: return "The archive is damaged or uses an unsupported ZIP layout."
        case .unsupportedArchive: return "This archive format is not supported."
        }
    }
}
