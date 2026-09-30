import Foundation

/// Reads ZIP central-directory metadata only. No entry data is opened or written.
final class ZIPContentProvider: PreviewContentProvider, @unchecked Sendable {
    private struct Node {
        let id: UUID
        let name: String
        let parent: Int
        var kind: PreviewItemKind
        var size: Int64?
        var date: Date?
        var children: [Int]
        var isSorted: Bool
    }

    private struct ArchiveEntry: Sendable, Hashable {
        let path: String
        let isDirectory: Bool
        let logicalSize: Int64?
        let compressedSize: Int64?
        let modifiedDate: Date?
    }

    private let archiveURL: URL
    private let lock = NSLock()
    private var cancelled = false
    private var parsed = false
    private var nodes: [Node] = []
    private var archiveEntries: [ArchiveEntry] = []

    static let semanticMaximumDepth = 2
    static let semanticMaximumEntries = 2_000

    init(archiveURL: URL) { self.archiveURL = archiveURL }

    func loadRoot() async throws -> [PreviewItem] {
        try parseIfNeeded(onRootUpdate: nil)
        return children(ofNodeIndex: 0)
    }

    func loadRoot(onUpdate: @escaping @Sendable ([PreviewItem]) -> Void) async throws -> [PreviewItem] {
        try parseIfNeeded(onRootUpdate: onUpdate)
        return children(ofNodeIndex: 0)
    }

    func loadChildren(of item: PreviewItem) async throws -> [PreviewItem] {
        guard item.isFolder else { throw PreviewContentError.notExpandable }
        try Task.checkCancellation()
        try parseIfNeeded(onRootUpdate: nil)
        return children(ofNodeID: item.id)
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    /// Produces the same bounded FolderAnalysis consumed by relationship and insight engines.
    /// Only central-directory metadata is read; no archive entry is extracted or decompressed.
    func semanticAnalysis(
        recognizer: FileIntelligenceRecognizer = FileIntelligenceRecognizer(),
        maximumDepth: Int = ZIPContentProvider.semanticMaximumDepth,
        maximumEntries: Int = ZIPContentProvider.semanticMaximumEntries
    ) throws -> FolderAnalysis {
        try parseIfNeeded(onRootUpdate: nil)
        let entries = lock.withLock { archiveEntries }
        var selected: [ContentEntry] = []
        var selectedPaths = Set<String>()
        var reachedLimits = Set<FolderAnalysisLimit>()

        func isHidden(_ component: String) -> Bool {
            component.hasPrefix(".") && component != ".dockerignore"
        }
        func isIgnored(_ component: String) -> Bool {
            [".git", "node_modules", "DerivedData", "build", "dist", "target", ".venv", "venv", "__pycache__", ".cache"].contains(component)
        }
        func addDirectory(_ path: String) {
            guard !path.isEmpty, selectedPaths.insert(path).inserted else { return }
            let name = (path as NSString).lastPathComponent
            selected.append(ContentEntry(url: URL(fileURLWithPath: path), relativePath: path, name: name,
                                         fileExtension: nil, isDirectory: true, logicalSize: nil,
                                         compressedSize: nil, modifiedDate: nil, sourceKind: .zip))
        }

        for entry in entries.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            let path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty else { continue }
            let components = path.split(separator: "/").map(String.init)
            guard components.count <= maximumDepth else {
                reachedLimits.insert(.maximumDepth)
                continue
            }
            guard !components.contains(where: isHidden), !components.dropLast().contains(where: isIgnored) else { continue }
            if selected.count >= maximumEntries {
                reachedLimits.insert(.maximumEntries)
                break
            }
            for index in 1..<components.count { addDirectory(components.prefix(index).joined(separator: "/")) }
            guard selectedPaths.insert(path).inserted else { continue }
            let url = URL(fileURLWithPath: path)
            selected.append(ContentEntry(url: url, relativePath: path, name: components.last ?? path,
                                         fileExtension: FileTypeRegistry.normalize(url.pathExtension).isEmpty ? nil : FileTypeRegistry.normalize(url.pathExtension),
                                         isDirectory: entry.isDirectory, logicalSize: entry.logicalSize,
                                         compressedSize: entry.compressedSize, modifiedDate: entry.modifiedDate, sourceKind: .zip))
        }
        let state: FolderAnalysisScanState = reachedLimits.isEmpty ? .complete : .partial(reachedLimits)
        return FolderAnalysis(snapshot: ContentSnapshot(entries: selected, scanState: state, sourceKind: .zip), recognizer: recognizer)
    }


    private func parseIfNeeded(onRootUpdate: (@Sendable ([PreviewItem]) -> Void)?) throws {
        let done = lock.withLock { parsed }
        if done { return }
        try Task.checkCancellation()
        guard !isCancelled else { return }

        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: archiveURL) } catch { throw error }
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        let tailLength = min(fileSize, 65_557)
        try handle.seek(toOffset: fileSize - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let eocd = findSignature(0x06054b50, in: tail) else { throw PreviewContentError.invalidArchive }
        guard eocd + 22 <= tail.count else { throw PreviewContentError.invalidArchive }
        let count = Int(readUInt16(tail, eocd + 10))
        let diskNumber = readUInt16(tail, eocd + 4)
        let directoryDisk = readUInt16(tail, eocd + 6)
        let countOnDisk = Int(readUInt16(tail, eocd + 8))
        let directorySize = UInt64(readUInt32(tail, eocd + 12))
        let directoryOffset = UInt64(readUInt32(tail, eocd + 16))
        guard diskNumber == 0, directoryDisk == 0, countOnDisk == count else { throw PreviewContentError.unsupportedArchive }
        guard count != 0xffff, directorySize != 0xffffffff, directoryOffset != 0xffffffff else {
            throw PreviewContentError.unsupportedArchive
        }
        guard directorySize <= UInt64(Int.max), directoryOffset <= fileSize,
              directorySize <= fileSize - directoryOffset else { throw PreviewContentError.invalidArchive }
        try handle.seek(toOffset: directoryOffset)
        let central = try handle.read(upToCount: Int(directorySize)) ?? Data()
        var parsedNodes: [Node] = [Node(id: UUID(), name: "", parent: -1, kind: .folder, size: nil, date: nil, children: [], isSorted: true)]
        var parsedArchiveEntries: [ArchiveEntry] = []
        var parsedIndexByPath: [String: Int] = ["": 0]
        var cursor = 0
        var processedEntries = 0
        while cursor + 46 <= central.count && processedEntries < count {
            try Task.checkCancellation(); guard !isCancelled else { return }
            guard readUInt32(central, cursor) == 0x02014b50 else { throw PreviewContentError.invalidArchive }
            let size = UInt64(readUInt32(central, cursor + 24))
            let compressedSize = UInt64(readUInt32(central, cursor + 20))
            let nameLength = Int(readUInt16(central, cursor + 28))
            let extraLength = Int(readUInt16(central, cursor + 30))
            let commentLength = Int(readUInt16(central, cursor + 32))
            let end = cursor + 46 + nameLength + extraLength + commentLength
            guard end <= central.count else { throw PreviewContentError.invalidArchive }
            let nameRange = (cursor + 46)..<(cursor + 46 + nameLength)
            let name = String(decoding: central[nameRange], as: UTF8.self)
            let isDirectory = name.hasSuffix("/") || (readUInt32(central, cursor + 38) & 0x10) != 0
            // Keep the central-directory name intact. `insertNode` already ignores
            // repeated separators; rebuilding the whole path here was a large
            // temporary allocation for archives with many entries.
            let clean = name.last == "/" ? String(name.dropLast()) : name
            if !clean.isEmpty {
                parsedArchiveEntries.append(ArchiveEntry(
                    path: clean,
                    isDirectory: isDirectory,
                    logicalSize: isDirectory ? nil : (size <= UInt64(Int64.max) ? Int64(size) : nil),
                    compressedSize: isDirectory ? nil : (compressedSize <= UInt64(Int64.max) ? Int64(compressedSize) : nil),
                    modifiedDate: dosDate(date: readUInt16(central, cursor + 14), time: readUInt16(central, cursor + 12))
                ))
                insertNode(path: clean, isDirectory: isDirectory,
                           size: isDirectory ? nil : (size <= UInt64(Int64.max) ? Int64(size) : nil),
                           date: dosDate(date: readUInt16(central, cursor + 14), time: readUInt16(central, cursor + 12)),
                           nodes: &parsedNodes, indexByPath: &parsedIndexByPath)
            }
            processedEntries += 1
            if processedEntries == min(count, 256), processedEntries < count {
                onRootUpdate?(rootItems(from: parsedNodes))
            }
            cursor = end
        }
        guard processedEntries == count else { throw PreviewContentError.invalidArchive }
        lock.withLock {
            nodes = parsedNodes
            archiveEntries = parsedArchiveEntries
            parsed = true
        }
    }

    private func children(ofNodeID id: UUID) -> [PreviewItem] {
        lock.withLock {
            guard let nodeIndex = nodeIndex(from: id), nodeIndex < nodes.count else { return [] }
            return childrenUnlocked(ofNodeIndex: nodeIndex)
        }
    }

    private func children(ofNodeIndex nodeIndex: Int) -> [PreviewItem] {
        lock.withLock { childrenUnlocked(ofNodeIndex: nodeIndex) }
    }

    private func childrenUnlocked(ofNodeIndex nodeIndex: Int) -> [PreviewItem] {
        if !nodes[nodeIndex].isSorted {
            var childIndices = nodes[nodeIndex].children
            childIndices.sort { lhs, rhs in
                let left = nodes[lhs]
                let right = nodes[rhs]
                return left.kind != right.kind
                    ? left.kind == .folder
                    : left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            nodes[nodeIndex].children = childIndices
            nodes[nodeIndex].isSorted = true
        }
        return nodes[nodeIndex].children.map { makeItem(from: $0, in: nodes) }
    }

    private func rootItems(from nodes: [Node]) -> [PreviewItem] {
        guard let root = nodes.first else { return [] }
        return root.children
            .map { makeItem(from: $0, in: nodes) }
            .sorted { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func makeItem(from index: Int, in nodes: [Node]) -> PreviewItem {
        let node = nodes[index]
        // ZIP children are resolved by the compact node ID; no path string is needed.
        let path = nodePath(from: index, in: nodes)
        return PreviewItem(id: node.id, name: node.name, relativePath: path, kind: node.kind,
                           size: node.size, modifiedDate: node.date, contentTypeIdentifier: nil)
    }

    private func nodePath(from index: Int, in nodes: [Node]) -> String {
        var components: [String] = []
        var current = index
        while current > 0 {
            components.append(nodes[current].name)
            current = nodes[current].parent
        }
        return components.reversed().joined(separator: "/")
    }

    private func insertNode(path: String, isDirectory: Bool, size: Int64?, date: Date?,
                            nodes: inout [Node], indexByPath: inout [String: Int]) {
        let components = path.split(separator: "/").map(String.init)
        var parentIndex = 0
        var prefix = ""
        for (componentIndex, component) in components.enumerated() {
            let nodePath = prefix.isEmpty ? component : prefix + "/" + component
            let isLeaf = componentIndex == components.count - 1
            if let existingIndex = indexByPath[nodePath] {
                if isLeaf {
                    if isDirectory { nodes[existingIndex].kind = .folder; nodes[existingIndex].size = nil }
                    if date != nil { nodes[existingIndex].date = date }
                }
                parentIndex = existingIndex
            } else {
                let node = Node(id: makeNodeID(nodes.count), name: component, parent: parentIndex,
                                kind: isLeaf && !isDirectory ? .file : .folder,
                                size: isLeaf ? size : nil, date: isLeaf ? date : nil,
                                children: [], isSorted: false)
                let newIndex = nodes.count
                nodes.append(node)
                indexByPath[nodePath] = newIndex
                nodes[parentIndex].children.append(newIndex)
                parentIndex = newIndex
            }
            prefix = nodePath
        }
    }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    // Encode the node's integer index directly in the UUID. This keeps PreviewItem's
    // public identity API while removing a second UUID->index dictionary for every entry.
    private func makeNodeID(_ index: Int) -> UUID {
        let value = UInt64(index)
        return UUID(uuid: (0x49, 0x50, 0x4B, 0x31, 0, 0, 0, 0,
                           0, 0,
                           UInt8((value >> 40) & 0xff), UInt8((value >> 32) & 0xff),
                           UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
                           UInt8((value >> 8) & 0xff), UInt8(value & 0xff)))
    }

    private func nodeIndex(from id: UUID) -> Int? {
        let bytes = id.uuid
        guard bytes.0 == 0x49, bytes.1 == 0x50, bytes.2 == 0x4B, bytes.3 == 0x31,
              bytes.4 == 0, bytes.5 == 0, bytes.6 == 0, bytes.7 == 0,
              bytes.8 == 0, bytes.9 == 0 else { return nil }
        return Int(bytes.10) << 40 | Int(bytes.11) << 32 | Int(bytes.12) << 24 |
            Int(bytes.13) << 16 | Int(bytes.14) << 8 | Int(bytes.15)
    }
}

private func readUInt16(_ data: Data, _ offset: Int) -> UInt16 { UInt16(data[offset]) | UInt16(data[offset + 1]) << 8 }
private func readUInt32(_ data: Data, _ offset: Int) -> UInt32 { UInt32(readUInt16(data, offset)) | UInt32(readUInt16(data, offset + 2)) << 16 }
private func findSignature(_ signature: UInt32, in data: Data) -> Int? {
    guard data.count >= 4 else { return nil }
    for index in stride(from: data.count - 4, through: 0, by: -1) where readUInt32(data, index) == signature { return index }
    return nil
}
private func dosDate(date: UInt16, time: UInt16) -> Date? {
    var c = DateComponents(); c.year = 1980 + Int((date >> 9) & 0x7f); c.month = Int((date >> 5) & 0xf); c.day = Int(date & 0x1f)
    c.hour = Int((time >> 11) & 0x1f); c.minute = Int((time >> 5) & 0x3f); c.second = Int(time & 0x1f) * 2
    return zipGregorianCalendar.date(from: c)
}

private let zipGregorianCalendar = Calendar(identifier: .gregorian)
