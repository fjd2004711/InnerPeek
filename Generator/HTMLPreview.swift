import Foundation

/// C entry point used by main.c. Renders an on-disk folder as a self-contained
/// HTML document using the same bounded analysis pipeline as the App Extension.
/// Takes a CFURLRef and returns a +1 retained CFDataRef (as a raw pointer), or nil to let Quick Look fall back.
@_cdecl("ip_render_preview")
public func ip_render_preview(_ rawURL: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let url = Unmanaged<CFURL>.fromOpaque(rawURL).takeUnretainedValue() as URL
    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    guard isDirectory else { return nil }
    guard let analysis = try? FolderAnalyzer().analyze(folderURL: url) else { return nil }
    let html = FolderHTMLRenderer(folderName: url.lastPathComponent, analysis: analysis).render()
    return Unmanaged.passRetained(Data(html.utf8) as CFData).toOpaque()
}

struct FolderHTMLRenderer {
    /// Upper bound on rendered tree rows; keeps HTML small and WebKit layout fast.
    static let maximumTreeRows = 400
    static let maximumCategoryRows = 6

    let folderName: String
    let analysis: FolderAnalysis
    private let isChinese: Bool
    private let locale = Locale.current

    init(folderName: String, analysis: FolderAnalysis) {
        self.folderName = folderName
        self.analysis = analysis
        let language = Locale.preferredLanguages.first ?? "en"
        self.isChinese = language.hasPrefix("zh")
    }

    func render() -> String {
        let relationships = RelationshipEngine().detect(in: analysis)
        let importantFiles = ImportantFileDetector().detect(in: analysis)
        let insights = InsightEngine().generate(for: analysis, relationships: relationships, importantFiles: importantFiles)
        let decision = SemanticVerdictEngine().decide(
            analysis: analysis, relationships: relationships,
            insights: insights, importantFiles: importantFiles
        )
        let quiet = decision.verdict == nil && decision.insights.isEmpty && decision.evidence.isEmpty

        var body = header()
        if let verdict = decision.verdict {
            body += section(verdictRows(verdict: verdict, repository: decision.repositoryContext))
        }
        if !decision.insights.isEmpty {
            body += section(decision.insights.map(insightRow).joined(), title: t("Insights", "洞察"))
        }
        if !decision.evidence.isEmpty {
            body += section(evidenceRows(decision.evidence), title: t("Evidence", "依据"))
        }
        if quiet {
            body += section(categoryRows(), title: t("What's inside", "内容概览"))
        }
        body += section(tree(), title: t("Browse", "浏览"))
        return page(body)
    }

    // MARK: Sections

    private func header() -> String {
        let summary = String(
            format: t("%ld files · %ld folders · %@ analyzed", "%ld 个文件 · %ld 个文件夹 · 已分析 %@"),
            analysis.analyzedFileCount, analysis.analyzedDirectoryCount,
            Self.byteCount(analysis.totalKnownFileSize)
        ) + (analysis.scanState.isPartial ? t(" (partial)", "（部分）") : "")
        return """
        <header><div class="folder-icon">\(Self.folderSVG)</div>
        <div><h1>\(esc(folderName))</h1><p class="sub">\(esc(summary))</p></div></header>
        """
    }

    private func section(_ rows: String, title: String? = nil) -> String {
        guard !rows.isEmpty else { return "" }
        let heading = title.map { "<h2>\(esc($0))</h2>" } ?? ""
        return "<section>\(heading)\(rows)</section>"
    }

    private func verdictRows(verdict: SemanticVerdict, repository: GitRepositoryContext?) -> String {
        var html = row(symbol: verdict.status == .warning ? "warn" : verdict.status == .complete ? "ok" : "info",
                       title: verdict.localizedTitle(for: locale), detail: verdict.localizedSummary(for: locale))
        if let repository {
            html += row(symbol: "info", title: repository.title.value(for: locale),
                        detail: repository.summary.value(for: locale))
        }
        return html
    }

    private func insightRow(_ insight: Insight) -> String {
        let symbol: String
        switch insight.severity {
        case .warning: symbol = "warn"
        case .positive: symbol = "ok"
        case .notice, .info: symbol = "info"
        }
        return row(symbol: symbol, title: insight.localizedTitle(for: locale),
                   detail: insight.localizedDetail(for: locale) ?? "")
    }

    private func row(symbol: String, title: String, detail: String) -> String {
        """
        <div class="row \(symbol)"><span class="dot"></span><div><div class="t">\(esc(title))</div>\
        \(detail.isEmpty ? "" : "<div class=\"d\">\(esc(detail))</div>")</div></div>
        """
    }

    private func evidenceRows(_ evidence: [SemanticEvidence]) -> String {
        let visible = evidence.prefix(PreviewLimits.maximumEvidence)
        var html = visible.map { item in
            """
            <div class="ev"><code>\(esc((item.relativePath as NSString).lastPathComponent))</code>\
            <span>\(esc(item.localizedReason(for: locale)))</span></div>
            """
        }.joined()
        let remaining = evidence.count - visible.count
        if remaining > 0 {
            html += "<div class=\"more\">" + esc(String(format: t("+ %ld more", "另有 %ld 项"), remaining)) + "</div>"
        }
        return html
    }

    private func categoryRows() -> String {
        let stats = analysis.categoryStatistics
        let maxSize = max(stats.map(\.totalKnownSize).max() ?? 1, 1)
        return stats.prefix(Self.maximumCategoryRows).map { stat in
            let width = max(2, Int(Double(stat.totalKnownSize) / Double(maxSize) * 100))
            return """
            <div class="cat"><span class="n">\(esc(categoryName(stat.category)))</span>\
            <span class="bar"><i style="width:\(width)%"></i></span>\
            <span class="m">\(stat.fileCount) · \(esc(Self.byteCount(stat.totalKnownSize)))</span></div>
            """
        }.joined()
    }

    // MARK: Tree

    private final class Node {
        let name: String
        var isDirectory: Bool
        var size: Int64?
        var children: [String: Node] = [:]
        init(name: String, isDirectory: Bool) { self.name = name; self.isDirectory = isDirectory }
    }

    private func tree() -> String {
        let sizes = Dictionary(analysis.analyzedFiles.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        let root = Node(name: "", isDirectory: true)
        for entry in analysis.analyzedEntries {
            var node = root
            let parts = entry.relativePath.split(separator: "/").map(String.init)
            for (index, part) in parts.enumerated() {
                let last = index == parts.count - 1
                let child = node.children[part] ?? Node(name: part, isDirectory: !last || entry.isDirectory)
                node.children[part] = child
                node = child
            }
            if !entry.isDirectory { node.size = sizes[entry.url] }
        }
        var budget = Self.maximumTreeRows
        var truncated = false
        func render(_ node: Node) -> String {
            let ordered = node.children.values.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            var html = ""
            for child in ordered {
                guard budget > 0 else { truncated = true; break }
                budget -= 1
                if child.isDirectory {
                    let inner = render(child)
                    html += "<details><summary>\(Self.folderSVG)\(esc(child.name))</summary>\(inner)</details>"
                } else {
                    let size = child.size.map { Self.byteCount($0) } ?? ""
                    html += "<div class=\"f\">\(Self.fileSVG)<span class=\"fn\">\(esc(child.name))</span><span class=\"m\">\(esc(size))</span></div>"
                }
            }
            return html
        }
        var html = "<div class=\"tree\">" + render(root) + "</div>"
        if truncated || analysis.scanState.isPartial {
            html += "<div class=\"more\">" + esc(t("Showing a bounded portion of this folder.", "仅显示文件夹的一部分内容。")) + "</div>"
        }
        return html
    }

    // MARK: Helpers

    private enum PreviewLimits { static let maximumEvidence = 5 }

    private func t(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }

    private func categoryName(_ category: FileCategory) -> String {
        switch category {
        case .document: return t("Documents", "文档")
        case .spreadsheet: return t("Spreadsheets", "表格")
        case .image: return t("Images", "图片")
        case .rawImage: return t("RAW Images", "RAW 图片")
        case .audio: return t("Audio", "音频")
        case .video: return t("Videos", "视频")
        case .archive: return t("Archives", "压缩包")
        case .sourceCode: return t("Source Code", "源代码")
        case .configuration: return t("Configuration", "配置")
        case .database: return t("Databases", "数据库")
        case .scientificData: return t("Scientific Data", "科学数据")
        case .aiModel: return t("AI Models", "AI 模型")
        case .threeD: return t("3D & CAD", "3D 与 CAD")
        case .font: return t("Fonts", "字体")
        case .executable: return t("Executables", "可执行文件")
        case .project: return t("Projects", "项目")
        case .unknown: return t("Other", "其他")
        }
    }

    private static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func esc(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static let folderSVG = "<svg class=\"ic\" viewBox=\"0 0 16 16\"><path fill=\"currentColor\" d=\"M1.5 3.5A1.5 1.5 0 0 1 3 2h3l1.5 1.5H13A1.5 1.5 0 0 1 14.5 5v7A1.5 1.5 0 0 1 13 13.5H3A1.5 1.5 0 0 1 1.5 12z\"/></svg>"
    private static let fileSVG = "<svg class=\"ic file\" viewBox=\"0 0 16 16\"><path fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.2\" d=\"M4 1.8h5l3 3V14H4z M9 1.8v3h3\"/></svg>"

    private func page(_ body: String) -> String {
        """
        <!doctype html><html lang="\(isChinese ? "zh-Hans" : "en")"><head><meta charset="utf-8">\
        <meta name="color-scheme" content="light dark"><style>\(Self.css)</style></head><body>\(body)</body></html>
        """
    }

    private static let css = """
    :root{color-scheme:light dark;--fg:#1d1d1f;--sub:#6e6e73;--line:rgba(0,0,0,.08);--chip:rgba(0,0,0,.05);--ok:#1f9d55;--warn:#d97706;--info:#6e6e73;--acc:#0a84ff}
    @media(prefers-color-scheme:dark){:root{--fg:#f5f5f7;--sub:#98989d;--line:rgba(255,255,255,.1);--chip:rgba(255,255,255,.07);--info:#98989d}}
    *{box-sizing:border-box}
    body{margin:0;padding:18px 22px 24px;font:13px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;color:var(--fg);background:transparent;-webkit-font-smoothing:antialiased}
    header{display:flex;align-items:center;gap:12px;padding-bottom:12px;border-bottom:1px solid var(--line)}
    .folder-icon{width:34px;height:34px;color:var(--acc)}.folder-icon svg{width:100%;height:100%}
    h1{margin:0;font-size:17px;font-weight:600;word-break:break-all}.sub{margin:2px 0 0;color:var(--sub);font-size:12px}
    section{padding:12px 0;border-bottom:1px solid var(--line)}section:last-child{border-bottom:0}
    h2{margin:0 0 6px;font-size:11px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:var(--sub)}
    .row{display:flex;gap:9px;padding:3px 0}.dot{flex:none;width:8px;height:8px;margin-top:5px;border-radius:50%;background:var(--info)}
    .row.ok .dot{background:var(--ok)}.row.warn .dot{background:var(--warn)}
    .t{font-weight:500}.d{color:var(--sub);font-size:12px}
    .ev{display:flex;gap:8px;align-items:baseline;padding:2px 0}.ev code{font:12px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--chip);padding:1px 6px;border-radius:5px}.ev span{color:var(--sub);font-size:12px}
    .more{color:var(--sub);font-size:12px;padding:4px 0}
    .cat{display:flex;align-items:center;gap:10px;padding:3px 0}.cat .n{width:96px}.cat .bar{flex:1;height:5px;border-radius:3px;background:var(--chip);overflow:hidden}.cat .bar i{display:block;height:100%;background:var(--acc);border-radius:3px}.cat .m{width:110px;text-align:right;color:var(--sub);font-size:12px;font-variant-numeric:tabular-nums}
    .tree details{margin-left:0}.tree details>details,.tree details>.f{margin-left:16px}
    summary{list-style:none;cursor:default;padding:2px 0;display:flex;align-items:center;gap:6px}summary::-webkit-details-marker{display:none}
    summary::before{content:"\\25B8";color:var(--sub);font-size:10px;width:10px;transition:transform .1s}details[open]>summary::before{transform:rotate(90deg)}
    .ic{width:15px;height:15px;flex:none;color:var(--acc)}.ic.file{color:var(--sub)}
    .f{display:flex;align-items:center;gap:6px;padding:2px 0 2px 16px}.fn{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .f .m{color:var(--sub);font-size:12px;font-variant-numeric:tabular-nums}
    """
}
