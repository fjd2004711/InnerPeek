import Foundation
import ImageIO
import AVFoundation
import PDFKit
import Security
import CoreText

/// Dispatches bounded, read-only file metadata extraction. Extractors are
/// ordered only as a deterministic fallback; a file is handled by one format
/// specialist, never by a chain of increasingly expensive probes.
struct MetadataExtractorRegistry: Sendable {
    private let extractors: [any MetadataExtracting]

    init(extractors: [any MetadataExtracting] = [
        NativeMediaMetadataExtractor(),
        StructuredTextMetadataExtractor(),
        DocumentFormatMetadataExtractor(),
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
        return [MetadataItem(key: .columns, value: "\(columns)", priority: 100), MetadataItem(key: .delimiter, value: MessageCatalog.shared.string(selected.1), priority: 90)]
    }

    private static func jsonShape(_ data: Data) -> [MetadataItem] {
        guard let first = data.first(where: { !$0.isASCIIWhitespace }) else { return [] }
        let shape = first == 123 ? "Object" : first == 91 ? "Array" : nil
        return shape.map { [MetadataItem(key: .jsonShape, value: MessageCatalog.shared.string($0), priority: 100)] } ?? []
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

/// Subtitles, mail, calendar and contact files, JSON Lines, certificates and fonts.
/// Reads at most 256 KB, never displays key material, and reports only what the
/// file itself states (counts, header fields, certificate subject and expiry).
private struct DocumentFormatMetadataExtractor: MetadataExtracting {
    static let maximumReadBytes = 256 * 1024
    private static let handled: Set<String> = [
        "srt", "vtt", "ass", "ssa", "eml", "emlx", "ics", "vcf", "jsonl", "ndjson",
        "pem", "crt", "cer", "der", "ttf", "otf", "ttc"
    ]

    func supports(_ intelligence: FileIntelligence) -> Bool { Self.handled.contains(intelligence.fileExtension ?? "") }

    func extract(from url: URL, intelligence: FileIntelligence) async throws -> [MetadataItem] {
        try Task.checkCancellation()
        let ext = intelligence.fileExtension ?? ""
        if ["ttf", "otf", "ttc"].contains(ext) { return Self.font(url) }
        let (data, truncated) = try Self.readPrefix(url)
        try Task.checkCancellation()
        switch ext {
        case "srt", "vtt", "ass", "ssa": return Self.subtitles(data, fileExtension: ext, truncated: truncated)
        case "eml", "emlx": return Self.email(data)
        case "ics", "vcf": return Self.calendarOrContacts(data, fileExtension: ext, truncated: truncated)
        case "jsonl", "ndjson": return Self.jsonLines(data, truncated: truncated)
        default: return Self.certificate(data)
        }
    }

    // MARK: Subtitles

    static func subtitles(_ data: Data, fileExtension: String, truncated: Bool) -> [MetadataItem] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        var cues = 0
        var lastEnd: TimeInterval?
        for line in text.split(whereSeparator: \.isNewline) {
            if fileExtension == "ass" || fileExtension == "ssa" {
                guard line.hasPrefix("Dialogue:") else { continue }
                cues += 1
                let fields = line.dropFirst(9).split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
                if fields.count > 2 { lastEnd = clock(String(fields[2])) ?? lastEnd }
            } else if let arrow = line.range(of: "-->") {
                cues += 1
                let end = line[arrow.upperBound...].split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                lastEnd = clock(end) ?? lastEnd
            }
        }
        guard cues > 0 else { return [] }
        var items = [MetadataItem(key: .cues, value: (truncated ? "≥ " : "") + "\(cues)", priority: 100)]
        if let lastEnd, !truncated, let formatted = durationFormatter.string(from: lastEnd) {
            items.append(MetadataItem(key: .duration, value: formatted, priority: 90))
        }
        return items
    }

    /// "01:02:03,500", "02:03.500" or "0:02:03.50" to seconds.
    static func clock(_ value: String) -> TimeInterval? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts { guard let number = Double(part) else { return nil }; seconds = seconds * 60 + number }
        return seconds
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    // MARK: Email

    static func email(_ data: Data) -> [MetadataItem] {
        var text = String(decoding: data, as: UTF8.self)
        // Apple Mail's .emlx starts with the message length on its own line.
        if let firstBreak = text.firstIndex(where: \.isNewline), text[..<firstBreak].allSatisfy(\.isNumber), !text[..<firstBreak].isEmpty {
            text = String(text[text.index(after: firstBreak)...])
        }
        let headerEnd = text.range(of: "\r\n\r\n")?.lowerBound ?? text.range(of: "\n\n")?.lowerBound ?? text.endIndex
        var headers: [String: String] = [:]
        var current: String?
        for rawLine in text[..<headerEnd].split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).prefix(200) {
            let line = String(rawLine)
            if line.first == " " || line.first == "\t", let key = current {
                headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].lowercased()
                current = key
                if headers[key] == nil { headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
            }
        }
        var items: [MetadataItem] = []
        if let subject = headers["subject"], !subject.isEmpty { items.append(MetadataItem(key: .subject, value: decodeWords(subject), priority: 100)) }
        if let from = headers["from"], !from.isEmpty { items.append(MetadataItem(key: .sender, value: decodeWords(from), priority: 90)) }
        if let date = headers["date"], !date.isEmpty { items.append(MetadataItem(key: .sentDate, value: formatMailDate(date), priority: 80)) }
        return items
    }

    /// RFC 2047 encoded words (`=?UTF-8?B?...?=` and `=?...?Q?...?=`).
    static func decodeWords(_ value: String) -> String {
        guard value.contains("=?"), let regex = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=") else { return value }
        var result = ""
        var cursor = value.startIndex
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let whole = Range(match.range, in: value), let charset = Range(match.range(at: 1), in: value),
                  let method = Range(match.range(at: 2), in: value), let payload = Range(match.range(at: 3), in: value) else { continue }
            let between = value[cursor..<whole.lowerBound]
            if !between.allSatisfy(\.isWhitespace) || result.isEmpty { result += between }
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(String(value[charset]) as CFString)
            let encoding = cfEncoding == kCFStringEncodingInvalidId ? String.Encoding.utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            var bytes = Data()
            if value[method].lowercased() == "b" {
                bytes = Data(base64Encoded: String(value[payload])) ?? Data()
            } else {
                let q = Array(value[payload].utf8)
                var index = 0
                while index < q.count {
                    if q[index] == 0x5F { bytes.append(0x20); index += 1 }
                    else if q[index] == 0x3D, index + 2 < q.count + 0, let byte = UInt8(String(decoding: q[(index + 1)...min(index + 2, q.count - 1)], as: UTF8.self), radix: 16) { bytes.append(byte); index += 3 }
                    else { bytes.append(q[index]); index += 1 }
                }
            }
            result += String(data: bytes, encoding: encoding) ?? String(value[whole])
            cursor = whole.upperBound
        }
        return result + value[cursor...]
    }

    private static func formatMailDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        let cleaned = raw.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            parser.dateFormat = format
            if let date = parser.date(from: cleaned) {
                let display = DateFormatter()
                display.dateStyle = .medium
                display.timeStyle = .short
                return display.string(from: date)
            }
        }
        return String(raw.prefix(48))
    }

    // MARK: Calendar and contacts

    static func calendarOrContacts(_ data: Data, fileExtension: String, truncated: Bool) -> [MetadataItem] {
        let text = String(decoding: data, as: UTF8.self)
        // Unfold continuation lines (RFC 5545 / 6350).
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\n ", with: "")
        let lines = unfolded.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let bound = truncated ? "≥ " : ""
        if fileExtension == "vcf" {
            let count = lines.filter { $0.uppercased() == "BEGIN:VCARD" }.count
            guard count > 0 else { return [] }
            var items = [MetadataItem(key: .contacts, value: bound + "\(count)", priority: 100)]
            if let name = lines.first(where: { $0.uppercased().hasPrefix("FN") && $0.contains(":") }).flatMap({ $0.split(separator: ":", maxSplits: 1).last.map(String.init) }), !name.isEmpty {
                items.append(MetadataItem(key: .title, value: name, priority: 90))
            }
            return items
        }
        let count = lines.filter { $0.uppercased() == "BEGIN:VEVENT" }.count
        guard count > 0 else { return [] }
        var items = [MetadataItem(key: .events, value: bound + "\(count)", priority: 100)]
        if let summary = lines.first(where: { $0.uppercased().hasPrefix("SUMMARY") && $0.contains(":") }).flatMap({ $0.split(separator: ":", maxSplits: 1).last.map(String.init) }), !summary.isEmpty {
            items.append(MetadataItem(key: .title, value: summary, priority: 90))
        }
        return items
    }

    // MARK: JSON Lines

    static func jsonLines(_ data: Data, truncated: Bool) -> [MetadataItem] {
        let count = data.split(separator: 0x0A).filter { !$0.allSatisfy { $0 == 0x20 || $0 == 0x0D || $0 == 0x09 } }.count
        guard count > 0 else { return [] }
        // A cut-off last line is not a record, so a truncated read reports a lower bound.
        return [MetadataItem(key: .records, value: truncated ? "≥ \(max(count - 1, 1))" : "\(count)", priority: 100)]
    }

    // MARK: Certificates

    /// Names block types only. The encoded body of a key is never decoded or shown.
    static func certificate(_ data: Data) -> [MetadataItem] {
        let text = String(decoding: data, as: UTF8.self)
        var items: [MetadataItem] = []
        var firstCertificate: Data?
        if text.contains("-----BEGIN"), let regex = try? NSRegularExpression(pattern: "-----BEGIN ([A-Z0-9 ]+)-----") {
            var counts: [(label: String, count: Int)] = []
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let label = describe(blockType: String(text[range]))
                if let index = counts.firstIndex(where: { $0.label == label }) { counts[index].count += 1 } else { counts.append((label, 1)) }
                if firstCertificate == nil, text[range] == "CERTIFICATE", let whole = Range(match.range, in: text),
                   let end = text.range(of: "-----END CERTIFICATE-----", range: whole.upperBound..<text.endIndex) {
                    let body = text[whole.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
                    firstCertificate = Data(base64Encoded: String(body))
                }
            }
            if !counts.isEmpty {
                items.append(MetadataItem(key: .contains, value: counts.map { $0.count > 1 ? "\($0.label) × \($0.count)" : $0.label }.joined(separator: ", "), priority: 100))
            }
        } else if data.first == 0x30 {
            firstCertificate = data
        }
        if let der = firstCertificate, let certificate = SecCertificateCreateWithData(nil, der as CFData) {
            if let subject = SecCertificateCopySubjectSummary(certificate) as String? { items.append(MetadataItem(key: .certificateSubject, value: subject, priority: 95)) }
            if let expiry = notAfter(of: certificate) {
                let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .none
                let label = formatter.string(from: expiry)
                items.append(MetadataItem(key: .expires, value: expiry < Date() ? label + catalog(" (expired)") : label, priority: 90))
            }
        }
        return items
    }

    private static func catalog(_ english: String) -> String { MessageCatalog.shared.string(english) }

    private static func describe(blockType: String) -> String {
        switch blockType {
        case "CERTIFICATE", "TRUSTED CERTIFICATE": return catalog("Certificate")
        case "CERTIFICATE REQUEST", "NEW CERTIFICATE REQUEST": return catalog("Certificate request")
        case "PUBLIC KEY", "RSA PUBLIC KEY": return catalog("Public key")
        case "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "ENCRYPTED PRIVATE KEY", "DSA PRIVATE KEY", "OPENSSH PRIVATE KEY":
            return catalog("Private key (not shown)")
        default: return blockType.capitalized
        }
    }

    private static func notAfter(of certificate: SecCertificate) -> Date? {
        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [CFString: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let number = entry[kSecPropertyKeyValue] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: number.doubleValue)
    }

    // MARK: Fonts

    static func font(_ url: URL) -> [MetadataItem] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String else { return [] }
        let style = CTFontDescriptorCopyAttribute(first, kCTFontStyleNameAttribute) as? String
        let styles = descriptors.count > 1 ? " · \(descriptors.count)" : (style.map { " · \($0)" } ?? "")
        return [MetadataItem(key: .fontFamily, value: family + styles, priority: 100)]
    }

    private static func readPrefix(_ url: URL) throws -> (Data, Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumReadBytes) ?? Data()
        return (data, data.count >= maximumReadBytes)
    }
}

private extension UInt8 { var isASCIIWhitespace: Bool { self == 9 || self == 10 || self == 13 || self == 32 } }
