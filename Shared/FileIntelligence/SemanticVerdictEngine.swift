import Foundation

/// The stable, user-facing archetypes that can be proven from bounded analysis.
enum SemanticArchetype: String, Sendable, Hashable {
    case transformerModelPackage
    case shapefileDataset
    case nodeProject
    case pythonProject
    case latexResearchProject
    case rustPackage
    case goModule
    case xcodeProject
    case photoCollection
    case gitRepository
    case githubRepository
    case gitlabRepository
    case bitbucketRepository
    case gitMetadata
    case githubMetadataProject
}

enum SemanticVerdictStatus: String, Sendable, Hashable {
    case complete
    case warning
    case detected
}

/// Support is deliberately categorical. It communicates rule support without
/// presenting an invented probability to the user.
enum SemanticSupport: String, Sendable, Hashable {
    case strong
    case supported
    case weak
}

enum SemanticEvidenceKind: String, Sendable, Hashable {
    case relationshipMember
    case insight
    case companionFile
    case importantFile
    case repositoryMetadata
}

/// A provider-neutral reference to an entry already admitted to FolderAnalysis.
struct SemanticEvidence: Sendable, Hashable {
    let relativePath: String
    let kind: SemanticEvidenceKind
    let sourceID: String
    let reason: InsightLocalizedText

    func localizedReason(for locale: Locale = .current) -> String {
        reason.value(for: locale)
    }
}

struct SemanticVerdict: Sendable, Hashable {
    let id: String
    let archetype: SemanticArchetype
    let title: InsightLocalizedText
    let summary: InsightLocalizedText
    let status: SemanticVerdictStatus
    let support: SemanticSupport
    let evidence: [SemanticEvidence]

    func localizedTitle(for locale: Locale = .current) -> String {
        title.value(for: locale)
    }

    func localizedSummary(for locale: Locale = .current) -> String {
        summary.value(for: locale)
    }
}

/// A single bounded presentation result for Quick Look. It does not retain
/// filesystem URLs and is identical for equivalent folder and ZIP analyses.
struct SemanticDecision: Sendable, Hashable {
    static let maximumVisibleInsights = 3
    static let maximumVisibleEvidence = 5

    let verdict: SemanticVerdict?
    let insights: [Insight]
    let importantFiles: [ImportantFile]
    let evidence: [SemanticEvidence]
    /// Repository context composes with, rather than replaces, a stronger
    /// project semantic such as Transformer or Node.
    let repositoryContext: GitRepositoryContext?
}

/// Converts existing structured intelligence into a concise, explainable
/// decision layer. It never reads the filesystem or archive members.
struct SemanticVerdictEngine: Sendable {
    func decide(
        analysis: FolderAnalysis,
        relationships: [DetectedRelationship],
        insights: [Insight],
        importantFiles: [ImportantFile]
    ) -> SemanticDecision {
        let visibleInsights = insights.sorted(by: insightPriority).prefix(SemanticDecision.maximumVisibleInsights).map { $0 }
        let domainVerdict = verdict(for: analysis, relationships: relationships, insights: visibleInsights)
        let repositoryVerdict = repositoryVerdict(for: analysis.repositoryContext)
        let verdict = domainVerdict ?? repositoryVerdict
        let evidence = combinedEvidence(
            verdict: verdict,
            insights: visibleInsights,
            importantFiles: importantFiles,
            analysis: analysis,
            repositoryContext: analysis.repositoryContext
        )
        return SemanticDecision(
            verdict: verdict,
            insights: visibleInsights,
            importantFiles: importantFiles,
            evidence: evidence,
            repositoryContext: domainVerdict == nil ? nil : analysis.repositoryContext
        )
    }

    private func verdict(
        for analysis: FolderAnalysis,
        relationships: [DetectedRelationship],
        insights: [Insight]
    ) -> SemanticVerdict? {
        if let relationship = primaryRelationship(in: relationships),
           let archetype = archetype(for: relationship.type) {
            var relationshipEvidence = relationship.members.compactMap { member in
                evidence(for: member, sourceID: relationship.type.rawValue, analysis: analysis)
            }
            // A non-generic claim is only allowed when its supporting entries
            // survived the same bounded analysis that produced the relationship.
            guard !relationshipEvidence.isEmpty else { return nil }
            let relatedDocker = relationships.first { $0.type == .docker }
            if archetype == .nodeProject, let relatedDocker {
                relationshipEvidence += relatedDocker.members.compactMap {
                    evidence(for: $0, sourceID: relatedDocker.type.rawValue, analysis: analysis)
                }
                var seen = Set<String>()
                relationshipEvidence = relationshipEvidence.filter { seen.insert($0.relativePath).inserted }
            }
            let hasWarning = warningApplies(to: relationship, insights: insights, analysis: analysis)
            let isComplete = !hasWarning && completenessApplies(to: relationship, insights: insights)
            return SemanticVerdict(
                id: archetype.rawValue,
                archetype: archetype,
                title: archetypeTitle(archetype),
                summary: archetypeSummary(
                    archetype,
                    status: hasWarning ? .warning : (isComplete ? .complete : .detected),
                    hasDocker: relatedDocker != nil
                ),
                status: hasWarning ? .warning : (isComplete ? .complete : .detected),
                support: relationship.confidence >= 0.95 ? .strong : .supported,
                evidence: relationshipEvidence
            )
        }

        if let pair = rawJPEGCompanionPair(in: analysis) {
            return SemanticVerdict(
                id: SemanticArchetype.photoCollection.rawValue,
                archetype: .photoCollection,
                title: text("Photo collection", "照片集合"),
                summary: text("RAW/JPEG companion files detected", "检测到 RAW/JPEG 配对文件"),
                status: .detected,
                support: .strong,
                evidence: pair.map {
                    SemanticEvidence(relativePath: $0.relativePath, kind: .companionFile, sourceID: "raw-jpeg-pair",
                                     reason: text("RAW/JPEG companion", "RAW/JPEG 配对"))
                }
            )
        }
        // A generic folder stays quiet: no inferred identity and no filler verdict.
        return nil
    }

    private func repositoryVerdict(for context: GitRepositoryContext?) -> SemanticVerdict? {
        guard let context else { return nil }
        let archetype: SemanticArchetype
        switch context.state {
        case .repository:
            switch context.remote?.provider {
            case .github: archetype = .githubRepository
            case .gitlab: archetype = .gitlabRepository
            case .bitbucket: archetype = .bitbucketRepository
            default: archetype = .gitRepository
            }
        case .metadataDetected: archetype = .gitMetadata
        case .githubMetadataOnly: archetype = .githubMetadataProject
        }
        let evidence = context.evidence.map {
            SemanticEvidence(relativePath: $0.relativePath, kind: .repositoryMetadata,
                             sourceID: "git", reason: $0.reason)
        }
        guard !evidence.isEmpty else { return nil }
        return SemanticVerdict(id: archetype.rawValue, archetype: archetype, title: context.title,
                               summary: context.summary,
                               status: context.isRepository ? .detected : .warning,
                               support: context.isRepository ? .strong : .supported,
                               evidence: evidence)
    }

    private func primaryRelationship(in relationships: [DetectedRelationship]) -> DetectedRelationship? {
        relationships
            .filter { archetype(for: $0.type) != nil }
            .sorted {
                let left = archetypePriority($0.type)
                let right = archetypePriority($1.type)
                if left != right { return left > right }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.type.rawValue < $1.type.rawValue
            }
            .first
    }

    private func archetype(for relationship: RelationshipType) -> SemanticArchetype? {
        switch relationship {
        case .transformer: return .transformerModelPackage
        case .shapefile: return .shapefileDataset
        case .node: return .nodeProject
        case .python: return .pythonProject
        case .latex: return .latexResearchProject
        case .rust: return .rustPackage
        case .go: return .goModule
        case .xcode: return .xcodeProject
        case .docker: return nil // Docker enriches a project verdict; it is not one by itself.
        }
    }

    private func archetypePriority(_ type: RelationshipType) -> Int {
        switch type {
        case .transformer: return 100
        case .shapefile: return 95
        case .node: return 90
        case .python: return 85
        case .latex: return 80
        case .rust, .go, .xcode: return 75
        case .docker: return 0
        }
    }

    private func warningApplies(to relationship: DetectedRelationship, insights: [Insight], analysis: FolderAnalysis) -> Bool {
        let relationshipPaths = Set(relationship.members.map(\.relativePath))
        return insights.contains { insight in
            guard insight.severity == .warning else { return false }
            let paths = evidencePaths(for: insight, in: analysis)
            return !paths.isEmpty && !relationshipPaths.isDisjoint(with: paths)
        }
    }

    private func completenessApplies(to relationship: DetectedRelationship, insights: [Insight]) -> Bool {
        let prefix: String
        switch relationship.type {
        case .transformer: prefix = "transformer-model-completeness"
        case .shapefile: prefix = "shapefile-completeness"
        default: return false
        }
        return insights.contains { $0.severity == .positive && $0.id.hasPrefix(prefix) }
    }

    private func rawJPEGCompanionPair(in analysis: FolderAnalysis) -> [AnalyzedEntry]? {
        let files = analysis.analyzedEntries.filter { !$0.isDirectory }
        let grouped = Dictionary(grouping: files) { entry in
            (entry.relativePath as NSString).deletingPathExtension.lowercased()
        }
        for path in grouped.keys.sorted() {
            guard let entries = grouped[path],
                  let raw = entries.first(where: { $0.intelligence?.category == .rawImage }),
                  let jpeg = entries.first(where: { $0.intelligence?.category == .image }) else { continue }
            return [raw, jpeg].sorted { $0.relativePath < $1.relativePath }
        }
        return nil
    }

    private func combinedEvidence(
        verdict: SemanticVerdict?,
        insights: [Insight],
        importantFiles: [ImportantFile],
        analysis: FolderAnalysis,
        repositoryContext: GitRepositoryContext?
    ) -> [SemanticEvidence] {
        var all = verdict?.evidence ?? []
        if let repositoryContext {
            all += repositoryContext.evidence.map {
                SemanticEvidence(relativePath: $0.relativePath, kind: .repositoryMetadata,
                                 sourceID: "git", reason: $0.reason)
            }
        }
        for insight in insights {
            all += evidence(for: insight, analysis: analysis)
        }
        let entriesByPath = Set(analysis.analyzedEntries.map(\.relativePath))
        for important in importantFiles {
            guard let entry = analysis.analyzedEntries.first(where: {
                !$0.isDirectory && $0.url == important.file.url
            }), entriesByPath.contains(entry.relativePath) else { continue }
            all.append(SemanticEvidence(relativePath: entry.relativePath, kind: .importantFile,
                                        sourceID: important.reason.rawValue,
                                        reason: text("Important file", "重要文件")))
        }
        let repositoryPaths = Set(repositoryContext?.evidence.map(\.relativePath) ?? [])
        var paths = Set<String>()
        return all.filter {
            (entriesByPath.contains($0.relativePath) || repositoryPaths.contains($0.relativePath)) &&
                paths.insert($0.relativePath).inserted
        }
            .prefix(SemanticDecision.maximumVisibleEvidence)
            .map { $0 }
    }

    private func evidence(for member: RelationshipMember, sourceID: String, analysis: FolderAnalysis) -> SemanticEvidence? {
        guard analysis.analyzedEntries.contains(where: { $0.relativePath == member.relativePath }) else { return nil }
        return SemanticEvidence(relativePath: member.relativePath, kind: .relationshipMember, sourceID: sourceID,
                                reason: text("Detected structure", "检测到的结构"))
    }

    private func evidence(for insight: Insight, analysis: FolderAnalysis) -> [SemanticEvidence] {
        evidencePaths(for: insight, in: analysis).map {
            SemanticEvidence(relativePath: $0, kind: .insight, sourceID: insight.id,
                             reason: text("Supports insight", "支持该洞察"))
        }
    }

    private func evidencePaths(for insight: Insight, in analysis: FolderAnalysis) -> [String] {
        let entries = analysis.analyzedEntries.filter { !$0.isDirectory }
        var paths = Set<String>()
        for item in insight.evidence {
            let raw: String
            switch item.source {
            case "relationshipMember": raw = item.value
            case "filePath": raw = item.value
            case "fileSize": raw = item.value.split(separator: "=", maxSplits: 1).first.map(String.init) ?? item.value
            case "gitMetadata":
                if let context = analysis.repositoryContext,
                   context.evidence.contains(where: { $0.relativePath == item.value }) {
                    paths.insert(item.value)
                }
                continue
            default: continue
            }
            if let exact = entries.first(where: { $0.relativePath == raw }) {
                paths.insert(exact.relativePath)
            } else if let named = entries.first(where: { $0.name == raw }) {
                paths.insert(named.relativePath)
            }
        }
        return paths.sorted()
    }

    private func insightPriority(_ lhs: Insight, _ rhs: Insight) -> Bool {
        if lhs.severity.rank != rhs.severity.rank { return lhs.severity.rank > rhs.severity.rank }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.id < rhs.id
    }

    private func archetypeTitle(_ archetype: SemanticArchetype) -> InsightLocalizedText {
        switch archetype {
        case .transformerModelPackage: return text("Transformer model package", "Transformer 模型包")
        case .shapefileDataset: return text("Shapefile dataset", "Shapefile 数据集")
        case .nodeProject: return text("Node.js project", "Node.js 项目")
        case .pythonProject: return text("Python project", "Python 项目")
        case .latexResearchProject: return text("LaTeX research project", "LaTeX 研究项目")
        case .rustPackage: return text("Rust package", "Rust 软件包")
        case .goModule: return text("Go module", "Go 模块")
        case .xcodeProject: return text("Xcode project", "Xcode 项目")
        case .photoCollection: return text("Photo collection", "照片集合")
        case .gitRepository: return text("Git Repository", "Git 仓库")
        case .githubRepository: return text("GitHub Repository", "GitHub 仓库")
        case .gitlabRepository: return text("GitLab Repository", "GitLab 仓库")
        case .bitbucketRepository: return text("Bitbucket Repository", "Bitbucket 仓库")
        case .gitMetadata: return text("Git metadata detected", "检测到 Git 元数据")
        case .githubMetadataProject: return text("GitHub project metadata detected", "检测到 GitHub 项目元数据")
        }
    }

    private func archetypeSummary(_ archetype: SemanticArchetype, status: SemanticVerdictStatus, hasDocker: Bool) -> InsightLocalizedText {
        if status == .warning, archetype == .transformerModelPackage {
            return text("Possible abnormal model weights", "模型权重可能异常")
        }
        if status == .complete {
            return text("Structure complete", "结构完整")
        }
        if archetype == .nodeProject, hasDocker {
            return text("Docker configuration detected", "检测到 Docker 配置")
        }
        if archetype == .latexResearchProject {
            return text("Bibliography and figures detected", "检测到参考文献与图表")
        }
        return text("Related structure detected", "检测到关联结构")
    }

    private func text(_ english: String, _ chinese: String) -> InsightLocalizedText {
        InsightLocalizedText(english: english, simplifiedChinese: chinese)
    }
}
