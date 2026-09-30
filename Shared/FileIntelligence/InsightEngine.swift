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

struct InsightLocalizedText: Codable, Sendable, Hashable {
    let english: String
    let simplifiedChinese: String

    enum CodingKeys: String, CodingKey {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
    }

    func value(for locale: Locale = .current, arguments: [String] = []) -> String {
        let template = locale.language.languageCode?.identifier == "zh" ? simplifiedChinese : english
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: locale, arguments: arguments.map { $0 as CVarArg })
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

    func localizedTitle(for locale: Locale = .current) -> String {
        title.value(for: locale)
    }

    func localizedDetail(for locale: Locale = .current) -> String? {
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
    static let singleFileConcentrationThreshold = 0.60
    static let topThreeConcentrationThreshold = 0.80
    static let categoryConcentrationThreshold = 0.75

    private let rules: [InsightRule]

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
                title: text("Detached HEAD detected", "检测到 HEAD 分离状态"),
                detail: text("No branch name is inferred from the local HEAD.", "不会从本地 HEAD 推断分支名称。"),
                detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".git/HEAD")],
                confidence: 1.0, priority: 760
            ))
        }
        if context.remote == nil {
            findings.append(Insight(
                id: "git-no-remote", kind: .completeness, severity: .info,
                title: text("Git metadata exists but no remote is configured", "存在 Git 元数据，但未配置远程仓库"),
                detail: nil, detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".git/HEAD")],
                confidence: 1.0, priority: 650
            ))
        }
        if context.hasGitHubActions {
            findings.append(Insight(
                id: "github-actions-workflow", kind: .completeness, severity: .positive,
                title: text("GitHub Actions workflow detected", "检测到 GitHub Actions 工作流"),
                detail: nil, detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".github/workflows")],
                confidence: 1.0, priority: 630
            ))
        }
        if !context.hasReadme {
            findings.append(Insight(
                id: "git-missing-readme", kind: .completeness, severity: .notice,
                title: text("Repository does not contain a README", "仓库不包含 README"),
                detail: nil, detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".git/HEAD")],
                confidence: 1.0, priority: 600
            ))
        }
        if !context.hasLicense {
            findings.append(Insight(
                id: "git-missing-license", kind: .completeness, severity: .notice,
                title: text("Repository does not contain a license", "仓库不包含许可证"),
                detail: nil, detailArguments: [], evidence: [InsightEvidence(source: "gitMetadata", value: ".git/HEAD")],
                confidence: 1.0, priority: 590
            ))
        }
        return findings
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
                title: text("Model weight file is empty", "模型权重文件为空"),
                detail: text("%@ is empty and may be a placeholder or test file.", "%@ 为空，可能只是占位文件或测试文件。"),
                detailArguments: [emptyModelWeights.map { $0.intelligence.fileName }.joined(separator: ", ")],
                evidence: emptyModelWeights.map { InsightEvidence(source: "filePath", value: $0.intelligence.fileName) },
                confidence: 1.0, priority: 980
            ))
        }

        if !emptyFiles.isEmpty {
            findings.append(Insight(
                id: "empty-files", kind: .anomaly,
                severity: emptyModelWeights.isEmpty ? .notice : .info,
                title: text("Empty files detected", "检测到空文件"),
                detail: text("%@ files have zero bytes.", "有 %@ 个文件大小为 0 字节。"),
                detailArguments: [String(emptyFiles.count)],
                evidence: emptyFiles.map { InsightEvidence(source: "filePath", value: $0.intelligence.fileName) },
                confidence: 1.0, priority: emptyModelWeights.isEmpty ? 850 : 400
            ))
        }

        let smallModels = modelWeightFiles.filter { $0.size > 0 && $0.size <= Self.smallModelWeightThreshold }
        if !smallModels.isEmpty {
            findings.append(Insight(
                id: "small-model-weights", kind: .anomaly, severity: .warning,
                title: text("Model weight file is unusually small", "模型权重文件异常小"),
                detail: text("%@ may be a placeholder or test file.", "%@ 可能只是占位文件或测试文件。"),
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
        guard files.count > 1, analysis.totalKnownFileSize > 0 else { return [] }
        let total = Double(analysis.totalKnownFileSize)
        let topRatio = Double(files[0].size) / total
        if topRatio >= Self.singleFileConcentrationThreshold {
            let duplicateKey = files[0].intelligence.fileName
            guard !existing.contains(where: { $0.evidence.contains { $0.value.contains(duplicateKey) } && $0.kind == .anomaly }) else { return [] }
            return [Insight(
                id: "largest-file-concentration", kind: .storage, severity: .notice,
                title: text("One file dominates analyzed size", "单个文件占据了大部分已分析空间"),
                detail: text("%@ accounts for %@ of analyzed size%@.", "%@ 占已分析空间的 %@%@。"),
                detailArguments: [files[0].intelligence.fileName, percentage(topRatio), analysis.scanState.isPartial ? partialSuffix() : ""],
                evidence: [InsightEvidence(source: "filePath", value: files[0].intelligence.fileName), InsightEvidence(source: "fileSize", value: String(files[0].size))],
                confidence: 1.0, priority: 560
            )]
        }

        let topThree = files.prefix(3)
        let topThreeRatio = Double(topThree.reduce(Int64(0), { $0 + $1.size })) / total
        if files.count >= 4, topThreeRatio >= Self.topThreeConcentrationThreshold {
            return [Insight(
                id: "top-three-concentration", kind: .storage, severity: .notice,
                title: text("A few files dominate analyzed size", "少数文件占据了大部分已分析空间"),
                detail: text("The largest %@ files account for %@ of analyzed size%@.", "最大的 %@ 个文件占已分析空间的 %@%@。"),
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
            title: text("One category dominates analyzed size", "一个类别占据了大部分已分析空间"),
            detail: text("%@ account for %@ of analyzed size%@.", "%@ 占已分析空间的 %@%@。"),
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
        let names: [String: (String, String)] = [
            "modelWeights": ("model weights", "模型权重"), "configuration": ("configuration", "配置"),
            "tokenizer": ("tokenizer", "tokenizer"), "geometry": ("geometry", "几何文件"),
            "index": ("index", "索引"), "attributeTable": ("attribute table", "属性表"),
            "projection": ("projection", "投影文件"), "manifest": ("manifest", "项目清单"),
            "lockfile": ("lockfile", "锁定文件")
        ]
        let pair = names[role] ?? (role, role)
        return Locale.current.language.languageCode?.identifier == "zh" ? pair.1 : pair.0
    }

    private func categoryName(_ category: FileCategory) -> String {
        let english: [FileCategory: String] = [.document: "Documents", .spreadsheet: "Spreadsheets", .image: "Images", .rawImage: "RAW images", .audio: "Audio", .video: "Videos", .archive: "Archives", .sourceCode: "Source Code", .configuration: "Configuration", .database: "Databases", .scientificData: "Scientific Data", .aiModel: "AI models", .threeD: "3D & CAD", .font: "Fonts", .executable: "Executables", .project: "Projects", .unknown: "Other"]
        let chinese: [FileCategory: String] = [.document: "文档", .spreadsheet: "电子表格", .image: "图像", .rawImage: "RAW 图像", .audio: "音频", .video: "视频", .archive: "归档", .sourceCode: "源代码", .configuration: "配置", .database: "数据库", .scientificData: "科学数据", .aiModel: "AI 模型", .threeD: "3D 与 CAD", .font: "字体", .executable: "可执行文件", .project: "项目", .unknown: "其他"]
        return Locale.current.language.languageCode?.identifier == "zh" ? (chinese[category] ?? category.rawValue) : (english[category] ?? category.rawValue)
    }

    private func text(_ english: String, _ chinese: String) -> InsightLocalizedText {
        InsightLocalizedText(english: english, simplifiedChinese: chinese)
    }

    private func formatBytes(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func percentage(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }
    private func partialSuffix() -> String { Locale.current.language.languageCode?.identifier == "zh" ? "（仅限已分析项目）" : " (analyzed items only)" }
}
