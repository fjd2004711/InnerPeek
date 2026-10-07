import Foundation

private struct RecognitionKnowledge: Decodable, Sendable {
    struct Evidence: Decodable, Sendable {
        let type: RecognitionEvidenceType
        let path: String?
        let file: String?
        let key: String?
        let contains: String?
        let extensions: [String]?
        let minimumFiles: Int?
        let minimumShare: Double?
        let module: String?
        let patterns: [String]?
        let weight: Double
    }

    struct Visual: Decodable, Sendable { let icon: String }

    struct Fact: Decodable, Sendable {
        let id: String
        let kind: ProjectFactKind
        let name: InsightLocalizedText
        let visual: Visual?
        let group: String?
        let supersedes: [String]
        let implies: [String]
        let evidence: [Evidence]

        enum CodingKeys: String, CodingKey { case id, kind, name, visual, group, supersedes, implies, evidence }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            kind = try values.decode(ProjectFactKind.self, forKey: .kind)
            name = try values.decode(InsightLocalizedText.self, forKey: .name)
            visual = try values.decodeIfPresent(Visual.self, forKey: .visual)
            group = try values.decodeIfPresent(String.self, forKey: .group)
            supersedes = try values.decodeIfPresent([String].self, forKey: .supersedes) ?? []
            implies = try values.decodeIfPresent([String].self, forKey: .implies) ?? []
            evidence = try values.decode([Evidence].self, forKey: .evidence)
        }
    }

    let detectionThreshold: Double
    let conflictMargin: Double
    let facts: [Fact]

    static let empty = RecognitionKnowledge(detectionThreshold: 0.5, conflictMargin: 0.05, facts: [])
}

/// Evaluates the declarative project-recognition knowledge against one folder.
///
/// Reads are bounded and local: the root directory listing, a few nested path
/// existence checks, and at most 256 KB of each known root-level manifest. It
/// never recurses, never runs tools, and a malformed manifest only means that
/// manifest contributes no evidence.
struct ProjectRecognizer: Sendable {
    private static let maximumManifestBytes = 256 * 1_024
    private static let maximumRootEntries = 2_000
    /// An implied fact is slightly less certain than the fact that implies it.
    private static let impliedScoreFactor = 0.9

    private let knowledge: RecognitionKnowledge

    init(data: Data? = nil) {
        let bundled = Bundle(for: FileTypeRegistry.self).url(forResource: "project-recognition", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Knowledge/project-recognition.json")
        knowledge = (data ?? bundled ?? (try? Data(contentsOf: sourceURL))).flatMap {
            try? JSONDecoder().decode(RecognitionKnowledge.self, from: $0)
        } ?? .empty
    }

    /// `entries` is the bounded file list the folder analysis already collected;
    /// extension evidence reuses it so recognition never walks the folder again.
    func recognize(folderURL: URL, entries: [AnalyzedEntry] = []) -> ProjectRecognition {
        guard !knowledge.facts.isEmpty else { return .empty }
        let workspace = RecognitionWorkspace(
            root: folderURL, maximumEntries: Self.maximumRootEntries, maximumBytes: Self.maximumManifestBytes,
            analyzedFiles: entries.filter { !$0.isDirectory }.map { ($0.relativePath, ($0.intelligence?.fileExtension ?? "").lowercased()) }
        )
        let definitions = Dictionary(knowledge.facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        struct Candidate {
            var score: Double
            var evidence: [RecognitionEvidence]
            var impliedBy: [String]
        }
        var candidates: [String: Candidate] = [:]
        for fact in knowledge.facts {
            let matches = fact.evidence.compactMap { evaluate($0, in: workspace) }
            guard !matches.isEmpty else { continue }
            let score = 1 - matches.reduce(1.0) { $0 * (1 - $1.weight) }
            guard score >= knowledge.detectionThreshold else { continue }
            candidates[fact.id] = Candidate(score: score, evidence: matches, impliedBy: [])
        }

        // Single-hop implication: only explicitly detected facts imply others.
        let explicit = knowledge.facts.compactMap { fact in candidates[fact.id].map { (fact, $0) } }
        for (fact, source) in explicit {
            for target in fact.implies where definitions[target] != nil {
                let score = source.score * Self.impliedScoreFactor
                guard score >= knowledge.detectionThreshold else { continue }
                var candidate = candidates[target] ?? Candidate(score: 0, evidence: [], impliedBy: [])
                candidate.score = max(candidate.score, score)
                candidate.evidence += source.evidence.filter { !candidate.evidence.contains($0) }
                if !candidate.impliedBy.contains(fact.id) { candidate.impliedBy.append(fact.id) }
                candidates[target] = candidate
            }
        }

        // Exclusive groups: the strongest member wins; near-ties are reported
        // as a conflict and neither is allowed to claim high confidence.
        var demoted = Set<String>()
        var capped = Set<String>()
        var conflicts: [FactConflict] = []
        let grouped = Dictionary(grouping: knowledge.facts.filter { candidates[$0.id] != nil && $0.group != nil }, by: { $0.group! })
        for group in grouped.keys.sorted() {
            let members = grouped[group]!.sorted {
                let left = candidates[$0.id]!.score, right = candidates[$1.id]!.score
                return left != right ? left > right : $0.id < $1.id
            }
            let top = candidates[members[0].id]!.score
            var tied = [members[0].id]
            for member in members.dropFirst() {
                if candidates[member.id]!.score >= top - knowledge.conflictMargin {
                    tied.append(member.id)
                } else {
                    demoted.insert(member.id)
                }
            }
            if tied.count > 1 {
                conflicts.append(FactConflict(group: group, factIDs: tied))
                capped.formUnion(tied)
            }
        }
        // Supersession: a detected framework/language makes the one it builds on supporting.
        for fact in knowledge.facts where candidates[fact.id] != nil {
            for superseded in fact.supersedes where candidates[superseded] != nil { demoted.insert(superseded) }
        }

        let kindOrder = Dictionary(uniqueKeysWithValues: ProjectFactKind.allCases.enumerated().map { ($1, $0) })
        let facts = knowledge.facts.compactMap { fact -> DetectedFact? in
            guard let candidate = candidates[fact.id] else { return nil }
            var confidence = ProjectIdentityConfidence(score: candidate.score)
            if capped.contains(fact.id), confidence == .high { confidence = .medium }
            return DetectedFact(
                id: fact.id, kind: fact.kind,
                name: fact.name,
                score: candidate.score, confidence: confidence,
                role: demoted.contains(fact.id) ? .supporting : .primary,
                evidence: candidate.evidence, impliedBy: candidate.impliedBy,
                iconKey: fact.visual?.icon
            )
        }.sorted {
            if $0.kind != $1.kind { return kindOrder[$0.kind]! < kindOrder[$1.kind]! }
            if $0.role != $1.role { return $0.role == .primary }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id < $1.id
        }
        return ProjectRecognition(facts: facts, conflicts: conflicts)
    }

    private func evaluate(_ rule: RecognitionKnowledge.Evidence, in workspace: RecognitionWorkspace) -> RecognitionEvidence? {
        switch rule.type {
        case .pathExists:
            guard let path = rule.path, let actual = workspace.match(path: path) else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: actual, key: nil, weight: rule.weight)
        case .manifestDependency:
            guard let file = rule.file, let key = rule.key,
                  let actual = workspace.actualName(of: file),
                  workspace.dependencies(of: actual)?.contains(RecognitionWorkspace.normalize(key)) == true else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: actual, key: key, weight: rule.weight)
        case .manifestKey:
            guard let file = rule.file, let key = rule.key,
                  let actual = workspace.actualName(of: file),
                  let keys = workspace.keys(of: actual) else { return nil }
            let wanted = key.lowercased()
            guard keys.contains(where: { $0 == wanted || $0.hasPrefix(wanted + ".") }) else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: actual, key: key, weight: rule.weight)
        case .manifestText:
            guard let file = rule.file, let needle = rule.contains,
                  let actual = workspace.actualName(of: file),
                  workspace.text(of: actual)?.range(of: needle, options: .caseInsensitive) != nil else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: actual, key: needle, weight: rule.weight)
        case .fileMatch:
            guard let patterns = rule.patterns, !patterns.isEmpty,
                  let match = workspace.fileNameMatch(patterns: patterns.map { $0.lowercased() }, minimumFiles: rule.minimumFiles ?? 1) else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: match.path, key: match.pattern, weight: rule.weight, matchedFiles: match.count)
        case .sourceImport:
            guard let extensions = rule.extensions, !extensions.isEmpty, let module = rule.module,
                  let match = workspace.importMatch(extensions: Set(extensions.map { $0.lowercased() }), module: module,
                                                    minimumFiles: rule.minimumFiles ?? 1) else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: match.path, key: module, weight: rule.weight,
                                       matchedFiles: match.count)
        case .extensionShare:
            guard let extensions = rule.extensions, !extensions.isEmpty,
                  let match = workspace.extensionMatch(extensions: Set(extensions.map { $0.lowercased() }),
                                                       minimumFiles: rule.minimumFiles ?? 1,
                                                       minimumShare: rule.minimumShare ?? 0) else { return nil }
            return RecognitionEvidence(type: rule.type, relativePath: match.path, key: match.extension, weight: rule.weight,
                                       matchedFiles: match.count, share: match.share)
        }
    }
}

/// Per-run view of one folder: lazily parsed, cached, bounded manifests.
private final class RecognitionWorkspace {
    private let root: URL
    private let maximumBytes: Int
    private let entries: [String]
    private let lowered: [String: String]
    private var texts: [String: String?] = [:]
    private var dependencyNames: [String: Set<String>?] = [:]
    private var keyNames: [String: Set<String>?] = [:]
    private let analyzedFiles: [(path: String, ext: String)]
    private var importCache: [String: [(path: String, modules: Set<String>)]] = [:]
    private static let maximumImportFiles = 60
    private static let maximumImportBytes = 8 * 1_024

    init(root: URL, maximumEntries: Int, maximumBytes: Int, analyzedFiles: [(String, String)]) {
        self.analyzedFiles = analyzedFiles.sorted { $0.0 < $1.0 }.map { (path: $0.0, ext: $0.1) }
        self.root = root
        self.maximumBytes = maximumBytes
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        entries = Array(names.prefix(maximumEntries))
        lowered = Dictionary(entries.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func lower(_ name: String) -> String { name.lowercased() }

    static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: ".", with: "-")
    }

    /// Succeeds when enough of the analysed files carry one of `extensions`;
    /// reports the first such file (by path) so the evidence stays traceable.
    func extensionMatch(extensions: Set<String>, minimumFiles: Int, minimumShare: Double) -> (path: String, extension: String, count: Int, share: Double)? {
        let matches = analyzedFiles.filter { extensions.contains($0.ext) }
        guard let first = matches.first, matches.count >= minimumFiles else { return nil }
        let share = Double(matches.count) / Double(analyzedFiles.count)
        guard share >= minimumShare else { return nil }
        return (first.path, first.ext, matches.count, share)
    }

    /// Succeeds when at least `minimumFiles` analysed files have a name matching one of `patterns`.
    /// Only the file name is matched, never the directory, and only already-analysed entries are used.
    func fileNameMatch(patterns: [String], minimumFiles: Int) -> (path: String, pattern: String, count: Int)? {
        var first: (path: String, pattern: String)?
        var count = 0
        for file in analyzedFiles {
            let name = (file.path as NSString).lastPathComponent.lowercased()
            guard let pattern = patterns.first(where: { Self.glob($0, name) }) else { continue }
            count += 1
            if first == nil { first = (file.path, pattern) }
        }
        guard let first, count >= minimumFiles else { return nil }
        return (first.path, first.pattern, count)
    }

    /// Succeeds when at least `minimumFiles` of the first 60 matching source files
    /// import `module` in their first 8 KB. Reports the first such file.
    func importMatch(extensions: Set<String>, module: String, minimumFiles: Int) -> (path: String, count: Int)? {
        let key = extensions.sorted().joined(separator: ",")
        let scanned: [(path: String, modules: Set<String>)]
        if let cached = importCache[key] {
            scanned = cached
        } else {
            scanned = analyzedFiles.filter { extensions.contains($0.ext) }.prefix(Self.maximumImportFiles).map { file in
                (file.path, Self.importedModules(in: readPrefix(of: file.path), extension: file.ext))
            }
            importCache[key] = scanned
        }
        let wanted = module.lowercased()
        let hits = scanned.filter { entry in
            entry.modules.contains { $0 == wanted || $0.hasPrefix(wanted + ".") || $0.hasPrefix(wanted + "/") }
        }
        guard let first = hits.first, hits.count >= minimumFiles else { return nil }
        return (first.path, hits.count)
    }

    private func readPrefix(of relativePath: String) -> String {
        let url = root.appendingPathComponent(relativePath)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.maximumImportBytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Normalized module names a source file imports. Only import statements at the
    /// start of a line are read, so commented-out or quoted imports do not count.
    static func importedModules(in text: String, extension ext: String) -> Set<String> {
        var modules = Set<String>()
        for rawLine in text.split(whereSeparator: \.isNewline).prefix(400) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            switch ext {
            case "swift":
                var body = Substring(line)
                for attribute in ["@testable ", "@_exported ", "@preconcurrency "] where body.hasPrefix(attribute) { body = body.dropFirst(attribute.count) }
                guard body.hasPrefix("import ") else { continue }
                var parts = body.dropFirst(7).split(whereSeparator: \.isWhitespace)
                if let first = parts.first, ["struct", "class", "enum", "protocol", "func", "var", "let", "typealias"].contains(String(first)) { parts.removeFirst() }
                if let path = parts.first, let module = path.split(separator: ".").first { modules.insert(lower(String(module))) }
            case "py":
                if line.hasPrefix("import ") {
                    for item in line.dropFirst(7).split(separator: ",") {
                        let name = item.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                        if let module = name.split(separator: ".").first { modules.insert(lower(String(module))) }
                    }
                } else if line.hasPrefix("from "), line.contains(" import ") {
                    let name = line.dropFirst(5).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                    if !name.hasPrefix("."), let module = name.split(separator: ".").first { modules.insert(lower(String(module))) }
                }
            case "js", "jsx", "mjs", "cjs", "ts", "tsx":
                for marker in ["from \"", "from '", "require(\"", "require('", "import \"", "import '"] {
                    guard line.hasPrefix("import") || line.hasPrefix("export") || line.contains("require("),
                          let range = line.range(of: marker) else { continue }
                    let rest = line[range.upperBound...]
                    guard let end = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
                    let specifier = String(rest[..<end])
                    guard !specifier.hasPrefix("."), !specifier.hasPrefix("/") else { continue }
                    let segments = specifier.split(separator: "/", omittingEmptySubsequences: true)
                    let name = specifier.hasPrefix("@") ? segments.prefix(2).joined(separator: "/") : (segments.first.map(String.init) ?? "")
                    if !name.isEmpty { modules.insert(lower(name)) }
                }
            case "java", "kt", "kts":
                guard line.hasPrefix("import ") else { continue }
                var path = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("static ") { path = String(path.dropFirst(7)) }
                path = path.trimmingCharacters(in: CharacterSet(charactersIn: "; "))
                if !path.isEmpty { modules.insert(lower(path)) }
            default:
                continue
            }
        }
        return modules
    }

    func actualName(of file: String) -> String? { lowered[file.lowercased()] }

    func match(path: String) -> String? {
        if path.contains("/") {
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count <= 3, !components.contains("..") else { return nil }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) ? path : nil
        }
        if path.contains("*") {
            let pattern = path.lowercased()
            return entries.first { Self.glob(pattern, $0.lowercased()) }
        }
        return lowered[path.lowercased()]
    }

    func text(of actual: String) -> String? {
        if let cached = texts[actual] { return cached }
        let url = root.appendingPathComponent(actual)
        var result: String?
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
           values.isRegularFile == true, values.isSymbolicLink != true,
           (values.fileSize ?? 0) <= maximumBytes,
           let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            result = String(data: data, encoding: .utf8)
        }
        texts[actual] = result
        return result
    }

    /// Normalized dependency names, or `nil` when the file is absent, oversized,
    /// malformed, or not a supported manifest format.
    func dependencies(of actual: String) -> Set<String>? {
        if let cached = dependencyNames[actual] { return cached }
        var result: Set<String>?
        if let text = text(of: actual) {
            switch actual.lowercased() {
            case "package.json": result = Self.packageJSONDependencies(text)
            case "requirements.txt": result = Self.requirementsDependencies(text)
            case "pyproject.toml": result = Self.pyprojectDependencies(Self.scanTOML(text))
            case "cargo.toml": result = Self.cargoDependencies(Self.scanTOML(text))
            case "go.mod": result = Self.goModDependencies(text)
            default: result = nil
            }
        }
        dependencyNames[actual] = result
        return result
    }

    /// Top-level JSON keys, or TOML table names, lowercased.
    func keys(of actual: String) -> Set<String>? {
        if let cached = keyNames[actual] { return cached }
        var result: Set<String>?
        if let text = text(of: actual) {
            switch actual.lowercased() {
            case "package.json":
                if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                    result = Set(object.keys.map { $0.lowercased() })
                }
            case "pyproject.toml", "cargo.toml": result = Self.scanTOML(text).tables
            default: result = nil
            }
        }
        keyNames[actual] = result
        return result
    }

    // MARK: Matching

    static func glob(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern), n = Array(name)
        var pi = 0, ni = 0, star = -1, mark = 0
        while ni < n.count {
            if pi < p.count, p[pi] == n[ni] { pi += 1; ni += 1 }
            else if pi < p.count, p[pi] == "*" { star = pi; mark = ni; pi += 1 }
            else if star != -1 { pi = star + 1; mark += 1; ni = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    // MARK: Manifest readers

    private static func packageJSONDependencies(_ text: String) -> Set<String>? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return nil }
        var names = Set<String>()
        for section in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
            if let table = object[section] as? [String: Any] { names.formUnion(table.keys.map(normalize)) }
        }
        return names
    }

    private static func requirementName(_ requirement: String) -> String? {
        let trimmed = requirement.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isLetter || first.isNumber, !trimmed.contains("://") else { return nil }
        let stop = Set(" =<>!~;[(@,")
        let name = String(trimmed.prefix { !stop.contains($0) })
        return name.isEmpty ? nil : normalize(name)
    }

    private static func requirementsDependencies(_ text: String) -> Set<String> {
        var names = Set<String>()
        for rawLine in text.split(whereSeparator: \.isNewline).prefix(5_000) {
            let line = stripComment(String(rawLine))
            if let name = requirementName(line) { names.insert(name) }
        }
        return names
    }

    private static func goModDependencies(_ text: String) -> Set<String> {
        var names = Set<String>()
        var inBlock = false
        for rawLine in text.split(whereSeparator: \.isNewline).prefix(5_000) {
            var line = String(rawLine)
            if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !parts.isEmpty else { continue }
            if inBlock {
                if parts[0] == ")" { inBlock = false } else { names.insert(normalize(parts[0])) }
            } else if parts[0] == "require" {
                if parts.count >= 2, parts[1] == "(" { inBlock = true }
                else if parts.count >= 2 { names.insert(normalize(parts[1])) }
            }
        }
        return names
    }

    // MARK: Minimal bounded TOML reader

    struct TOMLScan {
        var tables = Set<String>()
        var entries: [(table: String, key: String, value: String)] = []
    }

    private static func pyprojectDependencies(_ scan: TOMLScan) -> Set<String> {
        var names = Set<String>()
        for (table, key, value) in scan.entries {
            let poetryTable = table == "tool.poetry.dependencies" || table == "tool.poetry.dev-dependencies"
                || (table.hasPrefix("tool.poetry.group.") && table.hasSuffix(".dependencies"))
            if poetryTable {
                if key.lowercased() != "python" { names.insert(normalize(key)) }
            } else if (table == "project" && key == "dependencies") || table == "project.optional-dependencies"
                        || table == "dependency-groups" || (table == "tool.uv" && key == "dev-dependencies") {
                for requirement in quotedStrings(in: value) { if let name = requirementName(requirement) { names.insert(name) } }
            }
        }
        return names
    }

    private static func cargoDependencies(_ scan: TOMLScan) -> Set<String> {
        let tables = ["dependencies", "dev-dependencies", "build-dependencies", "workspace.dependencies"]
        var names = Set<String>()
        for (table, key, _) in scan.entries
        where tables.contains(table) || (table.hasPrefix("target.") && table.hasSuffix(".dependencies")) {
            if let first = key.split(separator: ".").first { names.insert(normalize(String(first))) }
        }
        for table in scan.tables {
            for prefix in tables where table.hasPrefix(prefix + ".") {
                if let last = table.split(separator: ".").last { names.insert(normalize(String(last))) }
            }
        }
        return names
    }

    static func scanTOML(_ text: String) -> TOMLScan {
        var scan = TOMLScan()
        var table = ""
        var pendingKey: String?
        var pendingValue = ""
        var depth = 0
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).prefix(5_000) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if let key = pendingKey {
                pendingValue += " " + line
                depth += bracketDelta(line)
                if depth <= 0 { scan.entries.append((table, key, pendingValue)); pendingKey = nil }
                continue
            }
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                let name = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
                table = name.split(separator: ".", omittingEmptySubsequences: false)
                    .map { unquote($0.trimmingCharacters(in: .whitespaces)) }.joined(separator: ".").lowercased()
                scan.tables.insert(table)
                continue
            }
            guard let equals = indexOfEquals(line) else { continue }
            let key = unquote(line[..<equals].trimmingCharacters(in: .whitespaces))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let delta = bracketDelta(value)
            if delta > 0 { pendingKey = key; pendingValue = value; depth = delta }
            else { scan.entries.append((table, key, value)) }
        }
        return scan
    }

    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open, !(open == "\"" && previous == "\\") { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
            previous = character
        }
        return line
    }

    private static func bracketDelta(_ text: String) -> Int {
        var quote: Character?
        var delta = 0
        for character in text {
            if let open = quote { if character == open { quote = nil }; continue }
            switch character {
            case "\"", "'": quote = character
            case "[", "{": delta += 1
            case "]", "}": delta -= 1
            default: break
            }
        }
        return delta
    }

    private static func indexOfEquals(_ line: String) -> String.Index? {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote { if character == open { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character }
            else if character == "=" { return index }
        }
        return nil
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func quotedStrings(in value: String) -> [String] {
        var result: [String] = []
        var quote: Character?
        var current = ""
        for character in value {
            if let open = quote {
                if character == open { result.append(current); current = ""; quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            }
        }
        return result
    }
}

/// Test-only entry point for the import grammar; production code goes through `ProjectRecognizer`.
enum RecognitionWorkspaceTestHook {
    static func modules(_ text: String, _ ext: String) -> Set<String> {
        RecognitionWorkspace.importedModules(in: text, extension: ext)
    }
}
