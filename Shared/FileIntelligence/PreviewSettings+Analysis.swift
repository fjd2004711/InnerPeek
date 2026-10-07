import Foundation

extension PreviewSettings {
    /// The folder-analysis limits these settings ask for. Kept apart from the settings
    /// model so the settings window can use the model without the analysis engine.
    var analysisLimits: FolderAnalysisLimits {
        FolderAnalysisLimits(
            maximumDepth: Self.clampDepth(scanDepth),
            maximumEntries: Self.snapEntries(maximumEntries),
            ignoredDirectoryNames: FolderAnalysisLimits.standard.ignoredDirectoryNames
        )
    }
}
