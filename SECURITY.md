# Security Policy / 安全策略

## English

InnerPeek opens folders and ZIP files you choose to preview, so it treats their contents as untrusted.

### Reporting a vulnerability

Please report it **privately**: open the repository's **Security** tab and choose **Report a vulnerability**
(GitHub private vulnerability reporting). Do not open a public issue for a security problem. Include
the macOS and InnerPeek versions, steps to reproduce and, if possible, a small sample (a crafted ZIP
or folder listing is fine; do not send private data).

You should get an acknowledgement within a few days. This is a volunteer project, so fixes follow as
time allows; coordinated disclosure is appreciated.

### What counts

- Escaping or weakening the App Sandbox; reading anything beyond the previewed item.
- Writing to, moving or deleting user files (InnerPeek must be read-only).
- Credentials, tokens or file contents leaking into the UI, logs, diagnostics or the clipboard.
- Crashes or unbounded CPU, memory or disk use triggered by a crafted ZIP (for example a huge or
  malformed central directory, path traversal in entry names) or a pathological folder.
- Network access of any kind (there should be none).

### Design notes useful to reviewers

- The Quick Look extension is sandboxed with user-selected read-only access.
- It declares one sandbox exception, `com.apple.security.temporary-exception.shared-preference.read-only`
  for `com.innerpeek.InnerPeek`, so it can read its own settings. Values are validated and clamped.
- The settings app is not sandboxed because the repair tool runs `pluginkit`, `lsregister`, `qlmanage`
  and `killall`. It acts only on InnerPeek's own registrations and asks for confirmation before running.
- ZIP files are never extracted; only the central directory is read. Folder analysis is bounded in depth,
  entry count and bytes read, and does not follow symlinks.
- Risk findings are paths only. Private-key and token checks read at most 4 KB of a file, never store
  or display it.

### Supported versions

Only the latest release receives fixes.

---

## 中文

InnerPeek 会打开你选择预览的文件夹和 ZIP，因此把它们的内容视为不可信输入。

### 报告漏洞

请**私下**报告：打开仓库的 **Security** 标签页，选择 **Report a vulnerability**（GitHub 私密漏洞报告）。
请不要为安全问题公开提 Issue。内容请包含 macOS 和 InnerPeek 版本、复现步骤，如有可能附上一个小样本
（构造的 ZIP 或目录结构即可，不要发送私人数据）。

通常会在几天内确认收到。这是志愿维护的项目，修复会按时间安排，感谢协调披露。

### 哪些算安全问题

- 逃出或削弱 App Sandbox；读取了被预览项目之外的内容。
- 写入、移动或删除用户文件（InnerPeek 必须是只读的）。
- 凭据、令牌或文件内容泄露到界面、日志、诊断信息或剪贴板。
- 精心构造的 ZIP（例如巨大或畸形的 central directory、条目名里的路径穿越）或异常的文件夹导致崩溃，
  或 CPU、内存、磁盘无界增长。
- 任何形式的网络访问（应当没有）。

### 供审阅者参考的设计说明

- Quick Look 扩展在沙盒中运行，仅有用户选择项目的只读权限。
- 它声明了一个沙盒例外 `com.apple.security.temporary-exception.shared-preference.read-only`，
  只用于读取 `com.innerpeek.InnerPeek` 的设置，读取的值会被校验并限制范围。
- 设置应用没有沙盒，因为修复工具要运行 `pluginkit`、`lsregister`、`qlmanage` 和 `killall`。它只处理 InnerPeek
  自己的注册记录，并在执行前请求确认。
- ZIP 从不解压，只读取 central directory。文件夹分析在深度、条目数和读取字节上都有上限，不跟随符号链接。
- 隐患结果只有路径。私钥和令牌检测最多读取文件开头 4 KB，不保存也不显示。

### 支持的版本

只有最新版本会得到修复。
