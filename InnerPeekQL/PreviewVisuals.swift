import AppKit

/// Shared visual constants for the Quick Look content view.
/// Values intentionally use AppKit defaults and semantic colors rather than a custom theme.
enum PreviewVisuals {
    static let headerTitleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let headerSubtitleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    static let rowFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let metadataFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    static let analysisTitleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    static let headerInset: CGFloat = 18
    static let headerIconSize: CGFloat = 24
    static let headerTextSpacing: CGFloat = 2
    static let contentInset: CGFloat = 12
    static let contentPanelCornerRadius: CGFloat = 12
    static let headerToContentSpacing: CGFloat = 12
    static let controlSpacing: CGFloat = 8
    static let tableRowHeight: CGFloat = 24
    static let tableIntercellSpacing = NSSize(width: 8, height: 2)
    static let analysisInset: CGFloat = 12
    static let analysisIconSize: CGFloat = 14
    static let analysisRowSpacing: CGFloat = 6
    static let analysisHeaderToRowsSpacing: CGFloat = 8
    static let analysisCountWidth: CGFloat = 52
    static let analysisSizeWidth: CGFloat = 70
    static let maximumDisplayedCategories = 6

    static let nameColumnMinimumWidth: CGFloat = 180
    static let sizeColumnWidth: CGFloat = 96
    static let modifiedColumnWidth: CGFloat = 150

    static let secondaryLabelColor = NSColor.secondaryLabelColor
}
