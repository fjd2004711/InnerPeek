import Foundation

private struct HealthKnowledge: Decodable, Sendable {
    struct Check: Decodable, Sendable {
        enum Importance: String, Decodable, Sendable { case core, extra }
        enum Requirement: String, Decodable, Sendable { case repository, language }
        let id: String
        let practice: String
        let name: InsightLocalizedText
        let importance: Importance
        let requires: Requirement?
        let missingSeverity: InsightSeverity?
    }
    struct Message: Decodable, Sendable {
        let title: InsightLocalizedText
        let detail: InsightLocalizedText
    }
    struct Messages: Decodable, Sendable {
        let complete: Message
        let gaps: Message
    }
    let appliesWhenAny: [Check.Requirement]
    let minimumCoreChecks: Int
    let checks: [Check]
    let messages: Messages
}

/// Which expected engineering practices a project has and lacks. It reads
/// recognised `practice.*` facts, so it never touches the filesystem itself.
struct RepositoryHealth: Sendable, Hashable {
    struct Item: Sendable, Hashable {
        let id: String
        let name: InsightLocalizedText
        let isCore: Bool
        let isPresent: Bool
        /// A path that proves the practice exists.
        let evidencePath: String?
        let missingSeverity: InsightSeverity
    }

    let items: [Item]
    let complete: InsightLocalizedText
    let completeDetail: InsightLocalizedText
    let gaps: InsightLocalizedText
    let gapsDetail: InsightLocalizedText

    var presentCore: [Item] { items.filter { $0.isCore && $0.isPresent } }
    var missingCore: [Item] { items.filter { $0.isCore && !$0.isPresent } }
    var presentExtras: [Item] { items.filter { !$0.isCore && $0.isPresent } }
}

struct RepositoryHealthEvaluator: Sendable {
    private static let maximumNamedItems = 6
    private let knowledge: HealthKnowledge?

    init(data: Data? = nil) {
        let bundled = Bundle(for: FileTypeRegistry.self).url(forResource: "repository-health", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Knowledge/repository-health.json")
        knowledge = (data ?? bundled ?? (try? Data(contentsOf: sourceURL))).flatMap { try? JSONDecoder().decode(HealthKnowledge.self, from: $0) }
    }

    /// `nil` when the folder is not a repository or a recognised code project, so a
    /// plain Downloads folder is never graded.
    func evaluate(recognition: ProjectRecognition, repositoryContext: GitRepositoryContext?) -> RepositoryHealth? {
        guard let knowledge else { return nil }
        let isRepository = repositoryContext?.isRepository == true
        let hasLanguage = recognition.facts.contains { $0.kind == .language && $0.role == .primary }
        func satisfied(_ requirement: HealthKnowledge.Check.Requirement) -> Bool {
            requirement == .repository ? isRepository : hasLanguage
        }
        guard knowledge.appliesWhenAny.contains(where: satisfied) else { return nil }

        let items = knowledge.checks.compactMap { check -> RepositoryHealth.Item? in
            let fact = recognition.facts.first { $0.id == check.practice }
            // A requirement only decides whether absence is worth reporting; a practice
            // that exists is always shown (CI in a downloaded copy without .git).
            if let requirement = check.requires, !satisfied(requirement), fact == nil { return nil }
            return RepositoryHealth.Item(
                id: check.id, name: check.name, isCore: check.importance == .core, isPresent: fact != nil,
                evidencePath: fact?.evidence.first?.relativePath, missingSeverity: check.missingSeverity ?? .info
            )
        }
        guard items.filter(\.isCore).count >= knowledge.minimumCoreChecks else { return nil }
        return RepositoryHealth(
            items: items,
            complete: knowledge.messages.complete.title, completeDetail: knowledge.messages.complete.detail,
            gaps: knowledge.messages.gaps.title, gapsDetail: knowledge.messages.gaps.detail
        )
    }

    /// Fills `%@` in both languages with that language's own item names.
    static func format(_ template: InsightLocalizedText, names: [InsightLocalizedText]) -> InsightLocalizedText {
        let shown = Array(names.prefix(maximumNamedItems))
        let english = shown.map(\.english).joined(separator: ", ")
        let chinese = shown.map(\.simplifiedChinese).joined(separator: "、")
        return InsightLocalizedText(
            english: template.english.replacingOccurrences(of: "%@", with: english),
            simplifiedChinese: template.simplifiedChinese.replacingOccurrences(of: "%@", with: chinese)
        )
    }
}
