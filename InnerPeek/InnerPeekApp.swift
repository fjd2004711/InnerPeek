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
    private let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true

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
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "folder.fill.badge.checkmark")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 58, height: 58)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("InnerPeek")
                    .font(.title.bold())
                Text(text("Quick Look 扩展已安装，可以开始使用", "Quick Look extension installed and ready"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("1.0.1")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.orange)
                Text(text("建议开启：完全磁盘访问", "Recommended: Full Disk Access"))
                    .font(.headline)
                Text(text("可选", "Optional"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
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
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.orange.opacity(0.22), lineWidth: 1)
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
}
