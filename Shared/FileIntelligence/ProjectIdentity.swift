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

/// Recognition-layer output. Presentation renders this object and does not
/// re-derive facts from raw files; later stages (project kinds, frameworks,
/// build systems, CI) extend it rather than adding checks to the UI.
struct ProjectIdentity: Sendable, Hashable {
    let name: String
    let repository: RepositoryIdentity?
    let confidence: ProjectIdentityConfidence
    let evidence: [GitMetadataItem]
}

struct ProjectIdentityResolver: Sendable {
    /// `folderName` is only the fallback display name; a recognised remote
    /// repository name takes precedence because folder names are often renamed.
    func resolve(folderName: String, repositoryContext: GitRepositoryContext?) -> ProjectIdentity {
        guard let context = repositoryContext else {
            return ProjectIdentity(name: folderName, repository: nil, confidence: .low, evidence: [])
        }
        let repository: RepositoryIdentity? = context.isRepository
            ? context.remote.map { RepositoryIdentity(provider: $0.provider, host: $0.host, slug: $0.identity, head: context.head) }
                ?? RepositoryIdentity(provider: .other, host: "", slug: nil, head: context.head)
            : nil
        let name = context.remote?.repository ?? folderName
        let confidence: ProjectIdentityConfidence
        switch context.state {
        case .repository: confidence = context.remote?.identity != nil ? .high : .medium
        case .githubMetadataOnly, .metadataDetected: confidence = .low
        }
        return ProjectIdentity(name: name, repository: repository, confidence: confidence, evidence: context.evidence)
    }
}
