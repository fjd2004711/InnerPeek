import Foundation

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
    let scanState: FolderAnalysisScanState
}
