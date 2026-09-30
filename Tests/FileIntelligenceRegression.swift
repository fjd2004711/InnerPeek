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

        try runFolderAnalysisRegression(using: registry)
        try runRelationshipRegression(using: recognizer)
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

        let recognizer = FileIntelligenceRecognizer(registry: registry, locale: Locale(identifier: "en_US"))
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
