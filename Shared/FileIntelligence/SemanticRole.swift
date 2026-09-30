import Foundation

/// A small, stable vocabulary shared by file recognition and relationship rules.
/// A file type may carry more than one role.
enum SemanticRole: String, CaseIterable, Codable, Sendable, Hashable {
    case readme
    case license
    case document
    case sourceCode
    case entryPoint
    case manifest
    case lockfile
    case configuration
    case buildConfig
    case modelWeights
    case tokenizer
    case dataset
    case database
    case index
    case metadata
    case sidecar
    case image
    case rawImage
    case audio
    case video
    case bibliography
    case archive
    case checksum
    case executable
    case installer
    case cache
    case generated
}
