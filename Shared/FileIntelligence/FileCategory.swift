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
}
