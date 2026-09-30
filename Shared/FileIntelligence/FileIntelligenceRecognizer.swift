import Foundation
import UniformTypeIdentifiers

/// Resolves a URL through macOS's type system first, then enriches it with
/// InnerPeek's extension registry when the registry has a more useful answer.
struct FileIntelligenceRecognizer: Sendable {
    let registry: FileTypeRegistry
    let locale: Locale

    init(registry: FileTypeRegistry = .shared, locale: Locale = .current) {
        self.registry = registry
        self.locale = locale
    }

    func intelligence(for url: URL) -> FileIntelligence {
        let fileExtension = normalizedExtension(of: url)
        // Resolve the system type before consulting our registry. The registry
        // may then replace a broad or dynamic system type with a precise,
        // human-readable definition for a specialist format.
        let systemType = fileExtension.flatMap {
            UTType(filenameExtension: $0, conformingTo: .data)
        }

        if let definition = registry.definition(forFileName: url.lastPathComponent)
            ?? registry.definition(forExtension: fileExtension) {
            return FileIntelligence(
                fileName: url.lastPathComponent,
                fileExtension: fileExtension,
                category: definition.category,
                roles: definition.roles,
                typeName: definition.displayName(for: locale),
                purpose: definition.purpose(for: locale),
                systemTypeIdentifier: systemType?.isDynamic == false ? systemType?.identifier : "public.data",
                confidence: 1.0
            )
        }

        // `UTType` can synthesize a dynamic identifier for any arbitrary
        // extension. Treat those as unresolved so the final fallback remains
        // an honest “Unknown File”, rather than presenting a made-up type.
        if let systemType, !systemType.isDynamic {
            return FileIntelligence(
                fileName: url.lastPathComponent,
                fileExtension: fileExtension,
                category: category(for: systemType),
                roles: [],
                typeName: systemType.localizedDescription ?? systemType.identifier,
                purpose: nil,
                systemTypeIdentifier: systemType.identifier,
                confidence: 0.72
            )
        }

        return FileIntelligence(
            fileName: url.lastPathComponent,
            fileExtension: fileExtension,
            category: .unknown,
            roles: [],
            typeName: localized("Unknown File", "未知文件"),
            purpose: nil,
            systemTypeIdentifier: "public.data",
            confidence: 0.2
        )
    }

    private func normalizedExtension(of url: URL) -> String? {
        let fileExtension = FileTypeRegistry.normalize(url.pathExtension)
        return fileExtension.isEmpty ? nil : fileExtension
    }

    private func category(for type: UTType) -> FileCategory {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .executable) { return .executable }
        if type.conforms(to: .text) { return .document }
        if type.conforms(to: .pdf) { return .document }
        return .unknown
    }

    private func localized(_ english: String, _ simplifiedChinese: String) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        return languageCode == "zh" ? simplifiedChinese : english
    }
}
