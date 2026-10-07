import SwiftUI
import AppKit

/// App-wide language for the settings window itself (the preview has its own setting).
private let appIsChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
func appText(_ chinese: String, _ english: String) -> String { appIsChinese ? chinese : english }

struct SettingsView: View {
    var body: some View {
        TabView {
            DisplaySettingsView()
                .tabItem { Label(appText("显示", "Display"), systemImage: "rectangle.3.group") }
            AnalysisSettingsView()
                .tabItem { Label(appText("分析", "Analysis"), systemImage: "gauge.with.dots.needle.33percent") }
            AppearanceSettingsView()
                .tabItem { Label(appText("语言与外观", "Language & Look"), systemImage: "globe") }
            DiagnosticsSettingsView()
                .tabItem { Label(appText("诊断", "Diagnostics"), systemImage: "stethoscope") }
        }
        .frame(width: 560, height: 520)
    }
}

private struct SettingsPage<Content: View>: View {
    let note: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form { content }
                .formStyle(.grouped)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private let applyNote = appText("更改会在下次打开 Quick Look 预览时生效，无需重启。", "Changes apply the next time a Quick Look preview opens. No restart needed.")

// MARK: Display

private struct DisplaySettingsView: View {
    @AppStorage(PreviewSettings.Key.showSummary) private var showSummary = true
    @AppStorage(PreviewSettings.Key.showTechStack) private var showTechStack = true
    @AppStorage(PreviewSettings.Key.showInsights) private var showInsights = true
    @AppStorage(PreviewSettings.Key.showBrandIcons) private var showBrandIcons = true
    @AppStorage(PreviewSettings.Key.showHiddenFiles) private var showHiddenFiles = false
    @AppStorage(PreviewSettings.Key.expandReasons) private var expandReasons = false

    var body: some View {
        SettingsPage(note: applyNote) {
            Section(appText("预览内容", "Preview content")) {
                Toggle(appText("摘要（项目类型与仓库）", "Summary (project type and repository)"), isOn: $showSummary)
                Toggle(appText("技术栈", "Tech stack"), isOn: $showTechStack)
                    .disabled(!showSummary)
                Toggle(appText("洞察（缺失项与异常）", "Insights (gaps and anomalies)"), isOn: $showInsights)
                Toggle(appText("品牌图标", "Brand icons"), isOn: $showBrandIcons)
            }
            Section(appText("文件列表", "File list")) {
                Toggle(appText("显示隐藏文件", "Show hidden files"), isOn: $showHiddenFiles)
                Toggle(appText("默认展开“识别依据”", "Expand “why this conclusion” by default"), isOn: $expandReasons)
            }
            Section {
                Button(appText("恢复默认", "Restore Defaults")) {
                    showSummary = true; showTechStack = true; showInsights = true
                    showBrandIcons = true; showHiddenFiles = false; expandReasons = false
                }
            }
        }
    }
}

// MARK: Analysis

private struct AnalysisSettingsView: View {
    @AppStorage(PreviewSettings.Key.scanDepth) private var scanDepth = PreviewSettings.standard.scanDepth
    @AppStorage(PreviewSettings.Key.maximumEntries) private var maximumEntries = PreviewSettings.standard.maximumEntries

    var body: some View {
        SettingsPage(note: appText(
            "分析始终在本机完成且只读。范围越大，能发现越深层的项目与更完整的统计，但大文件夹的预览会更慢；超出范围时界面会标注“≥”或“部分”。",
            "Analysis always runs locally and read-only. A larger scope finds deeper projects and fuller statistics but makes big folders slower; results beyond the scope are marked “≥” or “partial”."
        )) {
            Section(appText("扫描范围", "Scan scope")) {
                Picker(appText("扫描深度", "Scan depth"), selection: $scanDepth) {
                    ForEach(Array(PreviewSettings.depthRange), id: \.self) { depth in
                        Text(depthLabel(depth)).tag(depth)
                    }
                }
                Picker(appText("最多分析项目数", "Maximum items analysed"), selection: $maximumEntries) {
                    ForEach(PreviewSettings.entryLimits, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section {
                Button(appText("恢复默认", "Restore Defaults")) {
                    scanDepth = PreviewSettings.standard.scanDepth
                    maximumEntries = PreviewSettings.standard.maximumEntries
                }
            }
        }
    }

    private func depthLabel(_ depth: Int) -> String {
        let base = appText("\(depth) 层", "\(depth) level" + (depth == 1 ? "" : "s"))
        return depth == PreviewSettings.standard.scanDepth ? base + appText("（默认）", " (default)") : base
    }
}

// MARK: Language and look

private struct AppearanceSettingsView: View {
    @AppStorage(PreviewSettings.Key.language) private var language = PreviewLanguage.system.rawValue
    @AppStorage(PreviewSettings.Key.iconStyle) private var iconStyle = PreviewIconStyle.brandColor.rawValue

    var body: some View {
        SettingsPage(note: applyNote) {
            Section(appText("预览语言", "Preview language")) {
                Picker(appText("语言", "Language"), selection: $language) {
                    Text(appText("跟随系统", "Follow system")).tag(PreviewLanguage.system.rawValue)
                    Text("简体中文").tag(PreviewLanguage.simplifiedChinese.rawValue)
                    Text("English").tag(PreviewLanguage.english.rawValue)
                }
                Text(appText("想要更多语言？欢迎在 GitHub 参与翻译，详见 docs/localization.md。",
                             "Want another language? Translations are welcome on GitHub; see docs/localization.md."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(appText("图标", "Icons")) {
                Picker(appText("图标样式", "Icon style"), selection: $iconStyle) {
                    Text(appText("品牌彩色", "Brand colour")).tag(PreviewIconStyle.brandColor.rawValue)
                    Text(appText("统一单色", "Single colour")).tag(PreviewIconStyle.monochrome.rawValue)
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Button(appText("恢复默认", "Restore Defaults")) {
                    language = PreviewLanguage.system.rawValue
                    iconStyle = PreviewIconStyle.brandColor.rawValue
                }
            }
        }
    }
}

// MARK: Diagnostics

private struct DiagnosticsSettingsView: View {
    @StateObject private var model = ExtensionStatusModel()
    @State private var confirmRepair = false
    @State private var copied = false
    @State private var fullDiskAccess = FullDiskAccess.isGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard
            if !model.log.isEmpty { logView }
            HStack(spacing: 10) {
                Button {
                    confirmRepair = true
                } label: {
                    Label(appText("修复 Quick Look…", "Repair Quick Look…"), systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                Button {
                    model.copyDiagnostics(fullDiskAccess: fullDiskAccess, settings: PreviewSettings.load())
                    copied = true
                } label: {
                    Label(copied ? appText("已复制", "Copied") : appText("复制诊断信息", "Copy Diagnostics"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label(appText("刷新", "Refresh"), systemImage: "arrow.clockwise")
                }
                Spacer()
            }
            Button(appText("打开“登录项与扩展”设置", "Open Login Items & Extensions settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link)
            Text(appText(
                "诊断信息不含任何文件内容，主目录会显示为 ~，可以安全地贴到 Issue 里。修复只会清理指向已不存在文件的旧记录，不会删除任何文件，也不会动你另外保留的副本。",
                "Diagnostics contain no file contents and show your home folder as ~, so they are safe to paste into an issue. Repair only removes records of files that no longer exist; it deletes no files and leaves any other copy you keep alone."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .task { await model.refresh() }
        .confirmationDialog(appText("修复 Quick Look", "Repair Quick Look"), isPresented: $confirmRepair, titleVisibility: .visible) {
            Button(appText("修复", "Repair")) { Task { await model.repair(restartFinder: false, language: appText) } }
            Button(appText("修复并重启 Finder", "Repair and Restart Finder")) { Task { await model.repair(restartFinder: true, language: appText) } }
            Button(appText("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(appText("将清理过期记录、重新注册并启用本扩展、重置 Quick Look 缓存。重启 Finder 会关闭当前的 Finder 窗口。",
                         "This removes stale records, re-registers and enables the extension, and resets Quick Look caches. Restarting Finder closes its open windows."))
        }
    }

    private var statusCard: some View {
        let status = describe(model.health)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.symbol).foregroundStyle(status.color).font(.title3)
                Text(model.loaded ? status.title : appText("正在检查…", "Checking…")).font(.headline)
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            Text(status.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.registrations.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.registrations.enumerated()), id: \.offset) { _, registration in
                        Text("\(registration.election.map(String.init) ?? " ")  \(registration.version)  \(abbreviate(registration.path))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(status.color.opacity(0.22), lineWidth: 1) }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                Text(abbreviate(line)).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func abbreviate(_ text: String) -> String { text.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    private func describe(_ health: ExtensionHealth) -> (symbol: String, color: Color, title: String, detail: String) {
        switch health {
        case .healthy:
            return ("checkmark.seal.fill", .green, appText("Quick Look 扩展正常", "Quick Look extension is healthy"),
                    appText("已在当前位置注册并启用，没有过期记录。", "Registered and enabled at its current location, with no stale records."))
        case .notRegistered:
            return ("exclamationmark.triangle.fill", .orange, appText("扩展尚未注册", "Extension is not registered"),
                    appText("按空格时 Finder 可能显示系统默认卡片。点击“修复 Quick Look”来注册。", "Finder may show its default card on Space. Choose “Repair Quick Look” to register it."))
        case .registeredElsewhere:
            return ("arrow.triangle.branch", .orange, appText("已注册在其他位置", "Registered at another location"),
                    appText("系统当前使用的是另一份 InnerPeek 的扩展，而不是正在运行的这一份。点击“修复 Quick Look”改为注册这一份，或保留现状。",
                            "The system is using the extension of a different InnerPeek copy, not the one running now. Choose “Repair Quick Look” to register this one instead, or leave it."))
        case .disabled:
            return ("pause.circle.fill", .orange, appText("扩展已被关闭", "Extension is switched off"),
                    appText("请在“登录项与扩展”设置里打开 InnerPeek 的 Quick Look 扩展，或点击“修复 Quick Look”。", "Switch InnerPeek's Quick Look extension on in Login Items & Extensions, or choose “Repair Quick Look”."))
        case let .needsCleanup(stale, copies):
            var parts: [String] = []
            if stale > 0 { parts.append(appText("\(stale) 条指向已删除文件的过期记录", "\(stale) stale record(s) for deleted files")) }
            if copies > 0 { parts.append(appText("另有 \(copies) 份副本也已注册", "\(copies) other copy/copies also registered")) }
            return ("wrench.and.screwdriver.fill", .orange, appText("建议清理", "Cleanup recommended"),
                    parts.joined(separator: appText("；", "; ")) + appText("。过期记录可能让 Finder 回退到默认卡片。", ". Stale records can make Finder fall back to its default card."))
        }
    }
}
