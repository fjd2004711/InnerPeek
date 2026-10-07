import Foundation

/// Data side of the icon layer: which brand keys exist and which bundled asset
/// each one names. It holds no images, so recognition and visual-identity logic
/// stay testable without AppKit.
struct IconCatalog: Sendable {
    struct Entry: Decodable, Sendable, Hashable {
        let asset: String
        let upstream: String
        let monochrome: Bool
        let color: String
    }

    private struct Document: Decodable {
        let icons: [String: Entry]
        let repositoryProviders: [String: String]
    }

    let entries: [String: Entry]
    private let providerKeys: [String: String]

    init(data: Data? = nil) {
        let bundled = Bundle(for: FileTypeRegistry.self).url(forResource: "icon-registry", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Knowledge/icon-registry.json")
        let document = (data ?? bundled ?? (try? Data(contentsOf: sourceURL))).flatMap { try? JSONDecoder().decode(Document.self, from: $0) }
        entries = document?.icons ?? [:]
        providerKeys = document?.repositoryProviders ?? [:]
    }

    func entry(for key: String) -> Entry? { entries[key] }

    /// The registry key for a repository host, or `nil` when that key is unknown.
    func repositoryIconKey(for provider: GitRemoteProvider) -> String? {
        providerKeys[provider.rawValue].flatMap { entries[$0] != nil ? $0 : nil }
    }

    /// SF Symbol used when a brand asset is unavailable. The final fallback is `folder`.
    static func fallbackSymbol(for fallback: VisualFallback) -> String {
        switch fallback {
        case .kind(.framework): return "app.dashed"
        case .kind(.language): return "chevron.left.forwardslash.chevron.right"
        case .kind(.buildSystem): return "hammer"
        case .kind(.packageManager): return "shippingbox"
        case .kind(.projectKind): return "square.stack.3d.up"
        case .kind(.practice): return "checklist"
        case .repository: return "point.3.connected.trianglepath.dotted"
        case .generic: return "folder"
        }
    }
}
