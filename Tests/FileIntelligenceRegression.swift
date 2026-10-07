import AppKit
import Foundation
import CoreGraphics

@main
enum FileIntelligenceRegression {
    static func main() async throws {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Knowledge/file-types.json")
        let registry = FileTypeRegistry(data: try Data(contentsOf: resourceURL))
        let recognizer = FileIntelligenceRecognizer(
            registry: registry,
            locale: Locale(identifier: "en_US")
        )

        let expected: [(String, FileCategory, String)] = [
            ("test.py", .sourceCode, "Python Source Code"),
            ("example.swift", .sourceCode, "Swift Source Code"),
            ("guide.pdf", .document, "PDF Document"),
            ("budget.xlsx", .spreadsheet, "Spreadsheet"),
            ("model.onnx", .aiModel, "ONNX Model"),
            ("model.safetensors", .aiModel, "SafeTensors Model"),
            ("array.npy", .scientificData, "NumPy Array"),
            ("scene.blend", .threeD, "Blender Project"),
            ("cache.sqlite", .database, "Database File"),
            ("photo.cr3", .rawImage, "Camera RAW Image")
        ]

        for (fileName, category, typeName) in expected {
            let intelligence = recognizer.intelligence(for: URL(fileURLWithPath: "/tmp/\(fileName)"))
            try expect(intelligence.category == category, "\(fileName) category")
            try expect(intelligence.typeName == typeName, "\(fileName) type name")
            try expect(intelligence.confidence == 1.0, "\(fileName) confidence")
        }

        let chineseRecognizer = FileIntelligenceRecognizer(
            registry: registry,
            locale: Locale(identifier: "zh-Hans_CN")
        )
        try expect(
            chineseRecognizer.intelligence(for: URL(fileURLWithPath: "/tmp/model.onnx")).typeName == "ONNX 模型",
            "Simplified Chinese localization"
        )

        let systemOnlyRecognizer = FileIntelligenceRecognizer(
            registry: FileTypeRegistry(data: Data("[]".utf8)),
            locale: Locale(identifier: "en_US")
        )
        let systemPDF = systemOnlyRecognizer.intelligence(for: URL(fileURLWithPath: "/tmp/system.pdf"))
        try expect(systemPDF.category == .document, "UTType PDF category")
        try expect(systemPDF.confidence == 0.72, "UTType fallback confidence")

        let unknown = recognizer.intelligence(for: URL(fileURLWithPath: "/tmp/opaque.unknowninnerpeek"))
        try expect(unknown.category == .unknown, "unknown extension category")
        try expect(unknown.typeName == "Unknown File", "unknown extension fallback")
        try expect(unknown.confidence == 0.2, "unknown extension confidence")
        try expect(unknown.systemTypeIdentifier == "public.data", "unknown type identifier")

        let communityDefinition = """
        [{"id":"fooai","extensions":["fooai"],"filenames":[],"category":"aiModel","roles":["modelWeights"],"name":{"en":"FooAI Model","zh-Hans":"FooAI 模型"},"description":{"en":"Community model format.","zh-Hans":"社区模型格式。"},"isText":false,"isBinary":true}]
        """
        let communityRecognizer = FileIntelligenceRecognizer(
            registry: FileTypeRegistry(data: Data(communityDefinition.utf8)),
            locale: Locale(identifier: "en_US")
        )
        let communityType = communityRecognizer.intelligence(for: URL(fileURLWithPath: "/tmp/model.fooai"))
        try expect(communityType.category == .aiModel, "community type category")
        try expect(communityType.roles == [.modelWeights], "community type role")

        for (fileName, typeName) in [
            ("README", "Project Documentation"),
            ("Dockerfile", "Container Configuration"),
            ("Makefile", "Build Configuration"),
            ("LICENSE", "License File")
        ] {
            let intelligence = recognizer.intelligence(for: URL(fileURLWithPath: "/tmp/\(fileName)"))
            try expect(intelligence.typeName == typeName, "filename semantic \(fileName)")
        }

        // Coverage added in the knowledge audit: category, role and the .ts correction.
        let roleCases: [(String, FileCategory, SemanticRole?)] = [
            ("main.ts", .sourceCode, .sourceCode), ("video.m2ts", .video, nil), ("clip.mov", .video, nil),
            (".DS_Store", .configuration, .generated), ("Thumbs.db", .configuration, .generated),
            (".gitignore", .configuration, .configuration), (".editorconfig", .configuration, .configuration),
            ("package-lock.json", .configuration, .lockfile), ("Cargo.lock", .configuration, .lockfile), ("yarn.lock", .configuration, .lockfile),
            ("Gemfile", .project, .manifest), ("Jenkinsfile", .project, .buildConfig), ("build.bzl", .project, .buildConfig),
            ("photo.psd", .image, .image), ("icon.eps", .image, .image), ("shot.exr", .image, .image),
            ("report.docm", .document, .document), ("slides.pptm", .document, .document), ("paper.tex", .document, .document),
            ("refs.bib", .document, .bibliography), ("movie.srt", .document, .sidecar), ("invite.ics", .document, .document), ("mail.eml", .document, .document),
            ("cert.pem", .configuration, .configuration), ("keys.p12", .configuration, .configuration),
            ("app.dmg", .archive, .archive), ("mod.pyc", .executable, .generated), ("lib.wasm", .executable, .generated),
            ("deploy.tf", .sourceCode, .configuration), ("api.proto", .sourceCode, .configuration), ("kernel.metal", .sourceCode, .sourceCode),
            ("model.keras", .aiModel, .modelWeights), ("data.pkl", .scientificData, .dataset), ("reads.fastq", .scientificData, .dataset),
            ("Main.storyboard", .project, .configuration), ("App.entitlements", .project, .configuration), ("song.mid", .audio, nil)
        ]
        for (fileName, category, role) in roleCases {
            let found = recognizer.intelligence(for: URL(fileURLWithPath: "/tmp/\(fileName)"))
            try expect(found.category == category, "category of \(fileName): \(found.category)")
            if let role { try expect(found.roles.contains(role), "role of \(fileName)") }
            try expect(found.confidence == 1.0, "\(fileName) is registered, not a system guess")
        }
        // Every registered extension and filename must resolve to exactly one definition.
        var claimed: [String: String] = [:]
        for definition in registry.definitions {
            for key in definition.extensions.map({ "ext:" + $0.lowercased() }) + definition.filenames.map({ "name:" + $0.lowercased() }) {
                try expect(claimed[key] == nil || claimed[key] == definition.id, "ambiguous registration \(key)")
                claimed[key] = definition.id
            }
        }
        try expect(registry.definitions.count >= 90, "registry breadth")

        try runFolderAnalysisRegression(using: registry)
        try runRelationshipRegression(using: recognizer)
        try runInsightRegression(using: recognizer)
        try runGitRepositoryRegression()
        try runProjectIdentityRegression()
        try runProjectRecognitionRegression()
        try runVisualIdentityRegression()
        try runRepositoryHealthRegression()
        try await runZIPRegression(using: registry)
        try await runMetadataRegression(using: recognizer)

        print("Stage 1–5 regression checks passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        guard condition() else { throw RegressionFailure.failed(description) }
    }

    private enum RegressionFailure: Error, CustomStringConvertible {
        case failed(String)
        var description: String {
            switch self { case .failed(let description): return "Regression failed: \(description)" }
        }
    }

    private static func runFolderAnalysisRegression(using registry: FileTypeRegistry) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-FolderAnalyzer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var definitions = try JSONSerialization.jsonObject(with: registryData(registry), options: []) as! [[String: Any]]
        definitions.append([
            "id": "fooai", "extensions": ["fooai"], "filenames": [], "category": "aiModel",
            "roles": ["modelWeights"], "name": ["en": "FooAI Model", "zh-Hans": "FooAI 模型"],
            "description": ["en": "Community model format.", "zh-Hans": "社区模型格式。"],
            "isText": false, "isBinary": true
        ])
        let communityRegistry = FileTypeRegistry(data: try JSONSerialization.data(withJSONObject: definitions))
        let recognizer = FileIntelligenceRecognizer(registry: communityRegistry, locale: Locale(identifier: "en_US"))
        let analyzer = FolderAnalyzer(recognizer: recognizer)

        // Fixture A + B + F: mixed content, exact logical sizes and unknown files.
        try writeFile(root, "main.py", bytes: 11)
        try writeFile(root, "helper.swift", bytes: 13)
        try writeFile(root, "report.pdf", bytes: 17)
        try writeFile(root, "data.csv", bytes: 19)
        try writeFile(root, "image.png", bytes: 23)
        try writeFile(root, "config.yaml", bytes: 29)
        try writeFile(root, "model.onnx", bytes: 31)
        try writeFile(root, "unknown.xyzabc", bytes: 37)
        let mixed = try analyzer.analyze(folderURL: root)
        try expect(mixed.analyzedFileCount == 8, "mixed-content file count")
        try expect(mixed.analyzedDirectoryCount == 0, "mixed-content directory count")
        try expect(mixed.totalKnownFileSize == 180, "logical total size")
        try expect(statistic(.sourceCode, in: mixed)?.fileCount == 2, "source-code category count")
        try expect(statistic(.sourceCode, in: mixed)?.totalKnownSize == 24, "source-code size aggregation")
        try expect(statistic(.aiModel, in: mixed)?.totalKnownSize == 31, "AI-model size aggregation")
        try expect(statistic(.unknown, in: mixed)?.totalKnownSize == 37, "unknown files remain sized")
        try expect(mixed.extensionStatistics.first(where: { $0.fileExtension == "py" })?.totalKnownSize == 11, "extension aggregation")
        try expect(mixed.scanState == .complete, "mixed-content scan complete")

        // Fixture C: ignored directories count at their visible level but do not recurse.
        let ignoredRoot = root.appendingPathComponent("ignored", isDirectory: true)
        try makeDirectory(ignoredRoot.appendingPathComponent("src", isDirectory: true))
        try makeDirectory(ignoredRoot.appendingPathComponent("node_modules/deep", isDirectory: true))
        try writeFile(ignoredRoot, "src/main.py", bytes: 5)
        try writeFile(ignoredRoot, "node_modules/deep/package.js", bytes: 7)
        let ignored = try analyzer.analyze(folderURL: ignoredRoot)
        try expect(ignored.analyzedFileCount == 1, "ignored directory is not traversed")
        try expect(ignored.analyzedDirectoryCount == 2, "ignored directory itself remains counted")

        // Fixture D: direct children are depth 1; depth-2 directories are counted but not opened.
        let depthRoot = root.appendingPathComponent("depth", isDirectory: true)
        try makeDirectory(depthRoot.appendingPathComponent("one/two", isDirectory: true))
        try writeFile(depthRoot, "top.py", bytes: 3)
        try writeFile(depthRoot, "one/two/too-deep.py", bytes: 5)
        let depth = try analyzer.analyze(folderURL: depthRoot)
        try expect(depth.analyzedFileCount == 1, "maximum depth stops deeper files")
        try expect(depth.scanState == .partial([.maximumDepth]), "maximum depth is reported")

        // Fixture E: the entry bound applies to files and directories, excluding the root.
        let entryRoot = root.appendingPathComponent("entries", isDirectory: true)
        try makeDirectory(entryRoot)
        for index in 0..<8 { try writeFile(entryRoot, "\(index).py", bytes: 1) }
        let bounded = try FolderAnalyzer(
            recognizer: recognizer,
            limits: FolderAnalysisLimits(maximumDepth: 2, maximumEntries: 3, ignoredDirectoryNames: [])
        ).analyze(folderURL: entryRoot)
        try expect(bounded.analyzedEntryCount == 3, "entry bound")
        try expect(bounded.analyzedFileCount == 3, "entry-bound file count")
        try expect(bounded.scanState == .partial([.maximumEntries]), "entry bound is reported")

        // Stage 3: important files reuse the bounded analyzed-file list.
        let importantRoot = root.appendingPathComponent("important", isDirectory: true)
        try makeDirectory(importantRoot)
        for (name, size) in [
            ("README.md", 1), ("package.json", 1), ("main.py", 1),
            ("model.safetensors", 1), ("LICENSE", 1), ("index.ts", 1),
            ("notes.txt", 1), ("Dockerfile", 1), ("Makefile", 1),
            ("requirements.txt", 1), ("Cargo.toml", 1)
        ] {
            try writeFile(importantRoot, name, bytes: size)
        }
        let important = ImportantFileDetector(registry: registry).detect(in: try analyzer.analyze(folderURL: importantRoot))
        try expect(important.count == ImportantFileDetector.maximumResults, "important result bound")
        try expect(important.first?.file.intelligence.fileName == "README.md", "README ranks first")
        try expect(important.contains(where: { $0.file.intelligence.fileName == "package.json" }), "manifest is important")
    }

    private static func runRelationshipRegression(using recognizer: FileIntelligenceRecognizer) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-Relationships-\(UUID().uuidString)", isDirectory: true)
        try makeDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyzer = FolderAnalyzer(recognizer: recognizer)
        let engine = RelationshipEngine()

        func fixture(_ name: String, files: [String], directories: [String] = []) throws -> [DetectedRelationship] {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try makeDirectory(folder)
            for directory in directories { try makeDirectory(folder.appendingPathComponent(directory, isDirectory: true)) }
            for file in files { try writeFile(folder, file, bytes: 1) }
            return engine.detect(in: try analyzer.analyze(folderURL: folder))
        }
        func group(_ type: RelationshipType, in relationships: [DetectedRelationship]) -> DetectedRelationship? {
            relationships.first { $0.type == type }
        }

        let shape = try fixture("shape", files: ["map.shp", "map.shx", "map.dbf", "map.prj", "other.dbf"])
        try expect(shape.count == 1, "one Shapefile relationship")
        try expect(group(.shapefile, in: shape)?.members.count == 4, "Shapefile member count")
        try expect((group(.shapefile, in: shape)?.confidence ?? 0) > 0.95, "Shapefile confidence")
        try expect(group(.shapefile, in: shape)?.members.first(where: { $0.relativePath == "map.shp" })?.role == .geometry, "geometry role")
        try expect(group(.shapefile, in: shape)?.members.first(where: { $0.relativePath == "map.shx" })?.role == .index, "index role")
        try expect(group(.shapefile, in: shape)?.members.first(where: { $0.relativePath == "map.dbf" })?.role == .attributes, "attributes role")
        try expect(group(.shapefile, in: shape)?.members.first(where: { $0.relativePath == "map.prj" })?.role == .projection, "projection role")
        let shapeMismatched = try fixture("shape-mismatched", files: ["map.shp", "map.shx", "other.dbf"])
        try expect(shapeMismatched.isEmpty, "different Shapefile stem rejected")
        let shapeIncomplete = try fixture("shape-incomplete", files: ["map.shp", "map.dbf"])
        try expect(shapeIncomplete.isEmpty, "incomplete Shapefile rejected")

        let transformer = try fixture("transformer", files: ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"])
        try expect(group(.transformer, in: transformer)?.members.count == 4, "Transformer model package")
        let configAlone = try fixture("config-alone", files: ["config.json"])
        try expect(configAlone.isEmpty, "config alone rejected")
        let configSettings = try fixture("config-settings", files: ["config.json", "settings.json"])
        try expect(configSettings.isEmpty, "generic configuration rejected")
        let transformerNoWeights = try fixture("transformer-no-weights", files: ["config.json", "tokenizer.json"])
        try expect(transformerNoWeights.isEmpty, "Transformer requires weights")
        let split = try fixture("split-directories", files: ["a/config.json", "b/tokenizer.json", "b/model.safetensors"], directories: ["a", "b"])
        try expect(group(.transformer, in: split) == nil, "different directories are not grouped")

        let latex = try fixture("latex", files: ["main.tex", "references.bib"], directories: ["figures"])
        try expect(group(.latex, in: latex)?.members.count == 3, "LaTeX document set")
        let texAlone = try fixture("tex-alone", files: ["notes.tex"])
        try expect(texAlone.isEmpty, "single TeX file rejected")
        let node = try fixture("node", files: ["package.json", "pnpm-lock.yaml", "tsconfig.json"])
        try expect(group(.node, in: node)?.members.count == 3, "Node package")
        let python = try fixture("python", files: ["pyproject.toml", "uv.lock"], directories: ["src"])
        try expect(group(.python, in: python)?.members.count == 3, "Python project files")
        let rust = try fixture("rust", files: ["Cargo.toml", "Cargo.lock"], directories: ["src"])
        try expect(group(.rust, in: rust)?.members.count == 3, "Rust package")
        let go = try fixture("go", files: ["go.mod", "go.sum"])
        try expect(group(.go, in: go)?.members.count == 2, "Go module")
        let xcode = try fixture("xcode", files: ["Package.resolved"], directories: ["Example.xcodeproj"])
        try expect(group(.xcode, in: xcode)?.members.count == 2, "Xcode project")
        let docker = try fixture("docker", files: ["Dockerfile", "compose.yml", ".dockerignore"])
        try expect(group(.docker, in: docker)?.members.count == 3, "Docker configuration with sidecar")

        let overlap = try fixture("overlap", files: ["package.json", "pnpm-lock.yaml", "Dockerfile", "compose.yml", ".dockerignore"])
        try expect(overlap.count == 2 && group(.node, in: overlap) != nil && group(.docker, in: overlap) != nil, "distinct overlapping relationships coexist")
        try expect(Set(overlap.map { $0.type }).count == overlap.count, "duplicate relationships suppressed")
        let repeatAnalysis = try analyzer.analyze(folderURL: root.appendingPathComponent("overlap"))
        let reference = engine.detect(in: repeatAnalysis)
        for _ in 0..<20 { try expect(engine.detect(in: repeatAnalysis) == reference, "deterministic relationship order") }

        let many = try fixture("many", files: [
            "map.shp", "map.shx", "map.dbf", "config.json", "tokenizer.json", "model.safetensors",
            "main.tex", "references.bib", "package.json", "pnpm-lock.yaml", "Dockerfile", "compose.yml"
        ])
        try expect(many.count > RelationshipEngine.maxDisplayedRelationships, "engine retains more than UI limit")
        try expect(Array(many.prefix(RelationshipEngine.maxDisplayedRelationships)).count == 4, "visible relationship bound")
        let partialFolder = root.appendingPathComponent("python")
        let partial = try FolderAnalyzer(recognizer: recognizer, limits: .init(maximumDepth: 1, maximumEntries: 2000, ignoredDirectoryNames: [])).analyze(folderURL: partialFolder)
        try expect(partial.scanState.isPartial && group(.python, in: engine.detect(in: partial)) != nil, "strong group remains valid in partial analysis")
        let ordinaryPhoto = try fixture("ordinary-photo", files: ["a.jpg", "b.png"])
        try expect(ordinaryPhoto.isEmpty, "ordinary photos do not match software groups")
        let genericDocuments = try fixture("generic-documents", files: ["notes.txt", "report.pdf"])
        try expect(genericDocuments.isEmpty, "generic documents do not match")
        let empty = try fixture("empty", files: [])
        try expect(empty.isEmpty, "empty folder has no relationships")

        let resourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("InnerPeekQL")
        for language in ["en", "zh-Hans"] {
            let strings = try Data(contentsOf: resourceDirectory.appendingPathComponent("\(language).lproj/Localizable.strings"))
            let values = try PropertyListSerialization.propertyList(from: strings, format: nil) as? [String: String] ?? [:]
            try expect(values["detected_relationships"] != nil, "\(language) section localization")
            for type in [RelationshipType.shapefile, .transformer, .latex, .node, .python, .rust, .go, .xcode, .docker] {
                try expect(values["relationship_\(type.rawValue)"] != nil, "\(language) \(type.rawValue) localization")
            }
        }
    }

    private static func runMetadataRegression(using recognizer: FileIntelligenceRecognizer) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InnerPeek-Metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let extractor = MetadataExtractorRegistry()

        try writeData(root, "table.csv", Data("a,b,c,d\n1,2,3,4\n".utf8))
        var values = await metadata(extractor, recognizer, root, "table.csv")
        try expect(values[.columns] == "4", "CSV columns")
        try expect(values[.delimiter] == "Comma", "CSV delimiter")

        try writeData(root, "object.json", Data("{\"one\":1}".utf8))
        values = await metadata(extractor, recognizer, root, "object.json")
        try expect(values[.jsonShape] == "Object", "JSON top-level shape")

        let notebook = "{\"cells\":[{\"cell_type\":\"code\"},{\"cell_type\":\"code\"},{\"cell_type\":\"markdown\"}],\"metadata\":{\"kernelspec\":{\"display_name\":\"Python 3\"}}}"
        try writeData(root, "sample.ipynb", Data(notebook.utf8))
        values = await metadata(extractor, recognizer, root, "sample.ipynb")
        try expect(values[.codeCells] == "2", "notebook code cells")
        try expect(values[.markdownCells] == "1", "notebook markdown cells")

        try writeData(root, "references.bib", Data("@article{a,}\n@book{b,}\n@misc{c,}\n".utf8))
        values = await metadata(extractor, recognizer, root, "references.bib")
        try expect(values[.references] == "3", "BibTeX entries")

        let header = "{'descr': '<f4', 'fortran_order': False, 'shape': (3, 4), }\n"
        var npy = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0])
        let headerLength = UInt16(header.utf8.count)
        npy.append(UInt8(headerLength & 0xff)); npy.append(UInt8(headerLength >> 8)); npy.append(Data(header.utf8))
        try writeData(root, "array.npy", npy)
        values = await metadata(extractor, recognizer, root, "array.npy")
        try expect(values[.shape] == "3 × 4", "NumPy shape")
        try expect(values[.dataType] == "<f4", "NumPy dtype")

        let tensorHeader = Data("{\"tensor\":{\"dtype\":\"F32\"},\"__metadata__\":{\"format\":\"pt\"}}".utf8)
        var safe = Data(); let length = UInt64(tensorHeader.count)
        for index in 0..<8 { safe.append(UInt8((length >> UInt64(index * 8)) & 0xff)) }; safe.append(tensorHeader)
        try writeData(root, "model.safetensors", safe)
        values = await metadata(extractor, recognizer, root, "model.safetensors")
        try expect(values[.tensors] == "1", "SafeTensors count")

        var npz = Data(repeating: 0, count: 22); npz.replaceSubrange(0..<4, with: [0x50, 0x4b, 0x05, 0x06]); npz[10] = 2
        try writeData(root, "arrays.npz", npz)
        values = await metadata(extractor, recognizer, root, "arrays.npz")
        try expect(values[.arrays] == "2", "NPZ central-directory count")

        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8LwAAAABJRU5ErkJggg==")!
        try writeData(root, "pixel.png", image)
        values = await metadata(extractor, recognizer, root, "pixel.png")
        try expect(values[.dimensions] == "1 × 1", "image dimensions")

        let pdfURL = root.appendingPathComponent("two-pages.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 10, height: 10)
        let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil)!
        context.beginPDFPage(nil); context.endPDFPage(); context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        values = await metadata(extractor, recognizer, root, "two-pages.pdf")
        try expect(values[.pages] == "2", "PDF page count")

        try writeData(root, "unhandled.xyzunknown", Data([0x00, 0x01]))
        values = await metadata(extractor, recognizer, root, "unhandled.xyzunknown")
        try expect(values.isEmpty, "unsupported metadata is unavailable")
    }

    private static func runInsightRegression(using recognizer: FileIntelligenceRecognizer) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InnerPeek-Insights-\(UUID().uuidString)", isDirectory: true)
        try makeDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyzer = FolderAnalyzer(recognizer: recognizer)
        let engine = InsightEngine()

        try writeFile(root, "config.json", bytes: 1)
        try writeFile(root, "tokenizer.json", bytes: 1)
        try writeFile(root, "model.safetensors", bytes: 2_048)
        let completeAnalysis = try analyzer.analyze(folderURL: root)
        let completeRelationships = RelationshipEngine().detect(in: completeAnalysis)
        let completeInsights = engine.generate(for: completeAnalysis, relationships: completeRelationships)
        try expect(completeInsights.contains { $0.id == "transformer-model-completeness-complete" }, "complete transformer insight")
        try expect(!completeInsights.contains { $0.id == "small-model-weights" }, "normal model weight size")
        let verdictEngine = SemanticVerdictEngine()
        let completeDecision = verdictEngine.decide(
            analysis: completeAnalysis, relationships: completeRelationships, insights: completeInsights,
            importantFiles: ImportantFileDetector().detect(in: completeAnalysis)
        )
        try expect(completeDecision.verdict?.archetype == .transformerModelPackage, "transformer verdict archetype")
        try expect(completeDecision.verdict?.status == .complete, "complete transformer verdict")
        try expect(Set(completeDecision.evidence.map(\.relativePath)).isSuperset(of: ["config.json", "tokenizer.json", "model.safetensors"]), "transformer verdict evidence")
        try expect(completeDecision.insights.count <= SemanticDecision.maximumVisibleInsights, "decision insight bound")

        let communityRuleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/community-insight.json")
        let communityEngine = InsightEngine(data: try Data(contentsOf: communityRuleURL))
        try expect(communityEngine.generate(for: completeAnalysis, relationships: completeRelationships).contains { $0.id == "foo-model-package-complete" }, "knowledge-only insight rule")

        let missingRequired = DetectedRelationship(type: .transformer, members: [
            RelationshipMember(relativePath: "model.safetensors", role: .weights),
            RelationshipMember(relativePath: "tokenizer.json", role: .tokenizer)
        ], confidence: 0.96, priority: 95)
        let missingRequiredInsights = engine.generate(for: completeAnalysis, relationships: [missingRequired])
        try expect(missingRequiredInsights.first?.severity == .warning, "missing required role warning")

        let missingRecommended = DetectedRelationship(type: .transformer, members: [
            RelationshipMember(relativePath: "model.safetensors", role: .weights),
            RelationshipMember(relativePath: "config.json", role: .configuration)
        ], confidence: 0.96, priority: 95)
        let missingRecommendedInsights = engine.generate(for: completeAnalysis, relationships: [missingRecommended])
        try expect(missingRecommendedInsights.first?.severity == .notice, "missing recommended role notice")

        let partialAnalysis = FolderAnalysis(
            analyzedFileCount: completeAnalysis.analyzedFileCount,
            analyzedDirectoryCount: completeAnalysis.analyzedDirectoryCount,
            analyzedEntryCount: completeAnalysis.analyzedEntryCount,
            totalKnownFileSize: completeAnalysis.totalKnownFileSize,
            categoryStatistics: completeAnalysis.categoryStatistics,
            extensionStatistics: completeAnalysis.extensionStatistics,
            analyzedFiles: completeAnalysis.analyzedFiles,
            analyzedEntries: completeAnalysis.analyzedEntries,
            scanState: .partial([.maximumEntries])
        )
        let partialInsights = engine.generate(for: partialAnalysis, relationships: [missingRequired])
        try expect(!partialInsights.contains { $0.id == "transformer-model-completeness-missing-required" }, "partial scan suppresses missing role")

        let emptyRoot = root.appendingPathComponent("empty-files", isDirectory: true)
        try makeDirectory(emptyRoot)
        try writeFile(emptyRoot, "empty.txt", bytes: 0)
        let emptyInsights = engine.generate(for: try analyzer.analyze(folderURL: emptyRoot), relationships: [])
        try expect(emptyInsights.contains { $0.id == "empty-files" }, "empty file anomaly")

        let smallRoot = root.appendingPathComponent("small-model", isDirectory: true)
        try makeDirectory(smallRoot)
        try writeFile(smallRoot, "config.json", bytes: 1)
        try writeFile(smallRoot, "model.safetensors", bytes: 8)
        let smallAnalysis = try analyzer.analyze(folderURL: smallRoot)
        let smallInsights = engine.generate(for: smallAnalysis, relationships: [missingRecommended])
        try expect(smallInsights.contains { $0.id == "small-model-weights" }, "small model anomaly")

        let abnormalRoot = root.appendingPathComponent("abnormal-transformer", isDirectory: true)
        try makeDirectory(abnormalRoot)
        try writeFile(abnormalRoot, "config.json", bytes: 1)
        try writeFile(abnormalRoot, "tokenizer.json", bytes: 1)
        try writeFile(abnormalRoot, "model.safetensors", bytes: 8)
        let abnormalAnalysis = try analyzer.analyze(folderURL: abnormalRoot)
        let abnormalRelationships = RelationshipEngine().detect(in: abnormalAnalysis)
        let abnormalInsights = engine.generate(for: abnormalAnalysis, relationships: abnormalRelationships)
        let abnormalDecision = verdictEngine.decide(analysis: abnormalAnalysis, relationships: abnormalRelationships,
                                                    insights: abnormalInsights, importantFiles: ImportantFileDetector().detect(in: abnormalAnalysis))
        try expect(abnormalDecision.verdict?.status == .warning, "abnormal transformer verdict priority")
        try expect(abnormalDecision.insights.first?.severity == .warning, "warning insight appears first")

        let concentratedRoot = root.appendingPathComponent("concentrated", isDirectory: true)
        try makeDirectory(concentratedRoot)
        try writeFile(concentratedRoot, "large.dat", bytes: 800)
        try writeFile(concentratedRoot, "a.txt", bytes: 100)
        try writeFile(concentratedRoot, "b.txt", bytes: 100)
        let concentratedInsights = engine.generate(for: try analyzer.analyze(folderURL: concentratedRoot), relationships: [])
        try expect(concentratedInsights.contains { $0.id == "largest-file-concentration" }, "storage concentration")

        let balancedRoot = root.appendingPathComponent("balanced", isDirectory: true)
        try makeDirectory(balancedRoot)
        for index in 0..<4 { try writeFile(balancedRoot, "file-\(index).txt", bytes: 250) }
        let balancedInsights = engine.generate(for: try analyzer.analyze(folderURL: balancedRoot), relationships: [])
        try expect(!balancedInsights.contains { $0.kind == .storage }, "balanced storage has no hotspot")
        let genericAnalysis = try analyzer.analyze(folderURL: balancedRoot)
        let genericDecision = verdictEngine.decide(analysis: genericAnalysis, relationships: [], insights: balancedInsights, importantFiles: [])
        try expect(genericDecision.verdict == nil && genericDecision.insights.isEmpty, "quiet generic folder")
    }

    /// A read-only smoke test against this checkout complements the synthetic
    /// corpus and confirms normal repository metadata is accepted in practice.
    private static func runGitRepositoryRegression() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let context = GitRepositoryInspector().inspect(folderURL: repositoryRoot)
        try expect(context?.state == .repository, "real local Git repository")
        if case let .branch(branch)? = context?.head {
            try expect(!branch.isEmpty, "real local Git branch")
        } else {
            try expect(context?.head == .detached, "real local Git detached HEAD")
        }
    }

    /// The identity object is what presentation renders: it must carry the remote
    /// repository name over a renamed folder, grade confidence by evidence, and
    /// never expose a URL or credential.
    private static func runProjectIdentityRegression() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-Identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func repository(_ name: String, remote: String?) throws -> URL {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            let git = folder.appendingPathComponent(".git", isDirectory: true)
            try makeDirectory(git)
            try "ref: refs/heads/main\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
            if let remote {
                try "[remote \"origin\"]\n\turl = \(remote)\n".write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
            }
            return folder
        }
        let resolver = ProjectIdentityResolver()
        let inspector = GitRepositoryInspector()

        let renamed = try repository("renamed-checkout", remote: "https://user:fake-token@github.com/example/real-name.git")
        let identity = resolver.resolve(folderName: "renamed-checkout", repositoryContext: inspector.inspect(folderURL: renamed))
        try expect(identity.name == "real-name", "identity prefers remote repository name")
        try expect(identity.repository?.provider == .github && identity.repository?.slug == "example/real-name", "identity repository")
        try expect(identity.confidence == .high, "identity confidence with remote")
        try expect(!String(reflecting: identity).contains("fake-token"), "identity omits credentials")

        let local = try repository("local-only", remote: nil)
        let localIdentity = resolver.resolve(folderName: "local-only", repositoryContext: inspector.inspect(folderURL: local))
        try expect(localIdentity.name == "local-only" && localIdentity.confidence == .medium, "identity without remote")
        try expect(localIdentity.repository?.slug == nil, "identity without remote has no slug")

        let plain = root.appendingPathComponent("plain", isDirectory: true)
        try makeDirectory(plain)
        let plainIdentity = resolver.resolve(folderName: "plain", repositoryContext: inspector.inspect(folderURL: plain))
        try expect(plainIdentity.repository == nil && plainIdentity.confidence == .low, "identity of a plain folder")

        let metadataOnly = root.appendingPathComponent("metadata-only", isDirectory: true)
        try makeDirectory(metadataOnly.appendingPathComponent(".github/workflows", isDirectory: true))
        let metadataIdentity = resolver.resolve(folderName: "metadata-only", repositoryContext: inspector.inspect(folderURL: metadataOnly))
        try expect(metadataIdentity.repository == nil && metadataIdentity.confidence == .low, "identity from GitHub metadata only")
    }

    /// Parser edge cases plus the extensibility promise: a new framework is a
    /// knowledge entry, not Swift code.
    private static func runProjectRecognitionRegression() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-Recognition-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func folder(_ name: String, _ files: [String: String]) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try makeDirectory(url)
            for (file, text) in files { try text.write(to: url.appendingPathComponent(file), atomically: true, encoding: .utf8) }
            return url
        }
        func rule(_ id: String, _ file: String, _ key: String) -> String {
            let kind = id.split(separator: ".")[0]
            return #"{"id":"\#(id)","kind":"\#(kind)","name":{"en":"X","zh-Hans":"X"},"evidence":[{"type":"manifest_dependency","file":"\#(file)","key":"\#(key)","weight":0.9}]}"#
        }
        func detected(_ knowledge: [String], in url: URL) -> Set<String> {
            let json = #"{"version":1,"detectionThreshold":0.5,"conflictMargin":0.05,"facts":[\#(knowledge.joined(separator: ","))]}"#
            return Set(ProjectRecognizer(data: Data(json.utf8)).recognize(folderURL: url).facts.map(\.id))
        }

        let requirements = try folder("requirements", ["requirements.txt": """
            # comment
            Django[argon2]>=4.2 ; python_version > '3.9'
            -r base.txt
            git+https://example.test/x/y.git#egg=y
            Flask_Login==1.0   # trailing comment
            """])
        let found = detected([rule("framework.django", "requirements.txt", "django"), rule("framework.flasklogin", "requirements.txt", "flask-login"),
                              rule("framework.base", "requirements.txt", "base"), rule("framework.y", "requirements.txt", "y")], in: requirements)
        try expect(found == ["framework.django", "framework.flasklogin"], "requirements.txt parsing: extras, markers, comments, name normalization")

        let pyproject = try folder("pyproject", ["pyproject.toml": """
            [project]
            name = "demo"  # not a dependency
            dependencies = [
              "FastAPI>=0.100",   # api
              'uvicorn[standard]',
            ]

            [project.optional-dependencies]
            dev = ["pytest"]

            [tool.poetry.dependencies]
            python = "^3.12"
            "Rich" = "^13"
            """])
        let pyFound = detected([rule("framework.fastapi", "pyproject.toml", "fastapi"), rule("framework.uvicorn", "pyproject.toml", "uvicorn"),
                                rule("framework.pytest", "pyproject.toml", "pytest"), rule("framework.rich", "pyproject.toml", "rich"),
                                rule("framework.python", "pyproject.toml", "python"), rule("framework.demo", "pyproject.toml", "demo")], in: pyproject)
        try expect(pyFound == ["framework.fastapi", "framework.uvicorn", "framework.pytest", "framework.rich"], "pyproject.toml parsing: multi-line arrays, extras, quoted keys, python excluded")

        let cargo = try folder("cargo", ["Cargo.toml": """
            [package]
            name = "demo"
            [dependencies]
            serde = { version = "1", features = ["derive"] }
            tokio.workspace = true
            [dependencies.clap]
            version = "4"
            [target.'cfg(unix)'.dependencies]
            libc = "0.2"
            """])
        let cargoFound = detected([rule("framework.serde", "Cargo.toml", "serde"), rule("framework.tokio", "Cargo.toml", "tokio"),
                                   rule("framework.clap", "Cargo.toml", "clap"), rule("framework.libc", "Cargo.toml", "libc"),
                                   rule("framework.demo", "Cargo.toml", "demo")], in: cargo)
        try expect(cargoFound == ["framework.serde", "framework.tokio", "framework.clap", "framework.libc"], "Cargo.toml parsing: inline tables, dotted keys, dependency tables, target tables")

        let goMod = try folder("gomod", ["go.mod": "module example.test/m\nrequire github.com/a/single v1.0.0 // indirect\nrequire (\n\tgithub.com/b/block v1.0.0\n)\n"])
        let goFound = detected([rule("framework.single", "go.mod", "github.com/a/single"), rule("framework.block", "go.mod", "github.com/b/block"),
                                rule("framework.module", "go.mod", "example.test/m")], in: goMod)
        try expect(goFound == ["framework.single", "framework.block"], "go.mod parsing: single-line and block requires")

        // Extensibility: nothing but a data-declared rule distinguishes this ecosystem.
        let extra = try folder("extra", ["package.json": #"{"devDependencies":{"@acme/widget-kit":"1"}}"#])
        try expect(detected([rule("framework.widgetkit", "package.json", "@acme/widget-kit")], in: extra) == ["framework.widgetkit"], "new framework from knowledge data alone")

        // Broken knowledge must never crash or invent facts.
        let any = try folder("any", ["package.json": "{}"])
        try expect(ProjectRecognizer(data: Data("not json".utf8)).recognize(folderURL: any) == .empty, "malformed knowledge yields no facts")
        try expect(ProjectRecognizer(data: Data("{}".utf8)).recognize(folderURL: any) == .empty, "incomplete knowledge yields no facts")
        try expect(ProjectRecognizer().recognize(folderURL: root.appendingPathComponent("does-not-exist")) == .empty
                   || ProjectRecognizer().recognize(folderURL: root.appendingPathComponent("does-not-exist")).facts.isEmpty, "missing folder yields no facts")

        // extension_share consumes the analyzer's bounded file list, honours both thresholds, and stays traceable.
        let shareRule = #"{"id":"language.lang","kind":"language","name":{"en":"L","zh-Hans":"L"},"evidence":[{"type":"extension_share","extensions":["foo"],"minimumFiles":2,"minimumShare":0.5,"weight":0.7}]}"#
        let shareJSON = Data(#"{"version":1,"detectionThreshold":0.5,"conflictMargin":0.05,"facts":[\#(shareRule)]}"#.utf8)
        func shareFacts(_ files: [String]) throws -> [DetectedFact] {
            let url = try folder("share-\(UUID().uuidString)", [:])
            for file in files { try "x".write(to: url.appendingPathComponent(file), atomically: true, encoding: .utf8) }
            let analysis = try FolderAnalyzer().analyze(folderURL: url)
            return ProjectRecognizer(data: shareJSON).recognize(folderURL: url, entries: analysis.analyzedEntries).facts
        }
        let enough = try shareFacts(["a.foo", "b.FOO", "c.txt"])
        try expect(enough.map(\.id) == ["language.lang"] && enough[0].evidence[0].relativePath == "a.foo" && enough[0].evidence[0].key == "foo", "extension_share match is case-insensitive and traceable")
        let shareEvidence = enough[0].evidence[0]
        try expect(shareEvidence.matchedFiles == 2 && abs((shareEvidence.share ?? 0) - 2.0 / 3.0) < 0.001, "extension_share records count and share")
        try expect(shareEvidence.explanation.value(for: Locale(identifier: "en")) == "67% of analysed files are .foo (2 files)"
                   && shareEvidence.explanation.value(for: Locale(identifier: "zh-Hans")) == "已分析文件中 67% 为 .foo（2 个）", "extension_share explanation")
        let sparse = try shareFacts(["a.foo", "b.txt", "c.txt"])
        try expect(sparse.isEmpty, "extension_share respects minimumFiles and minimumShare")
        let none = try shareFacts([])
        try expect(none.isEmpty, "extension_share on an empty folder")

        // source_import: statement-start imports only, per-language grammar, bounded.
        func importFacts(_ files: [String: String], rule: String) throws -> Set<String> {
            let url = try folder("imports-\(UUID().uuidString)", [:])
            for (name, text) in files { try text.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            let analysis = try FolderAnalyzer().analyze(folderURL: url)
            let json = Data(#"{"version":1,"detectionThreshold":0.5,"conflictMargin":0.05,"facts":[\#(rule)]}"#.utf8)
            return Set(ProjectRecognizer(data: json).recognize(folderURL: url, entries: analysis.analyzedEntries).facts.map(\.id))
        }
        func importRule(_ extensions: String, _ module: String, minimumFiles: Int = 1) -> String {
            #"{"id":"framework.m","kind":"framework","name":{"en":"M","zh-Hans":"M"},"evidence":[{"type":"source_import","extensions":[\#(extensions)],"module":"\#(module)","minimumFiles":\#(minimumFiles),"weight":0.8}]}"#
        }
        func modules(_ text: String, _ ext: String) -> Set<String> { RecognitionWorkspaceTestHook.modules(text, ext) }
        try expect(modules("import SwiftUI\n@testable import Foo.Bar\nimport struct Foundation.URL\n// import Nope\n", "swift") == ["swiftui", "foo", "foundation"], "swift imports")
        try expect(modules("import os, numpy as np\nfrom torch.nn import Module\nfrom . import x\nfrom .y import z\n# import no\n", "py") == ["os", "numpy", "torch"], "python imports")
        try expect(modules("import React from 'react';\nimport {a} from \"@scope/pkg/sub\";\nconst b = require('lodash/fp');\nimport './local';\nimport 'side-effect';\nexport * from \"../up\";\n", "ts") == ["react", "@scope/pkg", "lodash", "side-effect"], "javascript imports")
        try expect(modules("import static org.springframework.boot.SpringApplication.run;\nimport org.springframework.boot.autoconfigure.SpringBootApplication;\n", "java") == ["org.springframework.boot.springapplication.run", "org.springframework.boot.autoconfigure.springbootapplication"], "java imports")
        try expect(modules("import Foo\n", "rb").isEmpty, "unsupported language yields no imports")
        let torchRule = importRule(#""py""#, "torch")
        let sameName = try importFacts(["a.py": "import torchvision\n", "b.py": "from .torch import x\n"], rule: torchRule)
        try expect(sameName.isEmpty, "torchvision and relative torch are not torch")
        let two = try importFacts(["a.py": "import torch\n", "b.py": "x = 1\n"], rule: importRule(#""py""#, "torch", minimumFiles: 2))
        try expect(two.isEmpty, "source_import honours minimumFiles")
        let javaPrefix = try importFacts(["A.java": "import org.springframework.boot.SpringApplication;\n"], rule: importRule(#""java""#, "org.springframework.boot"))
        try expect(javaPrefix == ["framework.m"], "java module prefix match")

        // Identity aggregation: confidence is the stronger of repository and best primary fact.
        let identityFolder = try folder("identity", ["package.json": #"{"dependencies":{"next":"1","react":"1"}}"#, "tsconfig.json": "{}", "pnpm-lock.yaml": "x"])
        let recognition = ProjectRecognizer().recognize(folderURL: identityFolder)
        let identity = ProjectIdentityResolver().resolve(folderName: "identity", repositoryContext: nil, recognition: recognition)
        try expect(identity.primaryFramework?.id == "framework.nextjs", "identity primary framework")
        try expect(identity.frameworks.map(\.id) == ["framework.nextjs", "framework.react"], "identity frameworks list primary first")
        try expect(identity.primaryLanguage?.id == "language.typescript" && identity.languages.last?.role == .supporting, "identity language roles")
        try expect(identity.primaryPackageManager?.id == "packageManager.pnpm", "identity package manager")
        try expect(identity.technologyStack.map(\.id) == ["framework.nextjs", "language.typescript", "packageManager.pnpm"], "technology stack order, no supporting facts")
        let pathEvidence = RecognitionEvidence(type: .manifestDependency, relativePath: "package.json", key: "next", weight: 0.9)
        try expect(pathEvidence.explanation.value(for: Locale(identifier: "en")) == "package.json depends on next"
                   && pathEvidence.explanation.value(for: Locale(identifier: "zh-Hans")) == "package.json 依赖 next", "dependency evidence explanation")
        try expect(identity.confidence == .high && identity.repository == nil, "identity confidence from facts without a repository")
        let bare = ProjectIdentityResolver().resolve(folderName: "bare", repositoryContext: nil)
        try expect(bare.facts.isEmpty && bare.confidence == .low, "identity without recognition stays low")
    }

    /// Icon choice is data-driven: keys come from the knowledge, priority is fixed,
    /// and every failure mode degrades to a glyph instead of throwing.
    private static func runVisualIdentityRegression() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-Visual-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = IconCatalog()
        let resolver = VisualIdentityResolver(catalog: catalog)

        func identity(_ files: [String: String], remote: String? = nil) throws -> ProjectIdentity {
            let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try makeDirectory(url)
            for (name, text) in files {
                let file = url.appendingPathComponent(name)
                try makeDirectory(file.deletingLastPathComponent())
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
            if let remote {
                try makeDirectory(url.appendingPathComponent(".git"))
                try "ref: refs/heads/main\n".write(to: url.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
                try "[remote \"origin\"]\n\turl = \(remote)\n".write(to: url.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
            }
            let analysis = try FolderAnalyzer().analyze(folderURL: url)
            return ProjectIdentityResolver().resolve(folderName: "p", repositoryContext: analysis.repositoryContext, recognition: analysis.projectRecognition)
        }

        let next = resolver.resolve(try identity([
            "package.json": #"{"dependencies":{"next":"1","react":"1"},"devDependencies":{"typescript":"5"}}"#,
            "pnpm-lock.yaml": "x", "turbo.json": "{}", "tsconfig.json": "{}"
        ], remote: "https://github.com/example/web.git"))
        try expect(next.primaryIconKey == "brand.nextjs", "primary icon is the primary framework")
        try expect(next.secondaryIconKeys == ["brand.typescript", "brand.pnpm", "brand.turborepo", "brand.github"], "secondary icons: other primary technologies then the host, no superseded React")

        try expect(next.technologyIconKey == "brand.nextjs" && next.repositoryIconKey == "brand.github", "technology and repository icons are separate")
        let swift = resolver.resolve(try identity(["Package.swift": "//", "App.xcodeproj/project.pbxproj": "x"]))
        try expect(swift.primaryIconKey == "brand.swift" && swift.secondaryIconKeys.contains("brand.xcode"), "Swift project shows Swift, Xcode is a badge")

        let django = resolver.resolve(try identity(["requirements.txt": "Django==5\n", "manage.py": "x"]))
        try expect(django.primaryIconKey == "brand.django", "Django outranks Python")

        let gitOnly = resolver.resolve(try identity(["notes.txt": "x"], remote: "https://gitlab.com/example/x.git"))
        try expect(gitOnly.technologyIconKey == nil && gitOnly.repositoryIconKey == "brand.gitlab", "a host logo is never reported as the technology")
        try expect(gitOnly.primaryIconKey == "brand.gitlab" && gitOnly.secondaryIconKeys.isEmpty, "repository host logo for a project without recognised technology")
        let customHost = resolver.resolve(try identity(["notes.txt": "x"], remote: "https://git.example.test/team/x.git"))
        try expect(customHost.primaryIconKey == "brand.git", "unknown host falls back to the Git logo")

        let csharp = resolver.resolve(try identity(["App.csproj": "<Project/>"]))
        try expect(csharp.primaryIconKey == nil && csharp.fallback == .kind(.language), "recognised technology without a logo gets its glyph")
        let plain = resolver.resolve(try identity(["notes.txt": "x"]))
        try expect(plain.primaryIconKey == nil && plain.fallback == .generic && plain.secondaryIconKeys.isEmpty, "unrecognised folder is generic")

        // Registry mismatch: a fact pointing at a key the catalog does not know is ignored.
        let broken = IconCatalog(data: Data(#"{"version":1,"icons":{},"repositoryProviders":{"github":"brand.github","gitlab":"brand.gitlab","bitbucket":"brand.bitbucket","other":"brand.git"}}"#.utf8))
        let degraded = VisualIdentityResolver(catalog: broken).resolve(next.primaryIconKey == nil ? try identity([:]) : try identity(["package.json": #"{"dependencies":{"next":"1"}}"#]))
        try expect(degraded.primaryIconKey == nil && degraded.secondaryIconKeys.isEmpty && degraded.fallback == .kind(.framework), "unknown registry keys degrade to a glyph")
        try expect(IconCatalog(data: Data("not json".utf8)).entries.isEmpty, "malformed icon registry yields an empty catalog")

        // Every key referenced by knowledge resolves to a decodable bundled SVG.
        let knowledgeBundle = Bundle(path: repositoryRoot.appendingPathComponent("Knowledge").path)!
        let registry = IconRegistry(catalog: catalog, bundle: knowledgeBundle)
        try expect(catalog.entries.count >= 30, "icon catalog is populated")
        for key in catalog.entries.keys.sorted() {
            guard let image = registry.brandImage(for: key), image.size.width > 0, image.isTemplate == catalog.entries[key]?.monochrome else {
                throw RegressionFailure.failed("brand image decodes: \(key)")
            }
        }
        try expect(catalog.entries.values.contains { !$0.monochrome } && catalog.entries.values.contains { $0.monochrome }, "catalog has coloured and template icons")
        try expect(registry.brandImage(for: "brand.does-not-exist") == nil, "unknown brand key yields no image")
        for fallback in [VisualFallback.kind(.framework), .kind(.language), .kind(.buildSystem), .kind(.packageManager), .kind(.projectKind), .repository, .generic] {
            let visual = VisualIdentity(primaryIconKey: "brand.missing", fallback: fallback, technologyIconKey: nil, repositoryIconKey: nil, secondaryIconKeys: [])
            try expect(registry.image(for: visual).size.width > 0, "fallback image always exists")
            try expect(NSImage(systemSymbolName: IconCatalog.fallbackSymbol(for: fallback), accessibilityDescription: nil) != nil, "fallback SF Symbol exists: \(IconCatalog.fallbackSymbol(for: fallback))")
        }
    }

    /// Health judges expected practices from recognised facts and speaks in both languages.
    private static func runRepositoryHealthRegression() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-Health-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func insights(_ files: [String], repository: Bool = false) throws -> [Insight] {
            let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try makeDirectory(url)
            if repository {
                try makeDirectory(url.appendingPathComponent(".git"))
                try "ref: refs/heads/main\n".write(to: url.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
            }
            for file in files {
                let target = url.appendingPathComponent(file)
                try makeDirectory(target.deletingLastPathComponent())
                try (file == "pyproject.toml" ? "[project]\nname = \"x\"\n" : "x").write(to: target, atomically: true, encoding: .utf8)
            }
            let analysis = try FolderAnalyzer().analyze(folderURL: url)
            return InsightEngine().generate(for: analysis, relationships: [], importantFiles: [])
        }
        func health(_ insights: [Insight]) -> Insight? { insights.first { $0.id.hasPrefix("repo-health") } }
        let en = Locale(identifier: "en"), zh = Locale(identifier: "zh-Hans")

        let gaps = health(try insights(["pyproject.toml", "src/main.py"]))
        try expect(gaps?.id == "repo-health-gaps" && gaps?.severity == .notice, "missing README and tests is a notice")
        try expect(gaps?.localizedTitle(for: en) == "Not found: README, License, Tests" && gaps?.localizedTitle(for: zh) == "未发现：README、许可证、测试", "gap title lists missing items in each language")

        let licenceOnly = health(try insights(["pyproject.toml", "README.md", "tests/test_a.py", ".github/workflows/ci.yml"], repository: true))
        try expect(licenceOnly?.id == "repo-health-gaps" && licenceOnly?.severity == .info, "a missing licence alone is informational")
        try expect(licenceOnly?.localizedTitle(for: en) == "Not found: License", "licence gap title")

        let complete = health(try insights(["pyproject.toml", "README.md", "LICENSE", "tests/test_a.py", ".github/workflows/ci.yml", "CONTRIBUTING.md", "docs/index.md"], repository: true))
        try expect(complete?.id == "repo-health-complete" && complete?.severity == .positive, "all basics present is positive")
        try expect(complete?.localizedDetail(for: zh) == "已具备：README、许可证、测试、持续集成、贡献指南、文档目录", "complete detail names core then extras")

        let withoutRepository = health(try insights(["package.json", "README.md", "LICENSE", "tests/a.test.js"]))
        try expect(withoutRepository?.id == "repo-health-complete", "CI is not demanded outside a repository")
        let presentCI = health(try insights(["package.json", "README.md", "LICENSE", "tests/a.test.js", ".github/workflows/ci.yml"]))
        try expect(presentCI?.localizedDetail(for: en)?.contains("CI") == true, "CI is shown when present even without a repository")

        let byName = health(try insights(["pyproject.toml", "README.md", "LICENSE", "pages/tests.py"]))
        try expect(byName?.id == "repo-health-complete", "tests recognised by file name")
        let plain = health(try insights(["README.md", "LICENSE", "notes.txt"]))
        try expect(plain == nil, "a plain folder is not graded")
        let opaque = health(try insights(["a.zzz"]))
        try expect(opaque == nil, "a folder with no README or code is not graded")

        // Declarative: names, severities and applicability come from data.
        let data = Data(#"{"version":1,"appliesWhenAny":["language"],"minimumCoreChecks":1,"checks":[{"id":"health.readme","practice":"practice.readme","name":{"en":"Readme","zh-Hans":"自述"},"importance":"core","missingSeverity":"warning"}],"messages":{"complete":{"title":{"en":"ok","zh-Hans":"好"},"detail":{"en":"Has %@","zh-Hans":"有%@"}},"gaps":{"title":{"en":"No %@","zh-Hans":"无%@"},"detail":{"en":"d","zh-Hans":"d"}}}}"#.utf8)
        let custom = RepositoryHealthEvaluator(data: data)
        let recognition = ProjectRecognition(facts: [], conflicts: [])
        try expect(custom.evaluate(recognition: recognition, repositoryContext: nil) == nil, "custom knowledge: not applicable without a language")
        try expect(RepositoryHealthEvaluator(data: Data("nope".utf8)).evaluate(recognition: recognition, repositoryContext: nil) == nil, "malformed health knowledge yields nothing")
    }

    private static func runZIPRegression(using registry: FileTypeRegistry) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnerPeek-ZIP-(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        try makeDirectory(source)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(source, "config.json", bytes: 3)
        try writeFile(source, "tokenizer.json", bytes: 3)
        try writeFile(source, "model.fooai", bytes: 2_048)
        let archive = root.appendingPathComponent("model-package.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = source
        zip.arguments = ["-q", "-r", archive.path, "."]
        try zip.run()
        zip.waitUntilExit()
        try expect(zip.terminationStatus == 0, "ZIP fixture creation")

        var definitions = try JSONSerialization.jsonObject(with: registryData(registry), options: []) as! [[String: Any]]
        definitions.append([
            "id": "fooai", "extensions": ["fooai"], "filenames": [], "category": "aiModel",
            "roles": ["modelWeights"], "name": ["en": "FooAI Model", "zh-Hans": "FooAI 模型"],
            "description": ["en": "Community model format.", "zh-Hans": "社区模型格式。"],
            "isText": false, "isBinary": true
        ])
        let communityRegistry = FileTypeRegistry(data: try JSONSerialization.data(withJSONObject: definitions))
        let recognizer = FileIntelligenceRecognizer(registry: communityRegistry, locale: Locale(identifier: "en_US"))
        let filesystemAnalysis = try FolderAnalyzer(recognizer: recognizer).analyze(folderURL: source)
        let provider = ZIPContentProvider(archiveURL: archive)
        let analysis = try provider.semanticAnalysis(recognizer: recognizer)
        try expect(analysis.sourceKind == .zip, "ZIP source kind")
        try expect(analysis.analyzedFileCount == 3, "ZIP semantic file count")
        try expect(analysis.totalKnownFileSize == 2_054, "ZIP logical uncompressed size")
        try expect(analysis.analyzedEntries.contains { $0.relativePath == "model.fooai" }, "ZIP community entry")
        try expect(analysis.analyzedEntries.allSatisfy { !$0.relativePath.isEmpty }, "ZIP stable relative paths")

        let relationships = RelationshipEngine().detect(in: analysis)
        let filesystemRelationships = RelationshipEngine().detect(in: filesystemAnalysis)
        try expect(Set(relationships.map(\.type)) == Set(filesystemRelationships.map(\.type)), "folder and ZIP relationship parity")
        try expect(analysis.categoryStatistics == filesystemAnalysis.categoryStatistics, "folder and ZIP category parity")
        try expect(relationships.contains { $0.type == .transformer }, "ZIP transformer relationship: \(relationships.map { $0.type.rawValue }) / \(analysis.analyzedEntries.compactMap { $0.intelligence?.roles })")
        let standardInsights = InsightEngine().generate(for: analysis, relationships: relationships)
        try expect(standardInsights.contains { $0.id == "transformer-model-completeness-complete" }, "ZIP standard insight")
        let filesystemInsights = InsightEngine().generate(for: filesystemAnalysis, relationships: filesystemRelationships)
        let zipDecision = SemanticVerdictEngine().decide(analysis: analysis, relationships: relationships, insights: standardInsights,
                                                         importantFiles: ImportantFileDetector(registry: communityRegistry).detect(in: analysis))
        let filesystemDecision = SemanticVerdictEngine().decide(analysis: filesystemAnalysis, relationships: filesystemRelationships, insights: filesystemInsights,
                                                                importantFiles: ImportantFileDetector(registry: communityRegistry).detect(in: filesystemAnalysis))
        try expect(zipDecision.verdict == filesystemDecision.verdict, "folder and ZIP verdict parity")
        try expect(zipDecision.evidence.allSatisfy { evidence in
            analysis.analyzedEntries.contains { $0.relativePath == evidence.relativePath }
        }, "ZIP evidence stays within analyzed entries")

        let rootItems = try await provider.loadRoot()
        try expect(rootItems.contains { $0.relativePath == "model.fooai" }, "ZIP browse path preserved")
        let extractionMarker = root.appendingPathComponent("model.fooai")
        try expect(!FileManager.default.fileExists(atPath: extractionMarker.path), "ZIP semantic analysis does not extract")
    }

    private static func registryData(_ registry: FileTypeRegistry) throws -> Data {
        try JSONSerialization.data(withJSONObject: registry.definitions.map { definition in
            ["id": definition.id, "extensions": definition.extensions, "filenames": definition.filenames,
             "category": definition.category.rawValue, "roles": definition.roles.map(\.rawValue),
             "name": ["en": definition.name.english, "zh-Hans": definition.name.simplifiedChinese],
             "description": ["en": definition.description.english, "zh-Hans": definition.description.simplifiedChinese],
             "isText": definition.isText, "isBinary": definition.isBinary]
        })
    }

    private static func metadata(_ extractor: MetadataExtractorRegistry, _ recognizer: FileIntelligenceRecognizer, _ root: URL, _ name: String) async -> [MetadataItem.Key: String] {
        let url = root.appendingPathComponent(name)
        let values = (try? await extractor.extract(from: url, intelligence: recognizer.intelligence(for: url))) ?? []
        return Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value) })
    }

    private static func statistic(_ category: FileCategory, in analysis: FolderAnalysis) -> CategoryStatistic? {
        analysis.categoryStatistics.first(where: { $0.category == category })
    }

    private static func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func writeFile(_ root: URL, _ relativePath: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    private static func writeData(_ root: URL, _ relativePath: String, _ data: Data) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
