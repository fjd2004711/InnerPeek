import Foundation

/// The facet of a project a fact describes. Presentation groups by kind and
/// never inspects files itself.
enum ProjectFactKind: String, Codable, Sendable, Hashable, CaseIterable {
    case projectKind
    case language
    case framework
    case buildSystem
    case packageManager
}

/// `primary` facts describe the project; `supporting` facts are real but
/// subordinate (React under Next.js, JavaScript under TypeScript, pip next to uv).
enum ProjectFactRole: String, Sendable, Hashable {
    case primary
    case supporting
}

enum RecognitionEvidenceType: String, Codable, Sendable, Hashable {
    case pathExists = "path_exists"
    case manifestDependency = "manifest_dependency"
    case manifestKey = "manifest_key"
    case manifestText = "manifest_text"
}

/// One matched rule. `key` always comes from the knowledge rule, never from
/// the inspected file, so evidence cannot carry manifest contents or secrets.
struct RecognitionEvidence: Sendable, Hashable {
    let type: RecognitionEvidenceType
    let relativePath: String
    let key: String?
    let weight: Double
}

struct DetectedFact: Sendable, Hashable {
    let id: String
    let kind: ProjectFactKind
    let name: InsightLocalizedText
    /// Combined strength of all matched evidence, 0...1.
    let score: Double
    let confidence: ProjectIdentityConfidence
    let role: ProjectFactRole
    let evidence: [RecognitionEvidence]
    /// Fact ids that caused this fact through an `implies` declaration.
    let impliedBy: [String]
}

/// Facts of one exclusive group whose scores are too close to pick a winner.
struct FactConflict: Sendable, Hashable {
    let group: String
    let factIDs: [String]
}

struct ProjectRecognition: Sendable, Hashable {
    let facts: [DetectedFact]
    let conflicts: [FactConflict]

    static let empty = ProjectRecognition(facts: [], conflicts: [])

    func facts(of kind: ProjectFactKind) -> [DetectedFact] { facts.filter { $0.kind == kind } }
}

extension ProjectIdentityConfidence {
    /// Shared score-to-tier mapping so every fact and the aggregate use one scale.
    init(score: Double) {
        self = score >= 0.85 ? .high : (score >= 0.6 ? .medium : .low)
    }
}
