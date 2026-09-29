import SwiftUI
import AppKit

@main
struct InnerPeekApp: App {
    var body: some Scene {
        WindowGroup {
            SetupGuideView()
        }
        .windowResizability(.contentSize)
    }
}

private struct SetupGuideView: View {
    private static let permissionConfirmationKey = "fullDiskAccessConfirmed"
    private let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionGranted = UserDefaults.standard.bool(forKey: permissionConfirmationKey)
    @State private var permissionChecked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Label(text("使用方法", "How to use"), systemImage: "space")
                    .font(.headline)
                step(1, text("在 Finder 中选中文件夹或 ZIP 压缩包。", "Select a folder or ZIP archive in Finder."))
                step(2, text("按下空格键打开预览；再次按空格键关闭。", "Press Space to preview; press Space again to close."))
                step(3, text("单击文件夹整行即可展开或收起。", "Click anywhere on a folder row to expand or collapse it."))
            }
            permissionCard
            HStack(spacing: 12) {
                Button(text("打开完全磁盘访问设置", "Open Full Disk Access Settings")) {
                    openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(text("在 Finder 中显示 InnerPeek", "Show InnerPeek in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .controlSize(.large)
                Button {
                    checkFullDiskAccess()
                } label: {
                    Label(text("重新检查", "Check Again"), systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                Button {
                    confirmFullDiskAccess()
                } label: {
                    Label(text("我已开启", "I Enabled It"), systemImage: "checkmark.circle")
                }
                .controlSize(.large)
                Spacer()
            }
            Text(text(
                "InnerPeek 不会后台驻留，也不会上传或修改你的文件。权限仅用于读取你主动预览的内容。",
                "InnerPeek does not stay running in the background, upload files, or modify them. Access is used only to read content you choose to preview."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            checkFullDiskAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkFullDiskAccess() }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("InnerPeek")
                    .font(.title.bold())
                Text(text("Quick Look 扩展已安装，可以开始使用", "Quick Look extension installed and ready"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openGitHub()
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help(text("访问 GitHub 项目", "Open GitHub project"))
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: permissionGranted ? "checkmark.shield.fill" : "lock.shield.fill")
                    .foregroundStyle(permissionGranted ? .green : .orange)
                Text(permissionGranted
                     ? text("完全磁盘访问：已获取", "Full Disk Access: Granted")
                     : text("建议开启：完全磁盘访问", "Recommended: Full Disk Access"))
                    .font(.headline)
                Text(permissionGranted ? text("正常", "Ready") : text("可选", "Optional"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(permissionGranted ? .green : .secondary)
                    .background((permissionGranted ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            }
            Text(text(
                "普通文件夹无需额外授权。若要预览桌面、文稿、下载、邮件资料或其他受 macOS 保护的位置，请为 InnerPeek 开启完全磁盘访问。macOS 要求用户亲自在系统设置中授权，应用不能静默获取。",
                "Regular folders need no extra permission. To preview Desktop, Documents, Downloads, Mail data, or other macOS-protected locations, grant InnerPeek Full Disk Access. macOS requires you to approve this manually in System Settings."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(text(
                "步骤：打开设置 → 点击“+” → 选择 /Applications/InnerPeek.app → 打开开关 → 重新打开 Finder 预览。",
                "Steps: Open Settings → click “+” → choose /Applications/InnerPeek.app → enable it → reopen the Finder preview."
            ))
            .font(.callout.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            if permissionChecked && !permissionGranted {
                Text(text(
                    "尚未检测到授权。沙盒扩展有时不会向应用暴露 TCC 状态；确认系统设置中的开关已打开后，点击“我已开启”。",
                    "Access was not detected. macOS may hide TCC state from a sandboxed extension; after confirming the switch is on, click “I Enabled It”."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background((permissionGranted ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke((permissionGranted ? Color.green : Color.orange).opacity(0.22), lineWidth: 1)
        }
    }

    private func step(_ number: Int, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.blue, in: Circle())
            Text(title)
                .font(.callout)
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    private func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]
        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func checkFullDiskAccess() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedLocations = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Messages")
        ]
        let canReadProtectedLocation = protectedLocations.contains {
            FileManager.default.isReadableFile(atPath: $0.path)
        }
        permissionGranted = canReadProtectedLocation || UserDefaults.standard.bool(forKey: Self.permissionConfirmationKey)
        permissionChecked = true
    }

    private func confirmFullDiskAccess() {
        UserDefaults.standard.set(true, forKey: Self.permissionConfirmationKey)
        permissionGranted = true
        permissionChecked = true
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/fjd2004711/InnerPeek") else { return }
        NSWorkspace.shared.open(url)
    }
}
