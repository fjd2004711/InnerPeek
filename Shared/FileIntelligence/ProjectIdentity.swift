import Foundation

/// How strongly the local evidence supports the recognised identity.
enum ProjectIdentityConfidence: String, Sendable, Hashable {
    case high
    case medium
    case low
}

/// Where a project's source of truth lives, without any URL or credential.
struct RepositoryIdentity: Sendable, Hashable {
    let provider: GitRemoteProvider
    let host: String
    /// `owner/repository` (or `group/subgroup/repository`) when the remote path is understood.
    let slug: String?
    let head: GitHead?
}

/// Recognition-layer output. Detectors produce facts, this object aggregates
/// them, and presentation only renders it: it never checks for manifests or
/// dependencies itself. New ecosystems arrive as knowledge, not as UI code.
struct ProjectIdentity: Sendable, Hashable {
    let name: String
    let repository: RepositoryIdentity?
    let facts: [DetectedFact]
    let conflicts: [FactConflict]
    /// Overall confidence: the stronger of the repository evidence and the best primary fact.
    let confidence: ProjectIdentityConfidence
    /// Repository evidence. Per-fact evidence lives on each `DetectedFact`.
    let evidence: [GitMetadataItem]

    func facts(of kind: ProjectFactKind) -> [DetectedFact] { facts.filter { $0.kind == kind } }
    var projectKinds: [DetectedFact] { facts(of: .projectKind) }
    var languages: [DetectedFact] { facts(of: .language) }
    var frameworks: [DetectedFact] { facts(of: .framework) }
    var buildSystems: [DetectedFact] { facts(of: .buildSystem) }
    var packageManagers: [DetectedFact] { facts(of: .packageManager) }

    func primary(of kind: ProjectFactKind) -> DetectedFact? { facts(of: kind).first { $0.role == .primary } }
    var primaryFramework: DetectedFact? { primary(of: .framework) }
    var primaryLanguage: DetectedFact? { primary(of: .language) }
    var primaryPackageManager: DetectedFact? { primary(of: .packageManager) }
}

struct ProjectIdentityResolver: Sendable {
    /// `folderName` is only the fallback display name; a recognised remote
    /// repository name takes precedence because folder names are often renamed.
    func resolve(
        folderName: String,
        repositoryContext: GitRepositoryContext?,
        recognition: ProjectRecognition = .empty
    ) -> ProjectIdentity {
        var repository: RepositoryIdentity?
        var evidence: [GitMetadataItem] = []
        var confidence = ProjectIdentityConfidence.low
        var name = folderName
        if let context = repositoryContext {
            evidence = context.evidence
            if context.isRepository {
                repository = context.remote.map {
                    RepositoryIdentity(provider: $0.provider, host: $0.host, slug: $0.identity, head: context.head)
                } ?? RepositoryIdentity(provider: .other, host: "", slug: nil, head: context.head)
                name = context.remote?.repository ?? folderName
                confidence = context.remote?.identity != nil ? .high : .medium
            }
        }
        let best = recognition.facts.filter { $0.role == .primary }.map(\.confidence).max(by: Self.isLower)
        if let best, Self.isLower(confidence, best) { confidence = best }
        return ProjectIdentity(
            name: name, repository: repository, facts: recognition.facts,
            conflicts: recognition.conflicts, confidence: confidence, evidence: evidence
        )
    }

    private static func isLower(_ left: ProjectIdentityConfidence, _ right: ProjectIdentityConfidence) -> Bool {
        rank(left) < rank(right)
    }

    private static func rank(_ confidence: ProjectIdentityConfidence) -> Int {
        switch confidence {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}
