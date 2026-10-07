import Foundation

/// What to draw when no brand asset applies.
enum VisualFallback: Sendable, Hashable {
    case kind(ProjectFactKind)
    case repository
    case generic
}

/// Presentation-neutral icon choice for a project: keys only, never images.
struct VisualIdentity: Sendable, Hashable {
    /// Registry key of the main logo, or `nil` when `fallback` should be drawn instead.
    let primaryIconKey: String?
    let fallback: VisualFallback
    /// Logo of the project's own technology (framework, specialised kind, language); never a repository host.
    let technologyIconKey: String?
    /// Logo of the repository host, when the remote is recognised.
    let repositoryIconKey: String?
    /// Small badges for the other primary technologies and the repository host.
    let secondaryIconKeys: [String]
}

/// Chooses the main logo with a fixed priority — primary framework, specialised
/// project kind, primary language, repository host, generic — and never looks
/// at files or at technology names.
struct VisualIdentityResolver: Sendable {
    static let maximumSecondaryIcons = 5

    private let catalog: IconCatalog

    init(catalog: IconCatalog = IconCatalog()) { self.catalog = catalog }

    func resolve(_ identity: ProjectIdentity) -> VisualIdentity {
        func icon(_ fact: DetectedFact) -> String? { fact.iconKey.flatMap { catalog.entry(for: $0) != nil ? $0 : nil } }
        let repositoryKey = identity.repository.flatMap { catalog.repositoryIconKey(for: $0.provider) }

        let tiers: [[DetectedFact]] = [
            identity.frameworks.filter { $0.role == .primary },
            identity.projectKinds.filter { $0.role == .primary },
            identity.languages.filter { $0.role == .primary }
        ]
        var primaryKey: String?
        var fallback = VisualFallback.generic
        for fact in tiers.flatMap({ $0 }) {
            if let key = icon(fact) { primaryKey = key; break }
        }
        let technologyKey = primaryKey
        if primaryKey == nil {
            // No logo among the technologies: a repository host logo beats a bare glyph,
            // but a recognised technology without a logo still gets its kind glyph.
            if let repositoryKey {
                primaryKey = repositoryKey
            } else if let fact = (tiers[0] + tiers[2]).first {
                fallback = .kind(fact.kind)
            } else if identity.repository != nil {
                fallback = .repository
            }
        }

        var secondary: [String] = []
        let badgeKinds: [ProjectFactKind] = [.framework, .language, .packageManager, .buildSystem]
        let badgeFacts = badgeKinds.flatMap { kind in identity.facts(of: kind).filter { $0.role == .primary } }
        for key in badgeFacts.compactMap(icon) + [repositoryKey].compactMap({ $0 })
        where key != primaryKey && !secondary.contains(key) {
            secondary.append(key)
        }
        return VisualIdentity(primaryIconKey: primaryKey, fallback: fallback,
                              technologyIconKey: technologyKey, repositoryIconKey: repositoryKey,
                              secondaryIconKeys: Array(secondary.prefix(Self.maximumSecondaryIcons)))
    }
}
