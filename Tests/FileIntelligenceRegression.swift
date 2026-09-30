import Foundation

@main
enum FileIntelligenceRegression {
    static func main() throws {
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

        print("File intelligence regression checks passed (\(expected.count) known formats + localization + fallback).")
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
}
