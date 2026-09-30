import Foundation
import ImageIO
import AVFoundation
import PDFKit

/// Dispatches bounded, read-only file metadata extraction. Extractors are
/// ordered only as a deterministic fallback; a file is handled by one format
/// specialist, never by a chain of increasingly expensive probes.
struct MetadataExtractorRegistry: Sendable {
    private let extractors: [any MetadataExtracting]

    init(extractors: [any MetadataExtracting] = [
        NativeMediaMetadataExtractor(),
        StructuredTextMetadataExtractor(),
        SpecializedHeaderMetadataExtractor()
    ]) {
        self.extractors = extractors
    }

    func extract(from url: URL, intelligence: FileIntelligence) async throws -> [MetadataItem] {
        guard let extractor = extractors.first(where: { $0.supports(intelligence) }) else { return [] }
        return try await extractor.extract(from: url, intelligence: intelligence)
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.key.rawValue < rhs.key.rawValue : lhs.priority > rhs.priority
            }
            .prefix(5)
            .map { $0 }
    }
}

private struct NativeMediaMetadataExtractor: MetadataExtracting {
    func supports(_ intelligence: FileIntelligence) -> Bool {
        intelligence.category == .image || intelligence.category == .rawImage ||
        intelligence.category == .video || intelligence.category == .audio ||
        intelligence.fileExtension == "pdf"
    }

    func extract(from url: URL, intelligence: FileIntelligence) async throws -> [MetadataItem] {
        try Task.checkCancellation()
        if intelligence.fileExtension == "pdf" {
            return PDFDocument(url: url).map { [MetadataItem(key: .pages, value: "\($0.pageCount)", priority: 100)] } ?? []
        }
        if intelligence.category == .image || intelligence.category == .rawImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return [] }
            return [MetadataItem(key: .dimensions, value: "\(width.intValue) × \(height.intValue)", priority: 100)]
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        try Task.checkCancellation()
        var items: [MetadataItem] = []
        if duration.isNumeric, duration.seconds.isFinite {
            items.append(MetadataItem(key: .duration, value: Self.durationFormatter.string(from: duration.seconds) ?? "", priority: 100))
        }
        if intelligence.category == .video,
           let track = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            if size.width > 0, size.height > 0 {
                items.append(MetadataItem(key: .dimensions, value: "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))", priority: 90))
            }
        }
        return items.filter { !$0.value.isEmpty }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

private struct StructuredTextMetadataExtractor: MetadataExtracting {
    private static let maximumReadBytes = 256 * 1024

    func supports(_ intelligence: FileIntelligence) -> Bool {
        ["csv", "tsv", "tab", "json", "jsonc", "json5", "ipynb", "bib"].contains(intelligence.fileExtension ?? "")
    }

    func extract(from url: URL, intelligence: FileIntelligence) async throws -> [MetadataItem] {
        let ext = intelligence.fileExtension ?? ""
        let data = try Self.readPrefix(url, maximum: Self.maximumReadBytes)
        try Task.checkCancellation()
        if ["csv", "tsv", "tab"].contains(ext) { return Self.delimited(data, fileExtension: ext) }
        if ext == "bib" { return Self.bibtex(data) }
        guard Self.isWholeSmallFile(url, limit: Self.maximumReadBytes) else { return [] }
        if ext == "ipynb" { return Self.notebook(data) }
        if ["json", "jsonc", "json5"].contains(ext) { return Self.jsonShape(data) }
        return []
    }

    private static func delimited(_ data: Data, fileExtension: String) -> [MetadataItem] {
        guard let text = String(data: data, encoding: .utf8),
              let header = text.split(whereSeparator: \.isNewline).first else { return [] }
        let candidates: [(Character, String)] = fileExtension == "tsv" || fileExtension == "tab"
            ? [("\t", "Tab")] : [(",", "Comma"), ("\t", "Tab"), (";", "Semicolon"), ("|", "Pipe")]
        let selected = candidates.max { lhs, rhs in
            header.filter { $0 == lhs.0 }.count < header.filter { $0 == rhs.0 }.count
        } ?? (",", "Comma")
        let columns = header.split(separator: selected.0, omittingEmptySubsequences: false).count
        guard columns > 0 else { return [] }
        return [MetadataItem(key: .columns, value: "\(columns)", priority: 100), MetadataItem(key: .delimiter, value: selected.1, priority: 90)]
    }

    private static func jsonShape(_ data: Data) -> [MetadataItem] {
        guard let first = data.first(where: { !$0.isASCIIWhitespace }) else { return [] }
        let shape = first == 123 ? "Object" : first == 91 ? "Array" : nil
        return shape.map { [MetadataItem(key: .jsonShape, value: $0, priority: 100)] } ?? []
    }

    private static func notebook(_ data: Data) -> [MetadataItem] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = object["cells"] as? [[String: Any]] else { return [] }
        let code = cells.filter { ($0["cell_type"] as? String) == "code" }.count
        let markdown = cells.filter { ($0["cell_type"] as? String) == "markdown" }.count
        var result = [MetadataItem(key: .notebookCells, value: "\(cells.count)", priority: 100), MetadataItem(key: .codeCells, value: "\(code)", priority: 90), MetadataItem(key: .markdownCells, value: "\(markdown)", priority: 80)]
        if let kernelspec = object["metadata"] as? [String: Any], let kernel = kernelspec["kernelspec"] as? [String: Any], let name = kernel["display_name"] as? String { result.append(MetadataItem(key: .kernel, value: name, priority: 70)) }
        if let metadata = object["metadata"] as? [String: Any], let language = metadata["language_info"] as? [String: Any], let name = language["name"] as? String { result.append(MetadataItem(key: .language, value: name, priority: 60)) }
        return result
    }

    private static func bibtex(_ data: Data) -> [MetadataItem] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let count = text.split(whereSeparator: \.isNewline).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("@") }.count
        return count > 0 ? [MetadataItem(key: .references, value: "\(count)", priority: 100)] : []
    }

    private static func readPrefix(_ url: URL, maximum: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maximum) ?? Data()
    }

    private static func isWholeSmallFile(_ url: URL, limit: Int) -> Bool {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? limit + 1) <= limit
    }
}

private struct SpecializedHeaderMetadataExtractor: MetadataExtracting {
    private static let maxHeaderBytes = 1_048_576

    func supports(_ intelligence: FileIntelligence) -> Bool {
        ["npy", "npz", "safetensors"].contains(intelligence.fileExtension ?? "")
    }

    func extract(from url: URL, intelligence: FileIntelligence) async throws -> [MetadataItem] {
        try Task.checkCancellation()
        switch intelligence.fileExtension {
        case "npy": return try Self.numpy(url)
        case "npz": return try Self.npz(url)
        case "safetensors": return try Self.safeTensors(url)
        default: return []
        }
    }

    private static func numpy(_ url: URL) throws -> [MetadataItem] {
        let data = try readPrefix(url, maximum: maxHeaderBytes)
        guard data.count >= 10, data.prefix(6) == Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59]) else { return [] }
        let major = data[6]
        let start = major == 1 ? 10 : 12
        let length = major == 1 ? Int(UInt16(data[8]) | UInt16(data[9]) << 8) : Int(UInt32(data[8]) | UInt32(data[9]) << 8 | UInt32(data[10]) << 16 | UInt32(data[11]) << 24)
        guard length >= 0, start + length <= data.count, let header = String(data: data[start..<(start + length)], encoding: .ascii) else { return [] }
        let dtype = capture("'descr'\\s*:\\s*'([^']+)'", in: header)
        let rawShape = capture("'shape'\\s*:\\s*\\(([^)]*)\\)", in: header)
        var result: [MetadataItem] = []
        if let rawShape { let dimensions = rawShape.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }; if !dimensions.isEmpty { result.append(MetadataItem(key: .shape, value: dimensions.map(String.init).joined(separator: " × "), priority: 100)) } }
        if let dtype { result.append(MetadataItem(key: .dataType, value: dtype, priority: 90)) }
        return result
    }

    private static func safeTensors(_ url: URL) throws -> [MetadataItem] {
        let prefix = try readPrefix(url, maximum: 8)
        guard prefix.count == 8 else { return [] }
        let length = Int(prefix.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << UInt64($1.offset * 8)) })
        guard length > 0, length <= maxHeaderBytes else { return [] }
        let data = try readPrefix(url, maximum: 8 + length)
        guard data.count == 8 + length, let object = try? JSONSerialization.jsonObject(with: data.dropFirst(8)) as? [String: Any] else { return [] }
        let tensors = object.keys.filter { $0 != "__metadata__" }.count
        var result = [MetadataItem(key: .tensors, value: "\(tensors)", priority: 100)]
        if let metadata = object["__metadata__"] as? [String: Any] { result.append(MetadataItem(key: .metadataKeys, value: "\(metadata.count)", priority: 90)) }
        return result
    }

    private static func npz(_ url: URL) throws -> [MetadataItem] {
        let size = Int((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        guard size >= 22 else { return [] }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let count = min(size, 65_557); try handle.seek(toOffset: UInt64(size - count))
        let tail = try handle.read(upToCount: count) ?? Data()
        guard let marker = tail.range(of: Data([0x50, 0x4b, 0x05, 0x06])), marker.lowerBound + 12 <= tail.count else { return [] }
        let offset = marker.lowerBound + 10
        let arrays = Int(UInt16(tail[offset]) | UInt16(tail[offset + 1]) << 8)
        return [MetadataItem(key: .arrays, value: "\(arrays)", priority: 100)]
    }

    private static func readPrefix(_ url: URL, maximum: Int) throws -> Data { let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }; return try h.read(upToCount: maximum) ?? Data() }
    private static func capture(_ pattern: String, in text: String) -> String? { guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }; return String(text[range]) }
}

private extension UInt8 { var isASCIIWhitespace: Bool { self == 9 || self == 10 || self == 13 || self == 32 } }
