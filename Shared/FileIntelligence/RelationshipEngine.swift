import Foundation

struct RelationshipMember: Sendable, Hashable {
    enum Role: String, Sendable, Hashable {
        case primary, geometry, index, attributes, projection, configuration
        case weights, tokenizer, source, bibliography, manifest, lockfile, project, supporting
    }
    let relativePath: String
    let role: Role
}

enum RelationshipType: String, Sendable, Hashable {
    case shapefile, transformer, latex, node, python, rust, go, xcode, docker
}

struct DetectedRelationship: Sendable, Hashable {
    let type: RelationshipType
    let members: [RelationshipMember]
    let confidence: Double
    let priority: Int
    var localizationKey: String { "relationship_\(type.rawValue)" }
}

/// Uses only the bounded FolderAnalysis snapshot. Rules operate within one
/// parent directory so unrelated files in neighboring folders cannot match.
struct RelationshipEngine: Sendable {
    static let maxDisplayedRelationships = 4

    func detect(in analysis: FolderAnalysis) -> [DetectedRelationship] {
        let directories = Dictionary(grouping: analysis.analyzedEntries) {
            ($0.relativePath as NSString).deletingLastPathComponent.lowercased()
        }
        var results: [DetectedRelationship] = []
        for path in directories.keys.sorted() {
            guard let entries = directories[path] else { continue }
            let context = Context(entries: entries)
            results += shapefiles(in: context)
            if let result = transformer(in: context) { results.append(result) }
            if let result = latex(in: context) { results.append(result) }
            if let result = node(in: context) { results.append(result) }
            if let result = python(in: context) { results.append(result) }
            if let result = rust(in: context) { results.append(result) }
            if let result = go(in: context) { results.append(result) }
            if let result = xcode(in: context) { results.append(result) }
            if let result = docker(in: context) { results.append(result) }
        }
        var seen = Set<String>()
        return results.filter { $0.confidence >= 0.85 }
            .sorted(by: Self.isHigherPriority)
            .filter { relationship in
                let paths = relationship.members.map(\.relativePath).sorted().joined(separator: "|")
                return seen.insert("\(relationship.type.rawValue)|\(paths)").inserted
            }
    }

    private struct Context {
        let entries: [AnalyzedEntry]
        let byName: [String: AnalyzedEntry]

        init(entries: [AnalyzedEntry]) {
            self.entries = entries.sorted { $0.relativePath < $1.relativePath }
            var names: [String: AnalyzedEntry] = [:]
            for entry in self.entries where names[entry.name.lowercased()] == nil {
                names[entry.name.lowercased()] = entry
            }
            byName = names
        }

        func file(_ name: String) -> AnalyzedEntry? {
            guard let entry = byName[name.lowercased()], !entry.isDirectory else { return nil }
            return entry
        }
        func directory(_ name: String) -> AnalyzedEntry? {
            guard let entry = byName[name.lowercased()], entry.isDirectory else { return nil }
            return entry
        }
        func firstFile(_ names: [String]) -> AnalyzedEntry? { names.compactMap(file).first }
        func members(_ roles: [String: RelationshipMember.Role]) -> [RelationshipMember] {
            entries.compactMap { entry in
                guard let role = roles[entry.name.lowercased()] else { return nil }
                return RelationshipMember(relativePath: entry.relativePath, role: role)
            }
        }
    }

    private func shapefiles(in context: Context) -> [DetectedRelationship] {
        let roles: [String: RelationshipMember.Role] = [
            "shp": .geometry, "shx": .index, "dbf": .attributes, "prj": .projection,
            "cpg": .supporting, "sbn": .supporting, "sbx": .supporting
        ]
        let grouped = Dictionary(grouping: context.entries.filter { !$0.isDirectory }) {
            $0.url.deletingPathExtension().lastPathComponent.lowercased()
        }
        return grouped.keys.sorted().compactMap { stem in
            guard let entries = grouped[stem] else { return nil }
            let extensions = Set(entries.map { $0.url.pathExtension.lowercased() })
            guard extensions.isSuperset(of: ["shp", "shx", "dbf"]) else { return nil }
            let members = entries.compactMap { entry -> RelationshipMember? in
                guard let role = roles[entry.url.pathExtension.lowercased()] else { return nil }
                return RelationshipMember(relativePath: entry.relativePath, role: role)
            }.sorted { $0.relativePath < $1.relativePath }
            return DetectedRelationship(type: .shapefile, members: members, confidence: 0.99, priority: 100)
        }
    }

    private func transformer(in context: Context) -> DetectedRelationship? {
        guard context.file("config.json") != nil,
              context.firstFile(["tokenizer.json", "tokenizer_config.json"]) != nil else { return nil }
        let weights = context.entries.filter { entry in
            !entry.isDirectory && (entry.url.pathExtension.lowercased() == "safetensors" ||
                ["pytorch_model.bin", "model.onnx"].contains(entry.name.lowercased()))
        }
        guard !weights.isEmpty else { return nil }
        var members = context.members([
            "config.json": .configuration, "tokenizer.json": .tokenizer,
            "tokenizer_config.json": .tokenizer, "special_tokens_map.json": .tokenizer
        ])
        members += weights.map { .init(relativePath: $0.relativePath, role: .weights) }
        return .init(type: .transformer, members: members.sorted { $0.relativePath < $1.relativePath }, confidence: 0.96, priority: 95)
    }

    private func latex(in context: Context) -> DetectedRelationship? {
        let sources = context.entries.filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "tex" }
        let bibliography = context.entries.filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "bib" }
        guard !sources.isEmpty, !bibliography.isEmpty else { return nil }
        var members = sources.map { RelationshipMember(relativePath: $0.relativePath, role: .source) }
        members += bibliography.map { .init(relativePath: $0.relativePath, role: .bibliography) }
        if let figures = context.directory("figures") { members.append(.init(relativePath: figures.relativePath, role: .supporting)) }
        return .init(type: .latex, members: members.sorted { $0.relativePath < $1.relativePath }, confidence: 0.93, priority: 82)
    }

    private func node(in context: Context) -> DetectedRelationship? {
        guard context.file("package.json") != nil,
              context.firstFile(["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "tsconfig.json"]) != nil else { return nil }
        return .init(type: .node, members: context.members([
            "package.json": .manifest, "package-lock.json": .lockfile, "pnpm-lock.yaml": .lockfile,
            "yarn.lock": .lockfile, "bun.lock": .lockfile, "tsconfig.json": .configuration
        ]), confidence: 0.95, priority: 78)
    }

    private func python(in context: Context) -> DetectedRelationship? {
        guard context.firstFile(["pyproject.toml", "requirements.txt", "Pipfile", "setup.py", "setup.cfg"]) != nil,
              context.firstFile(["uv.lock", "poetry.lock", "Pipfile.lock", "requirements.txt", "setup.py", "setup.cfg"]) != nil || context.directory("src") != nil else { return nil }
        var members = context.members([
            "pyproject.toml": .manifest, "requirements.txt": .manifest, "pipfile": .manifest,
            "setup.py": .manifest, "setup.cfg": .manifest, "uv.lock": .lockfile,
            "poetry.lock": .lockfile, "pipfile.lock": .lockfile
        ])
        if let source = context.directory("src") { members.append(.init(relativePath: source.relativePath, role: .source)) }
        guard members.count >= 2 else { return nil }
        return .init(type: .python, members: members.sorted { $0.relativePath < $1.relativePath }, confidence: 0.93, priority: 77)
    }

    private func rust(in context: Context) -> DetectedRelationship? {
        guard context.file("Cargo.toml") != nil,
              context.file("Cargo.lock") != nil || context.directory("src") != nil else { return nil }
        var members = context.members(["cargo.toml": .manifest, "cargo.lock": .lockfile])
        if let source = context.directory("src") { members.append(.init(relativePath: source.relativePath, role: .source)) }
        return .init(type: .rust, members: members.sorted { $0.relativePath < $1.relativePath }, confidence: 0.96, priority: 76)
    }

    private func go(in context: Context) -> DetectedRelationship? {
        guard context.file("go.mod") != nil, context.file("go.sum") != nil else { return nil }
        return .init(type: .go, members: context.members(["go.mod": .manifest, "go.sum": .lockfile]), confidence: 0.97, priority: 76)
    }

    private func xcode(in context: Context) -> DetectedRelationship? {
        let projects = context.entries.filter { $0.isDirectory && $0.name.lowercased().hasSuffix(".xcodeproj") }
        guard !projects.isEmpty else { return nil }
        var members = projects.map { RelationshipMember(relativePath: $0.relativePath, role: .project) }
        members += context.members(["package.swift": .manifest, "package.resolved": .lockfile])
        return .init(type: .xcode, members: members.sorted { $0.relativePath < $1.relativePath }, confidence: 0.98, priority: 84)
    }

    private func docker(in context: Context) -> DetectedRelationship? {
        guard context.file("Dockerfile") != nil,
              context.firstFile(["compose.yml", "compose.yaml", "docker-compose.yml", "docker-compose.yaml"]) != nil else { return nil }
        return .init(type: .docker, members: context.members([
            "dockerfile": .primary, "compose.yml": .configuration, "compose.yaml": .configuration,
            "docker-compose.yml": .configuration, "docker-compose.yaml": .configuration,
            ".dockerignore": .supporting
        ]), confidence: 0.96, priority: 80)
    }

    private static func isHigherPriority(_ lhs: DetectedRelationship, _ rhs: DetectedRelationship) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.type.rawValue != rhs.type.rawValue { return lhs.type.rawValue < rhs.type.rawValue }
        return (lhs.members.first?.relativePath ?? "") < (rhs.members.first?.relativePath ?? "")
    }
}
