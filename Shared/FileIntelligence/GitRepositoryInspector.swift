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
    var hasReadme: Bool { metadata.contains { $0.relativePath.lowercased().hasPrefix("readme") } }
    var hasLicense: Bool {
        metadata.contains {
            let path = $0.relativePath.lowercased()
            return path.hasPrefix("license") || path == "copying"
        }
    }
    var hasGitHubActions: Bool { metadata.contains { $0.relativePath == ".github/workflows" } }

    var title: InsightLocalizedText {
        switch state {
        case .metadataDetected: return text("Git metadata detected", "检测到 Git 元数据")
        case .githubMetadataOnly: return text("GitHub project metadata detected", "检测到 GitHub 项目元数据")
        case .repository:
            switch remote?.provider {
            case .github: return text("GitHub Repository", "GitHub 仓库")
            case .gitlab: return text("GitLab Repository", "GitLab 仓库")
            case .bitbucket: return text("Bitbucket Repository", "Bitbucket 仓库")
            default: return text("Git Repository", "Git 仓库")
            }
        }
    }

    var summary: InsightLocalizedText {
        var english: [String] = []
        var chinese: [String] = []
        if let identity = remote?.identity {
            english.append(identity); chinese.append(identity)
        } else if let host = remote?.host {
            english.append(host); chinese.append(host)
        }
        if case let .branch(branch)? = head {
            english.append("\(branch) branch"); chinese.append("\(branch) 分支")
        } else if case .detached? = head {
            english.append("HEAD detached"); chinese.append("HEAD 已分离")
        }
        if english.isEmpty {
            return state == .metadataDetected
                ? text("Local Git metadata could not be validated", "本地 Git 元数据无法验证")
                : text("Local project structure", "本地项目结构")
        }
        return text(english.joined(separator: " · "), chinese.joined(separator: " · "))
    }

    var evidence: [GitMetadataItem] {
        var result: [GitMetadataItem] = []
        if isRepository {
            result.append(GitMetadataItem(relativePath: ".git/HEAD", reason: text("Git HEAD reference", "Git HEAD 引用")))
            if remote != nil {
                result.append(GitMetadataItem(relativePath: ".git/config", reason: text("Git remote configuration", "Git 远程配置")))
            }
        } else if state == .metadataDetected {
            result.append(GitMetadataItem(relativePath: ".git", reason: text("Git metadata could not be validated", "Git 元数据无法验证")))
        }
        result.append(contentsOf: metadata)
        return result
    }

    private func text(_ english: String, _ chinese: String) -> InsightLocalizedText {
        InsightLocalizedText(english: english, simplifiedChinese: chinese)
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
        let remote = readRemote(at: gitDirectory.appendingPathComponent("config"))
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
           let scheme = components.scheme?.lowercased(), ["https", "http", "ssh"].contains(scheme),
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
        let descriptions: [String: (String, String)] = [
            ".github": ("GitHub project metadata", "GitHub 项目元数据"),
            ".github/workflows": ("GitHub Actions workflows", "GitHub Actions 工作流"),
            ".github/ISSUE_TEMPLATE": ("GitHub issue templates", "GitHub 问题模板"),
            ".github/PULL_REQUEST_TEMPLATE": ("GitHub pull request template", "GitHub 拉取请求模板"),
            ".github/PULL_REQUEST_TEMPLATE.md": ("GitHub pull request template", "GitHub 拉取请求模板"),
            ".github/dependabot.yml": ("Dependabot configuration", "Dependabot 配置"),
            ".github/CODEOWNERS": ("Code ownership rules", "代码所有权规则"),
            "CODEOWNERS": ("Code ownership rules", "代码所有权规则"),
            "README": ("Project documentation", "项目文档"),
            "README.md": ("Project documentation", "项目文档"),
            "README.rst": ("Project documentation", "项目文档"),
            "LICENSE": ("License file", "许可证文件"),
            "LICENSE.md": ("License file", "许可证文件"),
            "COPYING": ("License file", "许可证文件"),
            "CONTRIBUTING": ("Contribution guide", "贡献指南"),
            "CONTRIBUTING.md": ("Contribution guide", "贡献指南"),
            "SECURITY.md": ("Security policy", "安全策略"),
            "CODE_OF_CONDUCT.md": ("Code of conduct", "行为准则")
        ]
        return knowledge.metadataPaths.compactMap { declaration in
            guard let description = descriptions[declaration.path] else { return nil }
            let path = declaration.path
            let directory = declaration.kind == "directory"
            let (english, chinese) = description
            let url = folder.appendingPathComponent(path)
            let keys: Set<URLResourceKey> = declaration.kind == "any" ? [.isDirectoryKey, .isRegularFileKey] : (directory ? [.isDirectoryKey] : [.isRegularFileKey])
            guard let values = try? url.resourceValues(forKeys: keys),
                  declaration.kind == "any" ? (values.isDirectory == true || values.isRegularFile == true) : (directory ? values.isDirectory == true : values.isRegularFile == true) else { return nil }
            return GitMetadataItem(relativePath: path, reason: InsightLocalizedText(english: english, simplifiedChinese: chinese))
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
