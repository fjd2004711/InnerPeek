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
    let expectedVerdict: String?
    let expectedVerdictStatus: String?
    let forbiddenVerdicts: [String]
    let requiredEvidence: [String]
    let parityWith: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, sourceKind, path, requiredRelationships, forbiddenRelationships
        case requiredInsights, forbiddenInsights, maxInsights, expectedVerdict, expectedVerdictStatus
        case forbiddenVerdicts, requiredEvidence, parityWith
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
        expectedVerdict = try c.decodeIfPresent(String.self, forKey: .expectedVerdict)
        expectedVerdictStatus = try c.decodeIfPresent(String.self, forKey: .expectedVerdictStatus)
        forbiddenVerdicts = try c.decodeIfPresent([String].self, forKey: .forbiddenVerdicts) ?? []
        requiredEvidence = try c.decodeIfPresent([String].self, forKey: .requiredEvidence) ?? []
        parityWith = try c.decodeIfPresent(String.self, forKey: .parityWith)
    }
}

@main
enum AuditCorpusRunner {
    struct CaseResult: Encodable {
        let id: String
        let kind: String
        let sourceKind: String
        var status: String
        let relationships: [String]
        let insights: [String]
        let verdict: String?
        let verdictStatus: String?
        let evidencePaths: [String]
        let visibleInsightCount: Int
        let durationMilliseconds: Int
        var reason: String?
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
        let verdictFailures: Int
        let evidenceFailures: Int
        let parityFailures: Int
        let visibleInsightViolations: Int
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
                                          status: "unavailable", relationships: [], insights: [], verdict: nil, verdictStatus: nil,
                                          evidencePaths: [], visibleInsightCount: 0, durationMilliseconds: 0,
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
                let relationshipObjects = RelationshipEngine().detect(in: analysis)
                let relationships = relationshipObjects.map { $0.type.rawValue }
                let detectedRelationships = Set(relationships)
                let importantFiles = ImportantFileDetector(registry: registry).detect(in: analysis)
                let decision = SemanticVerdictEngine().decide(
                    analysis: analysis,
                    relationships: relationshipObjects,
                    insights: insightEngine.generate(for: analysis, relationships: relationshipObjects, importantFiles: importantFiles),
                    importantFiles: importantFiles
                )
                let insights = decision.insights.map(\.id)
                let detectedInsights = Set(insights)
                let missingRelationships = item.requiredRelationships.filter { !detectedRelationships.contains($0) }
                let forbiddenRelationships = item.forbiddenRelationships.filter { detectedRelationships.contains($0) }
                let missingInsights = item.requiredInsights.filter { !detectedInsights.contains($0) }
                let forbiddenInsights = item.forbiddenInsights.filter { detectedInsights.contains($0) }
                let overflow = item.maxInsights.map { insights.count > $0 } ?? false
                let verdict = decision.verdict
                let validPaths = Set(analysis.analyzedEntries.map(\.relativePath))
                let evidencePaths = decision.evidence.map(\.relativePath)
                let invalidEvidence = evidencePaths.contains { !validPaths.contains($0) || $0.hasPrefix("/") }
                let missingEvidence = item.requiredEvidence.filter { !evidencePaths.contains($0) }
                let expectedVerdictFailure = item.expectedVerdict.map { verdict?.archetype.rawValue != $0 } ?? false
                let statusFailure = item.expectedVerdictStatus.map { verdict?.status.rawValue != $0 } ?? false
                let forbiddenVerdict = item.forbiddenVerdicts.contains { verdict?.archetype.rawValue == $0 }
                let unsupportedVerdict = verdict != nil && verdict!.evidence.isEmpty
                let failures = missingRelationships.map { "missing relationship \($0)" }
                    + forbiddenRelationships.map { "forbidden relationship \($0)" }
                    + missingInsights.map { "missing insight \($0)" }
                    + forbiddenInsights.map { "forbidden insight \($0)" }
                    + (overflow ? ["insight overflow"] : [])
                    + (expectedVerdictFailure ? ["unexpected verdict"] : [])
                    + (statusFailure ? ["unexpected verdict status"] : [])
                    + (forbiddenVerdict ? ["forbidden verdict"] : [])
                    + missingEvidence.map { "missing evidence \($0)" }
                    + (invalidEvidence ? ["evidence outside analyzed entries"] : [])
                    + (unsupportedVerdict ? ["verdict has no evidence"] : [])
                results.append(CaseResult(id: item.id, kind: item.kind, sourceKind: item.sourceKind,
                                          status: failures.isEmpty ? "pass" : "review", relationships: relationships,
                                          insights: insights, verdict: verdict?.archetype.rawValue,
                                          verdictStatus: verdict?.status.rawValue, evidencePaths: evidencePaths,
                                          visibleInsightCount: insights.count, durationMilliseconds: max(0, Int(Date().timeIntervalSince(started) * 1_000)),
                                          reason: failures.isEmpty ? nil : failures.joined(separator: "; ")))
            } catch {
                results.append(CaseResult(id: item.id, kind: item.kind, sourceKind: item.sourceKind,
                                          status: "error", relationships: [], insights: [], verdict: nil, verdictStatus: nil,
                                          evidencePaths: [], visibleInsightCount: 0, durationMilliseconds: max(0, Int(Date().timeIntervalSince(started) * 1_000)),
                                          reason: String(describing: error)))
            }
        }

        var parityFailures = 0
        for index in results.indices {
            guard let peerID = manifest.cases.first(where: { $0.id == results[index].id })?.parityWith,
                  let peer = results.first(where: { $0.id == peerID }),
                  results[index].status != "unavailable", peer.status != "unavailable" else { continue }
            let differs = results[index].verdict != peer.verdict ||
                results[index].verdictStatus != peer.verdictStatus ||
                Set(results[index].insights) != Set(peer.insights) ||
                Set(results[index].evidencePaths) != Set(peer.evidencePaths)
            guard differs else { continue }
            parityFailures += 1
            results[index].status = "review"
            let note = "semantic parity mismatch with \(peerID)"
            results[index].reason = [results[index].reason, note].compactMap { $0 }.joined(separator: "; ")
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
        var verdictFailures = 0
        var evidenceFailures = 0
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
            if item.expectedVerdict != nil, result.verdict != item.expectedVerdict { verdictFailures += 1 }
            if !item.requiredEvidence.allSatisfy(result.evidencePaths.contains) { evidenceFailures += 1 }
        }
        let report = Report(version: 1, casesDeclared: manifest.cases.count, casesExecuted: executed.count,
                            casesUnavailable: unavailable, pass: passed, review: review, errors: errors,
                            totalInsights: allInsights.count, casesWithInsightOverflow: executed.filter { $0.insights.count > 3 }.count,
                            quietFolderSuccess: quietSuccess, quietFolderCandidates: quietResults.count,
                            expectedDetectionHits: expectedDetectionHits, expectedDetectionTotal: expectedDetectionTotal,
                            expectedInsightHits: expectedInsightHits, expectedInsightTotal: expectedInsightTotal,
                            forbiddenRelationshipTriggers: forbiddenRelationshipTriggers, unexpectedInsights: unexpectedInsights,
                            verdictFailures: verdictFailures, evidenceFailures: evidenceFailures,
                            parityFailures: parityFailures,
                            visibleInsightViolations: executed.filter { $0.visibleInsightCount > SemanticDecision.maximumVisibleInsights }.count,
                            slowestCase: slowest.map { SlowestCase(id: $0.id, durationMilliseconds: $0.durationMilliseconds) }, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = try encoder.encode(report)
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    enum RunnerError: Error { case usage }
}
