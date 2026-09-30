import Foundation

/// A broad, stable classification used by file recognition and later folder analysis.
/// Keep this vocabulary independent from the UI so new presentation layers can share it.
enum FileCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case document
    case spreadsheet
    case image
    case rawImage
    case audio
    case video
    case archive
    case sourceCode
    case configuration
    case database
    case scientificData
    case aiModel
    case threeD
    case font
    case executable
    case project
    case unknown

    /// Stable ordering used only when aggregate size and count are tied.
    var stableSortOrder: Int {
        switch self {
        case .document: return 0
        case .spreadsheet: return 1
        case .image: return 2
        case .rawImage: return 3
        case .audio: return 4
        case .video: return 5
        case .archive: return 6
        case .sourceCode: return 7
        case .configuration: return 8
        case .database: return 9
        case .scientificData: return 10
        case .aiModel: return 11
        case .threeD: return 12
        case .font: return 13
        case .executable: return 14
        case .project: return 15
        case .unknown: return 16
        }
    }

    /// The UI resolves this key from the extension's localized strings table.
    var localizationKey: String { "file_category_\(rawValue)" }

    var systemSymbolName: String {
        switch self {
        case .document: return "doc"
        case .spreadsheet: return "tablecells"
        case .image, .rawImage: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .archive: return "archivebox"
        case .sourceCode: return "chevron.left.forwardslash.chevron.right"
        case .configuration: return "gearshape"
        case .database: return "cylinder"
        case .scientificData: return "chart.bar"
        case .aiModel: return "brain"
        case .threeD: return "cube"
        case .font: return "textformat"
        case .executable: return "terminal"
        case .project: return "folder.badge.gearshape"
        case .unknown: return "questionmark.folder"
        }
    }
}
