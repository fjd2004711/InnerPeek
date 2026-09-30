import Foundation

struct FolderAnalysisLimits: Sendable, Hashable {
    /// The root folder's direct children have depth 1. Entries below a child
    /// directory have depth 2. Directories at the maximum depth are counted
    /// but their descendants are not enumerated.
    let maximumDepth: Int
    /// Maximum number of files and directories considered, excluding the root.
    let maximumEntries: Int
    let ignoredDirectoryNames: Set<String>

    static let standard = FolderAnalysisLimits(
        maximumDepth: 2,
        maximumEntries: 2_000,
        ignoredDirectoryNames: [
            ".git", "node_modules", "DerivedData", "build", "dist", "target",
            ".venv", "venv", "__pycache__", ".cache"
        ]
    )
}

/// Bounded, cancellation-aware semantic aggregation for on-disk folders.
/// It deliberately skips hidden entries to preserve the existing preview policy.
struct FolderAnalyzer: Sendable {
    let recognizer: FileIntelligenceRecognizer
    let limits: FolderAnalysisLimits

    init(
        recognizer: FileIntelligenceRecognizer = FileIntelligenceRecognizer(),
        limits: FolderAnalysisLimits = .standard
    ) {
        self.recognizer = recognizer
        self.limits = limits
    }

    func analyze(folderURL: URL) throws -> FolderAnalysis {
        precondition(limits.maximumDepth > 0, "maximumDepth must be positive")
        precondition(limits.maximumEntries > 0, "maximumEntries must be positive")

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        // Retain .dockerignore as a relationship sidecar while preserving the
        // preview's policy of skipping every other hidden entry.
        let options: FileManager.DirectoryEnumerationOptions = []
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return FolderAnalysis(
                analyzedFileCount: 0,
                analyzedDirectoryCount: 0,
                analyzedEntryCount: 0,
                totalKnownFileSize: 0,
                categoryStatistics: [],
                extensionStatistics: [],
                analyzedFiles: [],
                analyzedEntries: [],
                scanState: .complete
            )
        }

        var entryCount = 0
        var fileCount = 0
        var directoryCount = 0
        var totalSize: Int64 = 0
        var categories: [FileCategory: MutableStatistic] = [:]
        var extensions: [String?: MutableStatistic] = [:]
        var analyzedFiles: [AnalyzedFile] = []
        var analyzedEntries: [AnalyzedEntry] = []
        var reachedLimits = Set<FolderAnalysisLimit>()
        let resolvedRootPath = folderURL.resolvingSymlinksInPath().path

        while let itemURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let name = itemURL.lastPathComponent
            if name.hasPrefix(".") && name != ".dockerignore" {
                enumerator.skipDescendants()
                continue
            }
            if entryCount >= limits.maximumEntries {
                reachedLimits.insert(.maximumEntries)
                break
            }

            // FileManager.DirectoryEnumerator reports the root's direct
            // children at level 1, which is our documented traversal depth.
            let depth = enumerator.level
            let itemPath = itemURL.path
            let canonicalItemPath = itemPath.hasPrefix(resolvedRootPath + "/")
                ? itemPath : itemURL.resolvingSymlinksInPath().path
            guard canonicalItemPath.hasPrefix(resolvedRootPath + "/") else { continue }
            let relativePath = String(canonicalItemPath.dropFirst(resolvedRootPath.count + 1))
            do {
                let values = try itemURL.resourceValues(forKeys: keys)
                let isDirectory = values.isDirectory ?? false
                let isSymbolicLink = values.isSymbolicLink ?? false

                entryCount += 1
                if isDirectory {
                    analyzedEntries.append(AnalyzedEntry(
                        url: itemURL, relativePath: relativePath, name: name,
                        isDirectory: true, intelligence: nil
                    ))
                    directoryCount += 1

                    // Count the visible directory itself, but never recurse into a
                    // symlink directory, a known generated directory, or past depth.
                    if isSymbolicLink || limits.ignoredDirectoryNames.contains(itemURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    } else if depth >= limits.maximumDepth {
                        reachedLimits.insert(.maximumDepth)
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values.isRegularFile ?? true else { continue }
                let size = values.fileSize.map(Int64.init) ?? 0
                let intelligence = recognizer.intelligence(for: itemURL)
                analyzedEntries.append(AnalyzedEntry(
                    url: itemURL, relativePath: relativePath, name: name,
                    isDirectory: false, intelligence: intelligence
                ))
                fileCount += 1
                totalSize += size
                categories[intelligence.category, default: MutableStatistic()].add(size: size)
                extensions[intelligence.fileExtension, default: MutableStatistic()].add(size: size)
                analyzedFiles.append(AnalyzedFile(
                    url: itemURL,
                    size: size,
                    modifiedDate: values.contentModificationDate,
                    intelligence: intelligence
                ))
            } catch {
                // A single unreadable child must not stop a Quick Look preview.
                continue
            }
        }

        let categoryStatistics = categories.map {
            CategoryStatistic(category: $0.key, fileCount: $0.value.fileCount, totalKnownSize: $0.value.totalKnownSize)
        }.sorted(by: Self.sort)
        let extensionStatistics = extensions.map {
            ExtensionStatistic(fileExtension: $0.key, fileCount: $0.value.fileCount, totalKnownSize: $0.value.totalKnownSize)
        }.sorted(by: Self.sort)

        return FolderAnalysis(
            analyzedFileCount: fileCount,
            analyzedDirectoryCount: directoryCount,
            analyzedEntryCount: entryCount,
            totalKnownFileSize: totalSize,
            categoryStatistics: categoryStatistics,
            extensionStatistics: extensionStatistics,
            analyzedFiles: analyzedFiles,
            analyzedEntries: analyzedEntries,
            scanState: reachedLimits.isEmpty ? .complete : .partial(reachedLimits)
        )
    }

    private struct MutableStatistic {
        var fileCount = 0
        var totalKnownSize: Int64 = 0

        mutating func add(size: Int64) {
            fileCount += 1
            totalKnownSize += size
        }
    }

    private static func sort(_ lhs: CategoryStatistic, _ rhs: CategoryStatistic) -> Bool {
        if lhs.totalKnownSize != rhs.totalKnownSize { return lhs.totalKnownSize > rhs.totalKnownSize }
        if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
        return lhs.category.stableSortOrder < rhs.category.stableSortOrder
    }

    private static func sort(_ lhs: ExtensionStatistic, _ rhs: ExtensionStatistic) -> Bool {
        if lhs.totalKnownSize != rhs.totalKnownSize { return lhs.totalKnownSize > rhs.totalKnownSize }
        if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
        return (lhs.fileExtension ?? "") < (rhs.fileExtension ?? "")
    }
}
