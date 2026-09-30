import Foundation

/// The normalized answer to “what is this file?”
struct FileIntelligence: Sendable, Hashable {
    let fileName: String
    let fileExtension: String?
    let category: FileCategory
    let typeName: String
    let purpose: String?
    /// The system UTType identifier when available; unknown formats retain a
    /// generic data identifier rather than inventing a semantic type.
    let systemTypeIdentifier: String?
    /// 1.0 is an explicit registry match; lower values are system or fallback inference.
    let confidence: Double
}
