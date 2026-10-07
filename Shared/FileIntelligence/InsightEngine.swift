import Foundation

enum InsightKind: String, Codable, Sendable, Hashable {
    case completeness
    case anomaly
    case storage
}

enum InsightSeverity: String, Codable, Sendable, Hashable {
    case info
    case positive
    case notice
    case warning

    var rank: Int {
        switch self {
        case .warning: return 4
        case .notice: return 3
        case .positive: return 2
        case .info: return 1
        }
    }
}

struct InsightEvidence: Sendable, Hashable {
    let source: String
    let value: String
}

struct Insight: Sendable, Hashable {
    let id: String
    let kind: InsightKind
    let severity: InsightSeverity
    let title: InsightLocalizedText
    let detail: InsightLocalizedText?
    let detailArguments: [String]
    let evidence: [InsightEvidence]
    let confidence: Double
    let priority: Int

    func localizedTitle(for locale: Locale = LocaleOverride.effective) -> String {
        title.value(for: locale)
    }

    func localizedDetail(for locale: Locale = LocaleOverride.effective) -> String? {
        detail?.value(for: locale, arguments: detailArguments)
    }
}

private struct InsightRule: Decodable, Sendable {
    struct Messages: Decodable, Sendable {
        let complete: InsightMessage?
        let missingRequired: InsightMessage?
        let missingRecommended: InsightMessage?
    }

    struct InsightMessage: Decodable, Sendable {
        let title: InsightLocalizedText
        let detail: InsightLocalizedText?
    }

    let id: String
    let relationshipType: String
    let requiredRoles: [String]
    let recommendedRoles: [String]
    let positiveWhenComplete: Bool
    let completeSeverity: InsightSeverity
    let missingRequiredSeverity: InsightSeverity
    let missingRecommendedSeverity: InsightSeverity
    let messages: Messages

    enum CodingKeys: String, CodingKey {
        case id, relationshipType, requiredRoles, recommendedRoles, positiveWhenComplete
        case completeSeverity, missingRequiredSeverity, missingRecommendedSeverity, messages
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        relationshipType = try values.decode(String.self, forKey: .relationshipType)
        requiredRoles = try values.decodeIfPresent([String].self, forKey: .requiredRoles) ?? []
        recommendedRoles = try values.decodeIfPresent([String].self, forKey: .recommendedRoles) ?? []
        positiveWhenComplete = try values.decodeIfPresent(Bool.self, forKey: .positiveWhenComplete) ?? false
        completeSeverity = try values.decodeIfPresent(InsightSeverity.self, forKey: .completeSeverity) ?? .positive
        missingRequiredSeverity = try values.decodeIfPresent(InsightSeverity.self, forKey: .missingRequiredSeverity) ?? .warning
        missingRecommendedSeverity = try values.decodeIfPresent(InsightSeverity.self, forKey: .missingRecommendedSeverity) ?? .notice
        messages = try values.decode(Messages.self, forKey: .messages)
    }
}

/// Produces a small, deterministic set of actionable findings from the existing
/// bounded analysis snapshot. It never performs another filesystem traversal.
struct InsightEngine: Sendable {
    static let maximumVisibleInsights = 3
    static let smallModelWeightThreshold: Int64 = 1_024
    static let minimumFilesForConcentration = 4
    static let singleFileConcentrationThreshold = 0.60
    static let topThreeConcentrationThreshold = 0.80
    static let categoryConcentrationThreshold = 0.75

    private let rules: [InsightRule]
    private let health = RepositoryHealthEvaluator()

    init(data: Data) {
        rules = (try? JSONDecoder().decode([InsightRule].self, from: data)) ?? []
    }

    init() {
        let bundle = Bundle(for: FileTypeRegistry.self)
        let bundled = bundle.url(forResource: "insights", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Knowledge/insights.json")
        self.init(data: bundled ?? (try? Data(contentsOf: sourceURL)) ?? Data())
    }

    func generate(
        for analysis: FolderAnalysis,
        relationships: [DetectedRelationship],
        importantFiles: [ImportantFile] = []
    ) -> [Insight] {
        var findings = completenessInsights(analysis: analysis, relationships: relationships)
        findings += anomalyInsights(analysis: analysis, importantFiles: importantFiles)
        findings += storageInsights(analysis: analysis, existing: findings)
        findings += repositoryInsights(analysis.repositoryContext)
        findings += healthInsights(analysis)

        var seen = Set<String>()
        return findings
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.severity.rank != $1.severity.rank { return $0.severity.rank > $1.severity.rank }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.id < $1.id
            }
            .prefix(Self.maximumVisibleInsights)
            .map { $0 }
    }

    private func repositoryInsights(_ context: GitRepositoryContext?) -> [Insight] {
        guard let context, context.isRepository else { return [] }
        var findings: [Insight] = []
        if case .detached? = context.head {
            findings.append(Insight(
                id: "git-detached-head", kind: .anomaly, severity: .notice,
                title: text("Detached HEAD detected"),
                detail: text("No branch name is inferred from the local HEAD."),
                detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".git/HEAD")],
                confidence: 1.0, priority: 760
            ))
        }
        if context.remote == nil {
            findings.append(Insight(
                id: "git-no-remote", kind: .completeness, severity: .info,
                title: text("Git metadata exists but no remote is configured"),
                detail: nil, detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".git/HEAD")],
                confidence: 1.0, priority: 650
            ))
        }
        return findings
    }

    /// One finding about missing basics, or one positive when the basics are all there.
    private func healthInsights(_ analysis: FolderAnalysis) -> [Insight] {
        guard let result = health.evaluate(recognition: analysis.projectRecognition, repositoryContext: analysis.repositoryContext) else { return [] }
        let missing = result.missingCore
        if !missing.isEmpty {
            let severity = missing.map(\.missingSeverity).max { $0.rank < $1.rank } ?? .info
            return [Insight(
                id: "repo-health-gaps", kind: .completeness, severity: severity,
                title: InsightLocalizedText.fill(result.gaps, names: missing.map(\.name)),
                detail: result.gapsDetail, detailArguments: [],
                evidence: missing.map { InsightEvidence(source: "missingPractice", value: $0.id) },
                confidence: 0.9, priority: 700
            )]
        }
        let present = result.presentCore + result.presentExtras
        return [Insight(
            id: "repo-health-complete", kind: .completeness, severity: .positive,
            title: result.complete,
            detail: InsightLocalizedText.fill(result.completeDetail, names: present.prefix(6).map(\.name)), detailArguments: [],
            evidence: present.compactMap { item in item.evidencePath.map { InsightEvidence(source: "practice", value: $0) } },
            confidence: 0.9, priority: 640
        )]
    }

    private func completenessInsights(analysis: FolderAnalysis, relationships: [DetectedRelationship]) -> [Insight] {
        relationships.flatMap { relationship in
            rules.filter { $0.relationshipType == relationship.type.rawValue }.compactMap { rule in
                let present = Set(relationship.members.map(semanticRole(for:)))
                let missingRequired = rule.requiredRoles.filter { !present.contains($0) }
                let missingRecommended = rule.recommendedRoles.filter { !present.contains($0) }

                if !missingRequired.isEmpty {
                    // A bounded partial scan cannot prove that a required file is absent.
                    guard !analysis.scanState.isPartial, let message = rule.messages.missingRequired else { return nil }
                    return makeInsight(
                        id: rule.id + "-missing-required",
                        kind: .completeness,
                        severity: rule.missingRequiredSeverity,
                        message: message,
                        arguments: missingRequired.map(roleDisplayName).joined(separator: ", "),
                        evidence: missingRequired.map { InsightEvidence(source: "missingRole", value: $0) },
                        confidence: relationship.confidence,
                        priority: 940
                    )
                }

                if !missingRecommended.isEmpty, let message = rule.messages.missingRecommended {
                    return makeInsight(
                        id: rule.id + "-missing-recommended",
                        kind: .completeness,
                        severity: rule.missingRecommendedSeverity,
                        message: message,
                        arguments: missingRecommended.map(roleDisplayName).joined(separator: ", "),
                        evidence: missingRecommended.map { InsightEvidence(source: "missingRecommendedRole", value: $0) },
                        confidence: relationship.confidence,
                        priority: 700
                    )
                }

                guard rule.positiveWhenComplete, !analysis.scanState.isPartial, let message = rule.messages.complete else { return nil }
                return makeInsight(
                    id: rule.id + "-complete",
                    kind: .completeness,
                    severity: rule.completeSeverity,
                    message: message,
                    evidence: relationship.members.map { InsightEvidence(source: "relationshipMember", value: $0.relativePath) },
                    confidence: relationship.confidence,
                    priority: 620
                )
            }
        }
    }

    private func anomalyInsights(analysis: FolderAnalysis, importantFiles: [ImportantFile]) -> [Insight] {
        let emptyFiles = analysis.analyzedFiles.filter { $0.size == 0 }
        let modelWeightFiles = analysis.analyzedFiles.filter { $0.intelligence.roles.contains(.modelWeights) }
        let emptyModelWeights = modelWeightFiles.filter { $0.size == 0 }
        var findings: [Insight] = []

        if !emptyModelWeights.isEmpty {
            findings.append(Insight(
                id: "empty-model-weights", kind: .anomaly, severity: .warning,
                title: text("Model weight file is empty"),
                detail: text("%@ is empty and may be a placeholder or test file."),
                detailArguments: [emptyModelWeights.map { $0.intelligence.fileName }.joined(separator: ", ")],
                evidence: emptyModelWeights.map { InsightEvidence(source: "filePath", value: $0.intelligence.fileName) },
                confidence: 1.0, priority: 980
            ))
        }

        if !emptyFiles.isEmpty {
            findings.append(Insight(
                id: "empty-files", kind: .anomaly,
                severity: emptyModelWeights.isEmpty ? .notice : .info,
                title: text("Empty files detected"),
                detail: text("%@ files have zero bytes."),
                detailArguments: [String(emptyFiles.count)],
                evidence: emptyFiles.map { InsightEvidence(source: "filePath", value: $0.intelligence.fileName) },
                confidence: 1.0, priority: emptyModelWeights.isEmpty ? 850 : 400
            ))
        }

        let smallModels = modelWeightFiles.filter { $0.size > 0 && $0.size <= Self.smallModelWeightThreshold }
        if !smallModels.isEmpty {
            findings.append(Insight(
                id: "small-model-weights", kind: .anomaly, severity: .warning,
                title: text("Model weight file is unusually small"),
                detail: text("%@ may be a placeholder or test file."),
                detailArguments: [smallModels.map { "\($0.intelligence.fileName) (\(formatBytes($0.size)))" }.joined(separator: ", ")],
                evidence: smallModels.map { InsightEvidence(source: "fileSize", value: "\($0.intelligence.fileName)=\($0.size)") },
                confidence: 0.92, priority: 960
            ))
        }

        _ = importantFiles // Important files remain available for future actions and ranking.
        return findings
    }

    private func storageInsights(analysis: FolderAnalysis, existing: [Insight]) -> [Insight] {
        let files = analysis.analyzedFiles.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        // With only a few files some file is always the biggest; that is not a finding.
        guard files.count >= Self.minimumFilesForConcentration, analysis.totalKnownFileSize > 0 else { return [] }
        let total = Double(analysis.totalKnownFileSize)
        let topRatio = Double(files[0].size) / total
        if topRatio >= Self.singleFileConcentrationThreshold {
            let duplicateKey = files[0].intelligence.fileName
            guard !existing.contains(where: { $0.evidence.contains { $0.value.contains(duplicateKey) } && $0.kind == .anomaly }) else { return [] }
            return [Insight(
                id: "largest-file-concentration", kind: .storage, severity: .notice,
                title: text("One file dominates analyzed size"),
                detail: text("%@ accounts for %@ of analyzed size%@."),
                detailArguments: [files[0].intelligence.fileName, percentage(topRatio), analysis.scanState.isPartial ? partialSuffix() : ""],
                evidence: [InsightEvidence(source: "filePath", value: files[0].intelligence.fileName), InsightEvidence(source: "fileSize", value: String(files[0].size))],
                confidence: 1.0, priority: 560
            )]
        }

        let topThree = files.prefix(3)
        let topThreeRatio = Double(topThree.reduce(Int64(0), { $0 + $1.size })) / total
        if topThreeRatio >= Self.topThreeConcentrationThreshold {
            return [Insight(
                id: "top-three-concentration", kind: .storage, severity: .notice,
                title: text("A few files dominate analyzed size"),
                detail: text("The largest %@ files account for %@ of analyzed size%@."),
                detailArguments: ["3", percentage(topThreeRatio), analysis.scanState.isPartial ? partialSuffix() : ""],
                evidence: topThree.map { InsightEvidence(source: "filePath", value: $0.intelligence.fileName) },
                confidence: 1.0, priority: 520
            )]
        }

        let dominantCategory = analysis.categoryStatistics.sorted { $0.totalKnownSize > $1.totalKnownSize }.first
        guard analysis.categoryStatistics.count > 1,
              let dominantCategory,
              dominantCategory.totalKnownSize > 0 else { return [] }
        let categoryRatio = Double(dominantCategory.totalKnownSize) / total
        guard categoryRatio >= Self.categoryConcentrationThreshold else { return [] }
        return [Insight(
            id: "category-concentration", kind: .storage, severity: .info,
            title: text("One category dominates analyzed size"),
            detail: text("%@ takes up %@ of analyzed size%@."),
            detailArguments: [categoryName(dominantCategory.category), percentage(categoryRatio), analysis.scanState.isPartial ? partialSuffix() : ""],
            evidence: [InsightEvidence(source: "category", value: dominantCategory.category.rawValue)],
            confidence: 1.0, priority: 440
        )]
    }

    private func makeInsight(
        id: String,
        kind: InsightKind,
        severity: InsightSeverity,
        message: InsightRule.InsightMessage,
        arguments: String? = nil,
        evidence: [InsightEvidence],
        confidence: Double,
        priority: Int
    ) -> Insight {
        Insight(id: id, kind: kind, severity: severity, title: message.title, detail: message.detail,
                detailArguments: arguments.map { [$0] } ?? [], evidence: evidence, confidence: confidence, priority: priority)
    }

    private func semanticRole(for member: RelationshipMember) -> String {
        switch member.role {
        case .weights: return "modelWeights"
        case .attributes: return "attributeTable"
        case .geometry: return "geometry"
        case .projection: return "projection"
        case .index: return "index"
        case .tokenizer: return "tokenizer"
        case .configuration: return "configuration"
        case .manifest: return "manifest"
        case .lockfile: return "lockfile"
        case .source: return "sourceCode"
        case .primary, .project, .bibliography, .supporting: return member.role.rawValue
        }
    }

    private func roleDisplayName(_ role: String) -> String {
        let names: [String: String] = [
            "modelWeights": "model weights", "configuration": "configuration", "tokenizer": "tokenizer",
            "geometry": "geometry", "index": "index", "attributeTable": "attribute table",
            "projection": "projection", "manifest": "manifest", "lockfile": "lockfile"
        ]
        return MessageCatalog.shared.string(names[role] ?? role)
    }

    private func categoryName(_ category: FileCategory) -> String {
        let names: [FileCategory: String] = [.document: "Documents", .spreadsheet: "Spreadsheets", .image: "Images", .rawImage: "RAW images", .audio: "Audio", .video: "Videos", .archive: "Archives", .sourceCode: "Source Code", .configuration: "Configuration", .database: "Databases", .scientificData: "Scientific Data", .aiModel: "AI models", .threeD: "3D & CAD", .font: "Fonts", .executable: "Executables", .project: "Projects", .unknown: "Other"]
        return MessageCatalog.shared.string(names[category] ?? category.rawValue)
    }

    private func text(_ english: String) -> InsightLocalizedText {
        MessageCatalog.shared.text(english)
    }

    private func formatBytes(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func percentage(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }
    private func partialSuffix() -> String { MessageCatalog.shared.string(" (analyzed items only)") }
}
