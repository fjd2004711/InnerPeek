import Foundation

/// Bounded, local-only repository information. Remote URLs are never retained:
/// the inspector keeps only a sanitized host and path identity.
enum GitRemoteProvider: String, Codable, Sendable, Hashable {
    case github
    case gitlab
    case bitbucket
    case other
}

enum GitRepositoryState: String, Sendable, Hashable {
    case repository
    case metadataDetected
    case githubMetadataOnly
}

enum GitHead: Sendable, Hashable {
    case branch(String)
    case detached
}

struct GitRemote: Sendable, Hashable {
    let provider: GitRemoteProvider
    let host: String
    let owner: String?
    let repository: String?

    var identity: String? {
        guard let owner, let repository else { return nil }
        return "\(owner)/\(repository)"
    }
}

struct GitMetadataItem: Sendable, Hashable {
    let relativePath: String
    let reason: InsightLocalizedText
}

struct GitRepositoryContext: Sendable, Hashable {
    let state: GitRepositoryState
    let head: GitHead?
    let remote: GitRemote?
    let metadata: [GitMetadataItem]

    var isRepository: Bool { state == .repository }
    var title: InsightLocalizedText {
        switch state {
        case .metadataDetected: return text("Git metadata detected")
        case .githubMetadataOnly: return text("GitHub project metadata detected")
        case .repository:
            switch remote?.provider {
            case .github: return text("GitHub Repository")
            case .gitlab: return text("GitLab Repository")
            case .bitbucket: return text("Bitbucket Repository")
            default: return text("Git Repository")
            }
        }
    }

    var summary: InsightLocalizedText {
        var parts: [InsightLocalizedText] = []
        if let identity = remote?.identity {
            parts.append(InsightLocalizedText(english: identity))
        } else if let host = remote?.host {
            parts.append(InsightLocalizedText(english: host))
        }
        if case let .branch(branch)? = head {
            parts.append(text("%@ branch").formatted([branch]))
        } else if case .detached? = head {
            parts.append(text("HEAD detached"))
        }
        if parts.isEmpty {
            return state == .metadataDetected
                ? text("Local Git metadata could not be validated")
                : text("Local project structure")
        }
        return InsightLocalizedText.joined(parts)
    }

    var evidence: [GitMetadataItem] {
        var result: [GitMetadataItem] = []
        if isRepository {
            result.append(GitMetadataItem(relativePath: ".git/HEAD", reason: text("Git HEAD reference")))
            if remote != nil {
                result.append(GitMetadataItem(relativePath: ".git/config", reason: text("Git remote configuration")))
            }
        } else if state == .metadataDetected {
            result.append(GitMetadataItem(relativePath: ".git", reason: text("Git metadata could not be validated")))
        }
        result.append(contentsOf: metadata)
        return result
    }

    private func text(_ english: String) -> InsightLocalizedText {
        MessageCatalog.shared.text(english)
    }
}

private struct GitRecognitionKnowledge: Decodable, Sendable {
    struct Host: Decodable, Sendable {
        let host: String
        let provider: GitRemoteProvider
    }
    struct MetadataPath: Decodable, Sendable {
        let path: String
        let kind: String
    }
    let hosts: [Host]
    let metadataPaths: [MetadataPath]

    static let fallback = GitRecognitionKnowledge(
        hosts: [Host(host: "github.com", provider: .github), Host(host: "gitlab.com", provider: .gitlab), Host(host: "bitbucket.org", provider: .bitbucket)],
        metadataPaths: []
    )
}

/// Inspects only the repository root and explicit Git metadata paths. It never
/// invokes Git, follows history, touches objects, or contacts a remote host.
struct GitRepositoryInspector: Sendable {
    private static let maximumMetadataBytes = 64 * 1_024
    private static let remoteSchemes: Set<String> = ["https", "http", "ssh", "git", "git+ssh", "ssh+git"]
    private let knowledge: GitRecognitionKnowledge

    init(data: Data? = nil) {
        let bundled = Bundle(for: FileTypeRegistry.self).url(forResource: "git-recognition", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Knowledge/git-recognition.json")
        knowledge = (data ?? bundled ?? (try? Data(contentsOf: sourceURL))).flatMap {
            try? JSONDecoder().decode(GitRecognitionKnowledge.self, from: $0)
        } ?? .fallback
    }

    func inspect(folderURL: URL) -> GitRepositoryContext? {
        let metadata = projectMetadata(in: folderURL)
        let dotGit = folderURL.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: dotGit.path) else {
            return metadata.contains(where: { $0.relativePath.hasPrefix(".github") })
                ? GitRepositoryContext(state: .githubMetadataOnly, head: nil, remote: nil, metadata: metadata)
                : nil
        }

        guard let gitDirectory = resolveGitDirectory(at: dotGit),
              let head = readHead(at: gitDirectory.appendingPathComponent("HEAD")) else {
            return GitRepositoryContext(state: .metadataDetected, head: nil, remote: nil, metadata: metadata)
        }
        // A linked worktree keeps HEAD in its own directory but shares the
        // repository configuration (and therefore the remotes) with the main one.
        let configDirectory = resolveCommonDirectory(of: gitDirectory) ?? gitDirectory
        let remote = readRemote(at: configDirectory.appendingPathComponent("config"))
        return GitRepositoryContext(state: .repository, head: head, remote: remote, metadata: metadata)
    }

    private func resolveGitDirectory(at dotGit: URL) -> URL? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        guard let values = try? dotGit.resourceValues(forKeys: keys) else { return nil }
        if values.isDirectory == true { return dotGit }
        guard values.isRegularFile == true,
              let pointer = readText(at: dotGit),
              let path = gitDirectoryPointer(from: pointer) else { return nil }
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            candidate = dotGit.deletingLastPathComponent().appendingPathComponent(path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.standardizedFileURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return candidate.standardizedFileURL
    }

    private func resolveCommonDirectory(of gitDirectory: URL) -> URL? {
        guard let pointer = readText(at: gitDirectory.appendingPathComponent("commondir")) else { return nil }
        let lines = pointer.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count == 1, let path = lines.first, !path.isEmpty, !path.contains("\0") else { return nil }
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : gitDirectory.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.standardizedFileURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return candidate.standardizedFileURL
    }

    private func gitDirectoryPointer(from value: String) -> String? {
        let lines = value.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count == 1 else { return nil }
        let prefix = "gitdir:"
        guard lines[0].lowercased().hasPrefix(prefix) else { return nil }
        let path = String(lines[0].dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        return path
    }

    private func readHead(at url: URL) -> GitHead? {
        guard let text = readText(at: url) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("ref: ") {
            let reference = String(value.dropFirst(5))
            let prefix = "refs/heads/"
            guard reference.hasPrefix(prefix) else { return nil }
            let branch = String(reference.dropFirst(prefix.count))
            guard isSafeReferenceComponent(branch) else { return nil }
            return .branch(branch)
        }
        guard isHexObjectID(value) else { return nil }
        return .detached
    }

    private func readRemote(at configURL: URL) -> GitRemote? {
        guard let config = readText(at: configURL) else { return nil }
        var remotes: [(name: String, url: String)] = []
        var currentRemote: String?
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                currentRemote = remoteName(fromSection: String(line))
                continue
            }
            guard let currentRemote,
                  let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "url" else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard value.count <= Self.maximumMetadataBytes else { continue }
            remotes.append((currentRemote, String(value)))
        }
        let chosen = remotes.first(where: { $0.name == "origin" }) ?? remotes.first
        return chosen.flatMap { parseRemote($0.url) }
    }

    private func remoteName(fromSection section: String) -> String? {
        guard section.hasPrefix("[remote \""), section.hasSuffix("\"]") else { return nil }
        let name = String(section.dropFirst(9).dropLast(2))
        return !name.isEmpty && name.allSatisfy { !$0.isWhitespace && !isControl($0) } ? name : nil
    }

    private func parseRemote(_ value: String) -> GitRemote? {
        let host: String
        let path: String
        if let components = URLComponents(string: value),
           let scheme = components.scheme?.lowercased(), Self.remoteSchemes.contains(scheme),
           let parsedHost = components.host {
            host = parsedHost
            path = components.path
        } else if let colon = value.lastIndex(of: ":"),
                  let at = value[..<colon].lastIndex(of: "@") {
            host = String(value[value.index(after: at)..<colon])
            path = String(value[value.index(after: colon)...])
        } else {
            return nil
        }
        let normalizedHost = host.lowercased()
        guard isSafeHost(normalizedHost) else { return nil }
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count >= 2, segments.allSatisfy(isSafePathSegment) else { return nil }
        let repository = segments.last!.hasSuffix(".git") ? String(segments.last!.dropLast(4)) : segments.last!
        guard isSafePathSegment(repository) else { return nil }
        let owner = segments.dropLast().joined(separator: "/")
        let provider = knowledge.hosts.first { $0.host.caseInsensitiveCompare(normalizedHost) == .orderedSame }?.provider ?? .other
        return GitRemote(provider: provider, host: normalizedHost, owner: owner, repository: repository)
    }

    private func projectMetadata(in folder: URL) -> [GitMetadataItem] {
        let descriptions: [String: String] = [
            ".github": "GitHub project metadata",
            ".github/workflows": "GitHub Actions workflows",
            ".github/ISSUE_TEMPLATE": "GitHub issue templates",
            ".github/PULL_REQUEST_TEMPLATE": "GitHub pull request template",
            ".github/PULL_REQUEST_TEMPLATE.md": "GitHub pull request template",
            ".github/dependabot.yml": "Dependabot configuration",
            ".github/CODEOWNERS": "Code ownership rules",
            "CODEOWNERS": "Code ownership rules",
            "README": "Project documentation",
            "README.md": "Project documentation",
            "README.rst": "Project documentation",
            "LICENSE": "License file",
            "LICENSE.md": "License file",
            "COPYING": "License file",
            "CONTRIBUTING": "Contribution guide",
            "CONTRIBUTING.md": "Contribution guide",
            "SECURITY.md": "Security policy",
            "CODE_OF_CONDUCT.md": "Code of conduct"
        ]
        return knowledge.metadataPaths.compactMap { declaration in
            guard let description = descriptions[declaration.path] else { return nil }
            let path = declaration.path
            let directory = declaration.kind == "directory"
            let url = folder.appendingPathComponent(path)
            let keys: Set<URLResourceKey> = declaration.kind == "any" ? [.isDirectoryKey, .isRegularFileKey] : (directory ? [.isDirectoryKey] : [.isRegularFileKey])
            guard let values = try? url.resourceValues(forKeys: keys),
                  declaration.kind == "any" ? (values.isDirectory == true || values.isRegularFile == true) : (directory ? values.isDirectory == true : values.isRegularFile == true) else { return nil }
            return GitMetadataItem(relativePath: path, reason: MessageCatalog.shared.text(description))
        }
    }

    private func readText(at url: URL) -> String? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              (values.fileSize ?? 0) <= Self.maximumMetadataBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func isHexObjectID(_ value: String) -> Bool {
        guard value.count == 40 || value.count == 64 else { return false }
        return value.allSatisfy { $0.isHexDigit }
    }

    private func isSafeReferenceComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("..") && value.allSatisfy { !$0.isWhitespace && !isControl($0) && $0 != "~" && $0 != "^" && $0 != ":" && $0 != "?" && $0 != "*" && $0 != "[" && $0 != "\\" }
    }

    private func isSafeHost(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private func isSafePathSegment(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.allSatisfy { $0.isLetter || $0.isNumber || ".-_~".contains($0) }
    }

    private func isControl(_ value: Character) -> Bool {
        value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }
}
