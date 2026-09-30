import Foundation

enum ContentSourceKind: String, Codable, Sendable, Hashable {
    case filesystem
    case zip
}

/// A normalized entry shared by filesystem and archive intelligence.
/// `url` is the source URL for filesystem entries and a synthetic path for ZIP entries;
/// downstream analyzers use the stable relative path and never open archive data.
struct ContentEntry: Sendable, Hashable {
    let url: URL
    let relativePath: String
    let name: String
    let fileExtension: String?
    let isDirectory: Bool
    let logicalSize: Int64?
    let compressedSize: Int64?
    let modifiedDate: Date?
    let sourceKind: ContentSourceKind
}

struct ContentSnapshot: Sendable, Hashable {
    let entries: [ContentEntry]
    let scanState: FolderAnalysisScanState
    let sourceKind: ContentSourceKind
}

struct CategoryStatistic: Sendable, Hashable {
    let category: FileCategory
    let fileCount: Int
    /// Sum of the regular files' logical sizes, obtained from filesystem metadata.
    let totalKnownSize: Int64
}

struct ExtensionStatistic: Sendable, Hashable {
    /// `nil` represents a file with no filename extension.
    let fileExtension: String?
    let fileCount: Int
    let totalKnownSize: Int64
}

/// A regular file already discovered during the bounded Stage-2 traversal.
/// Later consumers must reuse this list rather than walking the folder again.
struct AnalyzedFile: Sendable, Hashable {
    let url: URL
    let size: Int64
    let modifiedDate: Date?
    let intelligence: FileIntelligence
}
struct AnalyzedEntry: Sendable, Hashable {
    let url: URL
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let intelligence: FileIntelligence?
}

enum FolderAnalysisLimit: String, Sendable, Hashable {
    case maximumDepth
    case maximumEntries
}

enum FolderAnalysisScanState: Sendable, Hashable {
    case complete
    case partial(Set<FolderAnalysisLimit>)

    var isPartial: Bool {
        if case .partial = self { return true }
        return false
    }
}

/// Statistics for the bounded recursive population, not Finder's immediate-child count.
struct FolderAnalysis: Sendable, Hashable {
    /// Number of regular files in the analyzed population.
    let analyzedFileCount: Int
    /// Number of directory entries in the analyzed population, excluding the root folder.
    let analyzedDirectoryCount: Int
    /// Number of file-system entries considered, including files and directories.
    let analyzedEntryCount: Int
    /// Sum of logical sizes for analyzed regular files; directories are not included.
    let totalKnownFileSize: Int64
    let categoryStatistics: [CategoryStatistic]
    let extensionStatistics: [ExtensionStatistic]
    let analyzedFiles: [AnalyzedFile]
    let analyzedEntries: [AnalyzedEntry]
    let scanState: FolderAnalysisScanState
    let sourceKind: ContentSourceKind
    /// Repository context is obtained from a fixed set of root metadata paths,
    /// outside the regular visible-file traversal.
    let repositoryContext: GitRepositoryContext?

    init(
        analyzedFileCount: Int,
        analyzedDirectoryCount: Int,
        analyzedEntryCount: Int,
        totalKnownFileSize: Int64,
        categoryStatistics: [CategoryStatistic],
        extensionStatistics: [ExtensionStatistic],
        analyzedFiles: [AnalyzedFile],
        analyzedEntries: [AnalyzedEntry],
        scanState: FolderAnalysisScanState,
        sourceKind: ContentSourceKind = .filesystem,
        repositoryContext: GitRepositoryContext? = nil
    ) {
        self.analyzedFileCount = analyzedFileCount
        self.analyzedDirectoryCount = analyzedDirectoryCount
        self.analyzedEntryCount = analyzedEntryCount
        self.totalKnownFileSize = totalKnownFileSize
        self.categoryStatistics = categoryStatistics
        self.extensionStatistics = extensionStatistics
        self.analyzedFiles = analyzedFiles
        self.analyzedEntries = analyzedEntries
        self.scanState = scanState
        self.sourceKind = sourceKind
        self.repositoryContext = repositoryContext
    }

    /// Builds the existing analysis contract from a provider-neutral snapshot.
    /// ZIP entries are classified from names and central-directory sizes only.
    init(snapshot: ContentSnapshot, recognizer: FileIntelligenceRecognizer) {
        var categories: [FileCategory: (count: Int, size: Int64)] = [:]
        var extensions: [String?: (count: Int, size: Int64)] = [:]
        var files: [AnalyzedFile] = []
        var analyzedEntries: [AnalyzedEntry] = []
        var total: Int64 = 0

        for entry in snapshot.entries {
            if entry.isDirectory {
                analyzedEntries.append(AnalyzedEntry(url: entry.url, relativePath: entry.relativePath,
                                                      name: entry.name, isDirectory: true, intelligence: nil))
                continue
            }
            let intelligence = recognizer.intelligence(for: entry.url)
            let size = entry.logicalSize ?? 0
            analyzedEntries.append(AnalyzedEntry(url: entry.url, relativePath: entry.relativePath,
                                                  name: entry.name, isDirectory: false, intelligence: intelligence))
            files.append(AnalyzedFile(url: entry.url, size: size, modifiedDate: entry.modifiedDate,
                                      intelligence: intelligence))
            total += size
            categories[intelligence.category, default: (0, 0)].count += 1
            categories[intelligence.category, default: (0, 0)].size += size
            extensions[intelligence.fileExtension, default: (0, 0)].count += 1
            extensions[intelligence.fileExtension, default: (0, 0)].size += size
        }

        let categoryStatistics = categories.map { CategoryStatistic(category: $0.key, fileCount: $0.value.count, totalKnownSize: $0.value.size) }
            .sorted { lhs, rhs in
                if lhs.totalKnownSize != rhs.totalKnownSize { return lhs.totalKnownSize > rhs.totalKnownSize }
                if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
                return lhs.category.stableSortOrder < rhs.category.stableSortOrder
            }
        let extensionStatistics = extensions.map { ExtensionStatistic(fileExtension: $0.key, fileCount: $0.value.count, totalKnownSize: $0.value.size) }
            .sorted { lhs, rhs in
                if lhs.totalKnownSize != rhs.totalKnownSize { return lhs.totalKnownSize > rhs.totalKnownSize }
                if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
                return (lhs.fileExtension ?? "") < (rhs.fileExtension ?? "")
            }

        self.init(analyzedFileCount: files.count,
                  analyzedDirectoryCount: analyzedEntries.filter(\.isDirectory).count,
                  analyzedEntryCount: analyzedEntries.count,
                  totalKnownFileSize: total,
                  categoryStatistics: categoryStatistics,
                  extensionStatistics: extensionStatistics,
                  analyzedFiles: files,
                  analyzedEntries: analyzedEntries,
                  scanState: snapshot.scanState,
                  sourceKind: snapshot.sourceKind,
                  repositoryContext: nil)
    }
}
