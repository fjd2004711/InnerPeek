import Foundation

// Declarative risk and stack insights. Rules live in Knowledge/project-insights.json;
// this file only evaluates them against names the bounded analysis already produced,
// plus a handful of tightly capped reads (see RiskScanner.maximumContentReads).
// File contents are matched against a rule's pattern and then discarded: they are
// never stored, shown, or logged. Findings carry paths only.

/// `*` matches any run of characters; callers lowercase both sides.
enum NameGlob {
    static func matches(_ pattern: String, _ name: String) -> Bool {
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
}

// MARK: Rules

struct RiskRule: Decodable, Sendable {
    let id: String
    let entryKind: String
    let names: [String]
    let paths: [String]
    let excludeNames: [String]
    let excludePathComponents: [String]
    let contentPattern: String?
    let trustedWithoutContent: [String]
    let scope: String
    let respectsGitignore: Bool
    let severity: InsightSeverity
    let priority: Int
    let title: InsightLocalizedText
    let detail: InsightLocalizedText
    let archiveDetail: InsightLocalizedText?

    enum CodingKeys: String, CodingKey {
        case id, entryKind, names, paths, excludeNames, excludePathComponents, contentPattern
        case trustedWithoutContent, scope, respectsGitignore, severity, priority, title, detail, archiveDetail
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        entryKind = try values.decode(String.self, forKey: .entryKind)
        names = try values.decodeIfPresent([String].self, forKey: .names) ?? []
        paths = try values.decodeIfPresent([String].self, forKey: .paths) ?? []
        excludeNames = try values.decodeIfPresent([String].self, forKey: .excludeNames) ?? []
        excludePathComponents = try values.decodeIfPresent([String].self, forKey: .excludePathComponents) ?? []
        contentPattern = try values.decodeIfPresent(String.self, forKey: .contentPattern)
        trustedWithoutContent = try values.decodeIfPresent([String].self, forKey: .trustedWithoutContent) ?? []
        scope = try values.decode(String.self, forKey: .scope)
        respectsGitignore = try values.decode(Bool.self, forKey: .respectsGitignore)
        severity = try values.decode(InsightSeverity.self, forKey: .severity)
        priority = try values.decode(Int.self, forKey: .priority)
        title = try values.decode(InsightLocalizedText.self, forKey: .title)
        detail = try values.decode(InsightLocalizedText.self, forKey: .detail)
        archiveDetail = try values.decodeIfPresent(InsightLocalizedText.self, forKey: .archiveDetail)
    }
}

struct StackRule: Decodable, Sendable {
    struct FactRequirement: Decodable, Sendable {
        let id: String
        let minimumConfidence: String
    }

    struct Multiple: Decodable, Sendable {
        let patterns: [String]
        let atLeast: Int
    }

    let id: String
    let requiresFact: FactRequirement?
    let requiresRepository: Bool
    let allPresent: [String]
    let anyPresent: [String]
    let nonePresent: [String]
    let multiplePresent: Multiple?
    let severity: InsightSeverity
    let priority: Int
    let title: InsightLocalizedText
    let detail: InsightLocalizedText?

    enum CodingKeys: String, CodingKey {
        case id, requiresFact, requiresRepository, allPresent, anyPresent, nonePresent, multiplePresent, severity, priority, title, detail
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        requiresFact = try values.decodeIfPresent(FactRequirement.self, forKey: .requiresFact)
        requiresRepository = try values.decodeIfPresent(Bool.self, forKey: .requiresRepository) ?? false
        allPresent = try values.decodeIfPresent([String].self, forKey: .allPresent) ?? []
        anyPresent = try values.decodeIfPresent([String].self, forKey: .anyPresent) ?? []
        nonePresent = try values.decodeIfPresent([String].self, forKey: .nonePresent) ?? []
        multiplePresent = try values.decodeIfPresent(Multiple.self, forKey: .multiplePresent)
        severity = try values.decode(InsightSeverity.self, forKey: .severity)
        priority = try values.decode(Int.self, forKey: .priority)
        title = try values.decode(InsightLocalizedText.self, forKey: .title)
        detail = try values.decodeIfPresent(InsightLocalizedText.self, forKey: .detail)
    }
}

struct ProjectInsightKnowledge: Decodable, Sendable {
    let risks: [RiskRule]
    let stack: [StackRule]

    static let empty = ProjectInsightKnowledge(risks: [], stack: [])
    static let shared = ProjectInsightKnowledge.load()

    init(risks: [RiskRule], stack: [StackRule]) {
        self.risks = risks
        self.stack = stack
    }

    init(data: Data) {
        self = (try? JSONDecoder().decode(ProjectInsightKnowledge.self, from: data)) ?? .empty
    }

    /// Bundled resource first, then the source tree (command-line tools and tests).
    static func load() -> ProjectInsightKnowledge {
        let bundle = Bundle(for: FileTypeRegistry.self)
        let bundled = bundle.url(forResource: "project-insights", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Knowledge/project-insights.json")
        guard let data = bundled ?? (try? Data(contentsOf: sourceURL)) else { return .empty }
        return ProjectInsightKnowledge(data: data)
    }
}

// MARK: Root context

/// Names the stack rules judge: root-level names (hidden ones included) when the listing
/// is complete, and lowercased relative paths for slash patterns.
struct ProjectRootContext: Sendable, Hashable {
    let names: Set<String>
    let paths: Set<String>

    /// For an archive: a single wrapping folder (`project/…`) is looked through, so the
    /// archive is judged like the folder it was made from. Returns nil for an empty archive.
    static func archive(entryPaths: [String]) -> ProjectRootContext? {
        let cleaned = entryPaths
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("__MACOSX/") && $0 != ".DS_Store" }
        guard !cleaned.isEmpty else { return nil }
        let split = cleaned.map { $0.split(separator: "/").map(String.init) }
        let firsts = Set(split.compactMap(\.first))
        let wrapped = firsts.count == 1 && split.allSatisfy { $0.count > 1 || $0 == split.first! }
            && split.contains { $0.count > 1 }
        let stripped = split.map { wrapped ? Array($0.dropFirst()) : $0 }.filter { !$0.isEmpty }
        return ProjectRootContext(
            names: Set(stripped.compactMap { $0.first?.lowercased() }),
            paths: Set(stripped.map { $0.joined(separator: "/").lowercased() })
        )
    }
}

// MARK: Risk findings

struct RiskFinding: Sendable, Hashable {
    let ruleID: String
    /// Relative paths, sorted, never file contents.
    let paths: [String]
    /// True when the finding comes from an archive listing rather than the file system.
    let archive: Bool
}

struct RiskCandidate: Sendable, Hashable {
    let relativePath: String
    let name: String
    let isDirectory: Bool
}

struct RiskEnvironment {
    var isRepository: Bool
    var isArchive: Bool
    var pathExists: (String) -> Bool
    /// First bytes of a regular, non-symlink file as text; `nil` when unreadable.
    var readPrefix: (String) -> String?
    /// Whether `.gitignore` rules cover the path.
    var isIgnored: (String, Bool) -> Bool

    static func archive(paths: Set<String>) -> RiskEnvironment {
        RiskEnvironment(isRepository: false, isArchive: true,
                        pathExists: { path in
                            let lowered = path.lowercased()
                            return paths.contains { $0 == lowered || $0.hasSuffix("/" + lowered) }
                        },
                        readPrefix: { _ in nil }, isIgnored: { _, _ in false })
    }
}

struct RiskScanner: Sendable {
    static let maximumContentReads = 12
    static let maximumPathsPerFinding = 40

    let rules: [RiskRule]

    func scan(candidates: [RiskCandidate], environment: RiskEnvironment) -> [RiskFinding] {
        var reads = 0
        var findings: [RiskFinding] = []

        for rule in rules {
            if rule.scope == "repository", !(environment.isRepository || environment.isArchive) { continue }
            let wantsDirectory = rule.entryKind == "directory"
            var matched: [(path: String, isDirectory: Bool)] = []

            for candidate in candidates where candidate.isDirectory == wantsDirectory {
                let name = candidate.name.lowercased()
                guard rule.names.contains(where: { NameGlob.matches($0.lowercased(), name) }) else { continue }
                if rule.excludeNames.contains(where: { NameGlob.matches($0.lowercased(), name) }) { continue }
                let parents = candidate.relativePath.lowercased().split(separator: "/").dropLast().map(String.init)
                if parents.contains(where: { rule.excludePathComponents.contains($0) }) { continue }
                matched.append((candidate.relativePath, candidate.isDirectory))
            }
            for path in rule.paths where environment.pathExists(path) {
                matched.append((path, false))
            }

            var seen = Set<String>()
            matched = matched.filter { seen.insert($0.path).inserted }.sorted { $0.path < $1.path }
            if matched.count > Self.maximumPathsPerFinding { matched = Array(matched.prefix(Self.maximumPathsPerFinding)) }

            if let pattern = rule.contentPattern, let regex = try? NSRegularExpression(pattern: pattern) {
                matched = matched.filter { item in
                    if environment.isArchive {
                        // An archive listing has no readable data; only unmistakable names count.
                        return rule.trustedWithoutContent.contains(item.path.split(separator: "/").last.map { $0.lowercased() } ?? "")
                    }
                    guard reads < Self.maximumContentReads, let text = environment.readPrefix(item.path) else { return false }
                    reads += 1
                    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                }
            }

            if rule.respectsGitignore, environment.isRepository {
                matched = matched.filter { !environment.isIgnored($0.path, $0.isDirectory) }
            }

            guard !matched.isEmpty else { continue }
            findings.append(RiskFinding(ruleID: rule.id, paths: matched.map(\.path), archive: environment.isArchive))
        }
        return findings
    }
}

// MARK: .gitignore

/// A deliberately small .gitignore evaluator: later rules win, `!` negates, a trailing
/// slash restricts a rule to directories, a rule with a slash is anchored to the folder
/// of its .gitignore, `**` spans folders. An ignored parent folder ignores everything
/// inside it. Global excludes are unknown to this check, so wording stays factual:
/// "is not covered by .gitignore".
struct GitIgnoreMatcher: Sendable {
    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let negated: Bool
        let directoryOnly: Bool
        let baseDirectory: String
    }

    private let rules: [Rule]

    /// `sources` are ordered from least to most specific (info/exclude, root, then deeper folders).
    init(sources: [(baseDirectory: String, text: String)]) {
        var parsed: [Rule] = []
        for source in sources {
            for line in source.text.split(whereSeparator: \.isNewline) {
                if let rule = Self.parse(String(line), baseDirectory: source.baseDirectory) { parsed.append(rule) }
            }
        }
        rules = parsed
    }

    func isIgnored(_ path: String, isDirectory: Bool) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        for end in 1..<components.count where decision(components[0..<end].joined(separator: "/"), isDirectory: true) {
            return true
        }
        return decision(path, isDirectory: isDirectory)
    }

    private func decision(_ path: String, isDirectory: Bool) -> Bool {
        var ignored = false
        for rule in rules {
            if rule.directoryOnly && !isDirectory { continue }
            var relative = path
            if !rule.baseDirectory.isEmpty {
                guard path.hasPrefix(rule.baseDirectory + "/") else { continue }
                relative = String(path.dropFirst(rule.baseDirectory.count + 1))
            }
            if rule.regex.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil {
                ignored = !rule.negated
            }
        }
        return ignored
    }

    private static func parse(_ rawLine: String, baseDirectory: String) -> Rule? {
        var line = rawLine
        while line.last == " " || line.last == "\t" || line.last == "\r" { line.removeLast() }
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        var negated = false
        if line.hasPrefix("!") { negated = true; line.removeFirst() }
        else if line.hasPrefix("\\!") || line.hasPrefix("\\#") { line.removeFirst() }
        var directoryOnly = false
        if line.hasSuffix("/") { directoryOnly = true; line.removeLast() }
        guard !line.isEmpty else { return nil }
        var anchored = line.contains("/")
        if line.hasPrefix("/") { line.removeFirst(); anchored = true }

        var body = ""
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    let atStart = index == 0 || characters[index - 1] == "/"
                    let followedBySlash = index + 2 < characters.count && characters[index + 2] == "/"
                    let atEnd = index + 2 >= characters.count
                    if atStart && followedBySlash { body += "(?:.*/)?"; index += 3; continue }
                    if atStart && atEnd { body += ".*"; index += 2; continue }
                    body += "[^/]*"; index += 2; continue
                }
                body += "[^/]*"
            } else if character == "?" {
                body += "[^/]"
            } else if character == "[", let close = characters[(index + 1)...].firstIndex(of: "]"), close > index + 1 {
                var set = String(characters[(index + 1)..<close])
                if set.hasPrefix("!") { set = "^" + set.dropFirst() }
                body += "[" + set + "]"
                index = close
            } else if character == "\\", index + 1 < characters.count {
                index += 1
                body += NSRegularExpression.escapedPattern(for: String(characters[index]))
            } else {
                body += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        let pattern = "^" + (anchored ? "" : "(?:.*/)?") + body + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Rule(regex: regex, negated: negated, directoryOnly: directoryOnly, baseDirectory: baseDirectory)
    }
}

// MARK: File-system environment

/// Bounded, read-only access for the risk scanner. Everything is capped and never follows symlinks.
final class FilesystemRiskSource: @unchecked Sendable {
    static let maximumPrefixBytes = 4_096
    static let maximumIgnoreFileBytes = 64 * 1_024
    static let maximumIgnoreFiles = 24
    static let maximumRootEntries = 5_000

    private let root: URL
    private var ignoreTexts: [String: String?] = [:]
    private var ignoreReads = 0

    init(root: URL) { self.root = root }

    /// Root-level names including hidden ones, which the visible traversal skips.
    /// `complete` is false when the listing hit its cap or could not be read.
    func rootListing() -> (candidates: [RiskCandidate], names: Set<String>, complete: Bool) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return ([], [], false) }
        let capped = names.prefix(Self.maximumRootEntries)
        var candidates: [RiskCandidate] = []
        for name in capped where name.hasPrefix(".") {
            let values = try? root.appendingPathComponent(name).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            candidates.append(RiskCandidate(relativePath: name, name: name, isDirectory: values?.isDirectory ?? false))
        }
        return (candidates, Set(capped.map { $0.lowercased() }), names.count <= Self.maximumRootEntries)
    }

    func environment(isRepository: Bool) -> RiskEnvironment {
        RiskEnvironment(
            isRepository: isRepository, isArchive: false,
            pathExists: { [root] path in
                guard !path.contains(".."), let values = try? root.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            },
            readPrefix: { [weak self] in self?.readPrefix($0) },
            isIgnored: { [weak self] path, isDirectory in self?.isIgnored(path, isDirectory: isDirectory) ?? false }
        )
    }

    private func readPrefix(_ relativePath: String) -> String? {
        guard !relativePath.contains("..") else { return nil }
        let url = root.appendingPathComponent(relativePath)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumPrefixBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func ignoreText(at relativePath: String) -> String? {
        if let cached = ignoreTexts[relativePath] { return cached }
        var text: String?
        if ignoreReads < Self.maximumIgnoreFiles {
            ignoreReads += 1
            let url = root.appendingPathComponent(relativePath)
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
               values.isRegularFile == true, values.isSymbolicLink != true,
               (values.fileSize ?? 0) <= Self.maximumIgnoreFileBytes,
               let data = try? Data(contentsOf: url) {
                text = String(decoding: data, as: UTF8.self)
            }
        }
        ignoreTexts[relativePath] = .some(text)
        return text
    }

    private func isIgnored(_ path: String, isDirectory: Bool) -> Bool {
        var sources: [(baseDirectory: String, text: String)] = []
        if let text = ignoreText(at: ".git/info/exclude") { sources.append(("", text)) }
        var directory = ""
        let folders = path.split(separator: "/").dropLast().map(String.init)
        for folder in [""] + folders {
            directory = directory.isEmpty ? folder : directory + "/" + folder
            let ignoreFile = (directory.isEmpty ? "" : directory + "/") + ".gitignore"
            if let text = ignoreText(at: ignoreFile) { sources.append((directory, text)) }
        }
        return GitIgnoreMatcher(sources: sources).isIgnored(path, isDirectory: isDirectory)
    }
}

// MARK: Stack rules

struct StackEvaluator: Sendable {
    let rules: [StackRule]

    /// `rootNames` are lowercased root-level names (complete listing); `nestedPaths` are
    /// lowercased relative paths from the bounded traversal, used only for slash patterns.
    func evaluate(rootNames: Set<String>, nestedPaths: Set<String>, facts: [DetectedFact], isRepository: Bool = false) -> [(rule: StackRule, evidence: [String])] {
        rules.compactMap { rule in
            if rule.requiresRepository, !isRepository { return nil }
            if let requirement = rule.requiresFact {
                guard let fact = facts.first(where: { $0.id == requirement.id }),
                      Self.satisfies(fact.confidence, minimum: requirement.minimumConfidence) else { return nil }
            }
            func matches(_ pattern: String) -> [String] {
                let lowered = pattern.lowercased()
                if lowered.contains("/") { return nestedPaths.contains(lowered) ? [lowered] : [] }
                if lowered.contains("*") { return rootNames.filter { NameGlob.matches(lowered, $0) }.sorted() }
                return rootNames.contains(lowered) ? [lowered] : []
            }

            var evidence: [String] = []
            if !rule.allPresent.isEmpty {
                let found = rule.allPresent.map(matches)
                guard found.allSatisfy({ !$0.isEmpty }) else { return nil }
                evidence += found.flatMap { $0 }
            }
            if !rule.anyPresent.isEmpty {
                let found = rule.anyPresent.flatMap(matches)
                guard !found.isEmpty else { return nil }
                evidence += found
            }
            if let multiple = rule.multiplePresent {
                let found = multiple.patterns.flatMap(matches)
                guard found.count >= multiple.atLeast else { return nil }
                evidence += found
            }
            if !rule.nonePresent.isEmpty {
                guard rule.nonePresent.allSatisfy({ matches($0).isEmpty }) else { return nil }
            }
            // A rule with no positive condition besides a fact is anchored by that fact alone.
            guard rule.requiresFact != nil || !evidence.isEmpty else { return nil }
            return (rule, evidence)
        }
    }

    private static func satisfies(_ confidence: ProjectIdentityConfidence, minimum: String) -> Bool {
        func rank(_ value: String) -> Int { value == "high" ? 2 : (value == "medium" ? 1 : 0) }
        return rank(confidence.rawValue) >= rank(minimum)
    }
}
