import Foundation
import CoreGraphics

@main
enum FileIntelligenceRegression {
    static func main() async throws {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("InnerPeekQL/Resources/FileTypes/file-types.json")
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
        try await runMetadataRegression(using: recognizer)

        print("File intelligence and folder analysis regression checks passed.")
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
