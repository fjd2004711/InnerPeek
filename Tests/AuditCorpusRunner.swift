import Foundation

struct AuditManifest: Decodable {
    let version: Int
    let cases: [AuditCase]
}

struct AuditCase: Decodable {
    let id: String
    let kind: String
    let sourceKind: String
    let path: String
    let requiredRelationships: [String]
    let forbiddenRelationships: [String]
    let requiredInsights: [String]
    let forbiddenInsights: [String]
    let maxInsights: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, sourceKind, path, requiredRelationships, forbiddenRelationships
        case requiredInsights, forbiddenInsights, maxInsights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        sourceKind = try c.decode(String.self, forKey: .sourceKind)
        path = try c.decode(String.self, forKey: .path)
        requiredRelationships = try c.decodeIfPresent([String].self, forKey: .requiredRelationships) ?? []
        forbiddenRelationships = try c.decodeIfPresent([String].self, forKey: .forbiddenRelationships) ?? []
        requiredInsights = try c.decodeIfPresent([String].self, forKey: .requiredInsights) ?? []
        forbiddenInsights = try c.decodeIfPresent([String].self, forKey: .forbiddenInsights) ?? []
        maxInsights = try c.decodeIfPresent(Int.self, forKey: .maxInsights)
    }
}

@main
enum AuditCorpusRunner {
    struct CaseResult: Encodable {
        let id: String
        let kind: String
        let sourceKind: String
        let status: String
        let relationships: [String]
        let insights: [String]
        let durationMilliseconds: Int
        let reason: String?
    }

    struct Report: Encodable {
        let version: Int
        let casesDeclared: Int
        let casesExecuted: Int
        let casesUnavailable: Int
        let pass: Int
        let review: Int
        let errors: Int
        let totalInsights: Int
        let casesWithInsightOverflow: Int
        let quietFolderSuccess: Int
        let quietFolderCandidates: Int
        let expectedDetectionHits: Int
        let expectedDetectionTotal: Int
        let expectedInsightHits: Int
        let expectedInsightTotal: Int
        let forbiddenRelationshipTriggers: Int
        let unexpectedInsights: Int
        let slowestCase: SlowestCase?
        let results: [CaseResult]
    }

    struct SlowestCase: Encodable {
        let id: String
        let durationMilliseconds: Int
    }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else { throw RunnerError.usage }
        let corpusRoot = URL(fileURLWithPath: args[1], isDirectory: true)
        let manifestURL = URL(fileURLWithPath: args[2])
        let registryURL = URL(fileURLWithPath: args[3])
        let insightsURL = URL(fileURLWithPath: args.count > 4 ? args[4] : "Knowledge/insights.json")
        let manifest = try JSONDecoder().decode(AuditManifest.self, from: Data(contentsOf: manifestURL))
        let registry = FileTypeRegistry(data: try Data(contentsOf: registryURL))
        let recognizer = FileIntelligenceRecognizer(registry: registry, locale: Locale(identifier: "en_US"))
        let insightEngine = InsightEngine(data: try Data(contentsOf: insightsURL))

        var results: [CaseResult] = []
        var unavailable = 0
        for item in manifest.cases {
            let url = corpusRoot.appendingPathComponent(item.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                unavailable += 1
                results.append(CaseResult(id: item.id, kind: item.kind, sourceKind: item.sourceKind,
                                          status: "unavailable", relationships: [], insights: [], durationMilliseconds: 0,
                                          reason: "case source is not available"))
                continue
            }
            let started = Date()
            do {
                let analysis: FolderAnalysis
                if item.sourceKind == ContentSourceKind.zip.rawValue {
                    analysis = try ZIPContentProvider(archiveURL: url).semanticAnalysis(recognizer: recognizer)
                } else {
                    analysis = try FolderAnalyzer(recognizer: recognizer).analyze(folderURL: url)
                }
                let relationships = RelationshipEngine().detect(in: analysis).map { $0.type.rawValue }
                let detectedRelationships = Set(relationships)
                let insights = insightEngine.generate(for: analysis,
                                                      relationships: RelationshipEngine().detect(in: analysis)).map(\.id)
                let detectedInsights = Set(insights)
                let missingRelationships = item.requiredRelationships.filter { !detectedRelationships.contains($0) }
                let forbiddenRelationships = item.forbiddenRelationships.filter { detectedRelationships.contains($0) }
                let missingInsights = item.requiredInsights.filter { !detectedInsights.contains($0) }
                let forbiddenInsights = item.forbiddenInsights.filter { detectedInsights.contains($0) }
                let overflow = item.maxInsights.map { insights.count > $0 } ?? false
                let failures = missingRelationships.map { "missing relationship \($0)" }
                    + forbiddenRelationships.map { "forbidden relationship \($0)" }
                    + missingInsights.map { "missing insight \($0)" }
                    + forbiddenInsights.map { "forbidden insight \($0)" }
                    + (overflow ? ["insight overflow"] : [])
                results.append(CaseResult(id: item.id, kind: item.kind, sourceKind: item.sourceKind,
                                          status: failures.isEmpty ? "pass" : "review", relationships: relationships,
                                          insights: insights, durationMilliseconds: max(0, Int(Date().timeIntervalSince(started) * 1_000)),
                                          reason: failures.isEmpty ? nil : failures.joined(separator: "; ")))
            } catch {
                results.append(CaseResult(id: item.id, kind: item.kind, sourceKind: item.sourceKind,
                                          status: "error", relationships: [], insights: [], durationMilliseconds: max(0, Int(Date().timeIntervalSince(started) * 1_000)),
                                          reason: String(describing: error)))
            }
        }

        let executed = results.filter { $0.status != "unavailable" }
        let passed = executed.filter { $0.status == "pass" }.count
        let review = executed.filter { $0.status == "review" }.count
        let errors = executed.filter { $0.status == "error" }.count
        let allInsights = executed.flatMap(\.insights)
        let quietCandidates = manifest.cases.filter { $0.maxInsights == 0 }.map(\.id)
        let quietResults = executed.filter { quietCandidates.contains($0.id) }
        let quietSuccess = quietResults.filter { $0.insights.isEmpty }.count
        let slowest = executed.max { $0.durationMilliseconds < $1.durationMilliseconds }
        var expectedDetectionHits = 0
        var expectedDetectionTotal = 0
        var expectedInsightHits = 0
        var expectedInsightTotal = 0
        var forbiddenRelationshipTriggers = 0
        var unexpectedInsights = 0
        for item in manifest.cases {
            guard let result = results.first(where: { $0.id == item.id }) else { continue }
            let relationships = Set(result.relationships)
            let insights = Set(result.insights)
            expectedDetectionTotal += item.requiredRelationships.count
            expectedDetectionHits += item.requiredRelationships.filter { relationships.contains($0) }.count
            expectedInsightTotal += item.requiredInsights.count
            expectedInsightHits += item.requiredInsights.filter { insights.contains($0) }.count
            forbiddenRelationshipTriggers += item.forbiddenRelationships.filter { relationships.contains($0) }.count
            if item.requiredInsights.isEmpty, item.maxInsights == 0 {
                unexpectedInsights += result.insights.count
            }
        }
        let report = Report(version: 1, casesDeclared: manifest.cases.count, casesExecuted: executed.count,
                            casesUnavailable: unavailable, pass: passed, review: review, errors: errors,
                            totalInsights: allInsights.count, casesWithInsightOverflow: executed.filter { $0.insights.count > 3 }.count,
                            quietFolderSuccess: quietSuccess, quietFolderCandidates: quietResults.count,
                            expectedDetectionHits: expectedDetectionHits, expectedDetectionTotal: expectedDetectionTotal,
                            expectedInsightHits: expectedInsightHits, expectedInsightTotal: expectedInsightTotal,
                            forbiddenRelationshipTriggers: forbiddenRelationshipTriggers, unexpectedInsights: unexpectedInsights,
                            slowestCase: slowest.map { SlowestCase(id: $0.id, durationMilliseconds: $0.durationMilliseconds) }, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = try encoder.encode(report)
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    enum RunnerError: Error { case usage }
}
