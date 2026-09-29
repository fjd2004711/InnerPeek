import Foundation
import UniformTypeIdentifiers

final class FolderContentProvider: PreviewContentProvider, @unchecked Sendable {
    private let rootURL: URL
    private let lock = NSLock()
    private var isCancelled = false

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func loadRoot() async throws -> [PreviewItem] {
        try loadDirectory(at: rootURL, relativePrefix: "")
    }

    func loadChildren(of item: PreviewItem) async throws -> [PreviewItem] {
        guard item.isFolder else { throw PreviewContentError.notExpandable }
        try Task.checkCancellation()
        return try loadDirectory(at: rootURL.appendingPathComponent(item.relativePath), relativePrefix: item.relativePath)
    }

    func cancel() {
        lock.withLock { isCancelled = true }
    }


    private func loadDirectory(at url: URL, relativePrefix: String) throws -> [PreviewItem] {
        try Task.checkCancellation()
        guard !cancelled else { return [] }
        // Avoid contentTypeKey here: LaunchServices can synchronously consult
        // its database for every child and is visible as a click hitch in a
        // Quick Look remote view. The icon layer already classifies by
        // extension, while directory/size/date are cheap resource values.
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var result: [PreviewItem] = []
        result.reserveCapacity(urls.count)

        for childURL in urls {
            try Task.checkCancellation()
            guard !cancelled else { return result }
            let values = try childURL.resourceValues(forKeys: Set(keys))
            let isDirectory = values.isDirectory ?? false
            let relativePath = relativePrefix.isEmpty ? childURL.lastPathComponent : relativePrefix + "/" + childURL.lastPathComponent
            result.append(PreviewItem(
                name: childURL.lastPathComponent,
                relativePath: relativePath,
                kind: isDirectory ? .folder : .file,
                size: isDirectory ? nil : values.fileSize.map(Int64.init),
                modifiedDate: values.contentModificationDate,
                contentTypeIdentifier: nil
            ))
        }

        return result.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var cancelled: Bool {
        lock.withLock { isCancelled }
    }
}
