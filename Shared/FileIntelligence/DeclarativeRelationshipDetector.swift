import Foundation

private struct DeclarativeRelationshipRule: Decodable, Sendable {
    struct RequiredFile: Decodable, Sendable {
        let filename: String
        let role: String?
    }

    let id: String
    let relationshipType: String
    let required: [RequiredFile]
    let requiredRoles: [String]
    let requiredAnyFilenames: [String]
    let optionalRoles: [String]
    let optionalFilenames: [String]
    let optionalDirectories: [String]
    let minimumOptionalMatches: Int
    let confidence: Double
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id, relationshipType, required, requiredRoles, requiredAnyFilenames
        case optionalRoles, optionalFilenames, optionalDirectories
        case minimumOptionalMatches, confidence, priority
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        relationshipType = try values.decode(String.self, forKey: .relationshipType)
        required = try values.decodeIfPresent([RequiredFile].self, forKey: .required) ?? []
        requiredRoles = try values.decodeIfPresent([String].self, forKey: .requiredRoles) ?? []
        requiredAnyFilenames = try values.decodeIfPresent([String].self, forKey: .requiredAnyFilenames) ?? []
        optionalRoles = try values.decodeIfPresent([String].self, forKey: .optionalRoles) ?? []
        optionalFilenames = try values.decodeIfPresent([String].self, forKey: .optionalFilenames) ?? []
        optionalDirectories = try values.decodeIfPresent([String].self, forKey: .optionalDirectories) ?? []
        minimumOptionalMatches = try values.decodeIfPresent(Int.self, forKey: .minimumOptionalMatches) ?? 0
        confidence = try values.decode(Double.self, forKey: .confidence)
        priority = try values.decode(Int.self, forKey: .priority)
    }
}

/// Evaluates filename/role rules from the community knowledge base.
struct DeclarativeRelationshipDetector: Sendable {
    private let rules: [DeclarativeRelationshipRule]

    init(data: Data) {
        rules = (try? JSONDecoder().decode([DeclarativeRelationshipRule].self, from: data)) ?? []
    }

    init() {
        let bundle = Bundle(for: FileTypeRegistry.self)
        let bundled = bundle.url(forResource: "relationships", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Knowledge/relationships.json")
        let source = try? Data(contentsOf: sourceURL)
        self.init(data: bundled ?? source ?? Data())
    }

    func detect(in entries: [AnalyzedEntry]) -> [DetectedRelationship] {
        let files = entries.filter { !$0.isDirectory }
        let byName = Dictionary(files.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return rules.compactMap { rule in
            guard let type = RelationshipType(rawValue: rule.relationshipType) else { return nil }
            let requiredEntries = rule.required.compactMap { requirement -> (AnalyzedEntry, String?)? in
                guard let entry = byName[requirement.filename.lowercased()] else { return nil }
                return (entry, requirement.role)
            }
            guard requiredEntries.count == rule.required.count else { return nil }
            guard rule.requiredAnyFilenames.isEmpty || rule.requiredAnyFilenames.contains(where: { byName[$0.lowercased()] != nil }) else { return nil }
            guard rule.requiredRoles.allSatisfy({ role in files.contains { $0.intelligence?.roles.contains { $0.rawValue == role } == true } }) else { return nil }

            let optionalEntries = files.filter { entry in
                rule.optionalFilenames.contains { $0.caseInsensitiveCompare(entry.name) == .orderedSame } ||
                entry.intelligence?.roles.contains { rule.optionalRoles.contains($0.rawValue) } == true
            }
            let optionalDirectories = entries.filter { entry in
                entry.isDirectory && rule.optionalDirectories.contains { $0.caseInsensitiveCompare(entry.name) == .orderedSame }
            }
            guard optionalEntries.count + optionalDirectories.count >= rule.minimumOptionalMatches else { return nil }

            var selected = requiredEntries.map { ($0.0, $0.1) }
            selected += rule.requiredAnyFilenames.compactMap { name in byName[name.lowercased()].map { ($0, nil) } }
            selected += optionalEntries.map { ($0, nil) }
            selected += optionalDirectories.map { ($0, nil) }
            var seen = Set<String>()
            let members = selected.compactMap { entry, explicitRole -> RelationshipMember? in
                guard seen.insert(entry.relativePath).inserted else { return nil }
                return RelationshipMember(relativePath: entry.relativePath, role: role(for: entry, explicitRole: explicitRole))
            }.sorted { $0.relativePath < $1.relativePath }
            return DetectedRelationship(type: type, members: members, confidence: rule.confidence, priority: rule.priority)
        }
    }

    private func role(for entry: AnalyzedEntry, explicitRole: String?) -> RelationshipMember.Role {
        if let explicitRole, let role = relationshipRole(named: explicitRole) { return role }
        if entry.name.lowercased() == "dockerfile" { return .primary }
        if entry.isDirectory && entry.name.lowercased() == "src" { return .source }
        if let semanticRole = entry.intelligence?.roles.first(where: { relationshipRole(named: $0.rawValue) != nil }),
           let role = relationshipRole(named: semanticRole.rawValue) { return role }
        switch entry.name.lowercased() {
        case "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "uv.lock", "poetry.lock", "pipfile.lock", "cargo.lock", "go.sum": return .lockfile
        case "tsconfig.json": return .configuration
        case ".dockerignore": return .supporting
        default: return .supporting
        }
    }

    private func relationshipRole(named rawValue: String) -> RelationshipMember.Role? {
        switch rawValue {
        case "manifest": return .manifest
        case "lockfile": return .lockfile
        case "configuration", "buildConfig": return .configuration
        case "sourceCode": return .source
        case "modelWeights": return .weights
        case "tokenizer": return .tokenizer
        case "bibliography": return .bibliography
        case "database": return .supporting
        case "index": return .index
        case "sidecar": return .supporting
        default: return nil
        }
    }
}
