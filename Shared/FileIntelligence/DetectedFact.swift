import Foundation

/// The facet of a project a fact describes. Presentation groups by kind and
/// never inspects files itself.
enum ProjectFactKind: String, Codable, Sendable, Hashable, CaseIterable {
    case projectKind
    case language
    case framework
    case buildSystem
    case packageManager
    /// An engineering practice that is present (README, tests, CI, ...). Whether it is expected is decided by repository-health.json.
    case practice
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
    case extensionShare = "extension_share"
    case sourceImport = "source_import"
    case fileMatch = "file_match"
}

/// One matched rule. `key` always comes from the knowledge rule, never from
/// the inspected file, so evidence cannot carry manifest contents or secrets.
struct RecognitionEvidence: Sendable, Hashable {
    let type: RecognitionEvidenceType
    let relativePath: String
    let key: String?
    let weight: Double
    /// Only for `extension_share`: how many analysed files matched, and their share of all analysed files.
    let matchedFiles: Int?
    let share: Double?

    init(type: RecognitionEvidenceType, relativePath: String, key: String?, weight: Double,
         matchedFiles: Int? = nil, share: Double? = nil) {
        self.type = type
        self.relativePath = relativePath
        self.key = key
        self.weight = weight
        self.matchedFiles = matchedFiles
        self.share = share
    }

    /// A short, user-facing "why was this concluded" sentence. Built only from
    /// the rule's key, the path and counts, never from manifest contents.
    var explanation: InsightLocalizedText {
        let key = key ?? ""
        let catalog = MessageCatalog.shared
        switch type {
        case .pathExists: return catalog.text("%@ is present").formatted([relativePath])
        case .manifestDependency: return catalog.text("%@ depends on %@").formatted([relativePath, key])
        case .manifestKey: return catalog.text("%@ defines %@").formatted([relativePath, key])
        case .manifestText: return catalog.text("%@ mentions %@").formatted([relativePath, key])
        case .fileMatch:
            let count = matchedFiles ?? 0
            return catalog.text(count == 1 ? "%@ file is named like %@" : "%@ files are named like %@").formatted(["\(count)", key])
        case .sourceImport:
            let count = matchedFiles ?? 0
            return catalog.text(count == 1 ? "%@ file imports %@" : "%@ files import %@").formatted(["\(count)", key])
        case .extensionShare:
            let percent = Int(((share ?? 0) * 100).rounded())
            return catalog.text("%@%% of analysed files are .%@ (%@ files)").formatted(["\(percent)", key, "\(matchedFiles ?? 0)"])
        }
    }
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
    /// Stable visual key from the knowledge (`brand.nextjs`), resolved later by the icon layer.
    let iconKey: String?
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
