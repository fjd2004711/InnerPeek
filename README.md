<p align="center">
  <img src="InnerPeek/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="104" alt="InnerPeek logo">
</p>

<h1 align="center">InnerPeek</h1>

<p align="center"><strong>让 Finder 的空格预览，真正看懂文件夹和 ZIP 压缩包。</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-Apple%20Silicon%20%7C%20Intel-151515?logo=apple&logoColor=white" alt="macOS Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/Quick%20Look-native-24C8DB" alt="Quick Look native extension">
  <img src="https://img.shields.io/badge/ZIP-zero%20extraction-4C8DFF" alt="ZIP zero extraction">
  <img src="https://img.shields.io/badge/License-MIT-60B932" alt="MIT license">
</p>

InnerPeek 是一个本地运行的 macOS Quick Look 扩展。它不改变 Finder 的工作方式，只把你按下空格后看到的文件夹或 ZIP，从一个普通图标变成可浏览的树形内容。

## 它解决什么问题

Finder 能预览图片、文档和视频，却不能快速回答最常见的问题：这个文件夹里有什么？这个压缩包里到底是哪一层目录？InnerPeek 专注解决这一件事。

| 能力 | 说明 |
| --- | --- |
| 文件夹树形预览 | 原生 Quick Look 窗口中查看目录层级、文件大小和修改时间。 |
| ZIP 零解压浏览 | 直接读取 ZIP central directory，不把压缩包解到磁盘，打开快、占用小。 |
| 整行展开 / 收起 | 点击文件夹整行即可切换，保留 macOS 原生 disclosure triangle。 |
| 真实文件图标 | 磁盘文件使用系统类型图标；ZIP 内部使用缓存的类型图标，避免阻塞首次点击。 |
| 原生交互 | 使用 AppKit `NSOutlineView`，支持键盘、触控板和系统 Quick Look 动画。 |
| 最小驻留 | 主 App 只负责设置说明，Quick Look 扩展按需运行，不后台常驻。 |

## 快速开始

1. 从 [Releases](../../releases) 下载适合当前 macOS 的 ZIP。
2. 解压后把 `InnerPeek.app` 拖进「应用程序」。
3. 首次打开时按提示完成权限设置（普通目录不需要额外权限）。
4. 在 Finder 中选中文件夹或 ZIP，按空格键即可预览。
5. 在预览中点击文件夹整行，或点击左侧箭头，展开 / 收起目录。

InnerPeek 不会自动打开文件、解压文件或修改原始内容。

## macOS 权限说明

普通文件夹和 Finder 主动交给 Quick Look 的项目无需完全磁盘访问。若要预览桌面、文稿、下载、邮件资料或其他受 macOS 保护的位置，请打开：

**系统设置 → 隐私与安全性 → 完全磁盘访问权限 → “+” → 选择 `/Applications/InnerPeek.app` → 打开开关**

回到 Finder 后重新按一次空格。InnerPeek 设置窗口会通过实际读取受保护目录自动刷新状态，不需要手动确认按钮。

macOS 不允许应用静默把自己加入完全磁盘访问列表；授权必须由用户确认。权限只用于读取你主动预览的内容，InnerPeek 不上传文件，也不修改文件。

## 为什么它快

- 文件夹读取只请求目录、大小和修改时间等必要元数据。
- ZIP 只扫描 central directory，避免完整解压和临时文件。
- 子目录按需加载，第一次展开和后续收起都使用原生 outline 动画。
- 系统图标采用异步缓存，避免 Launch Services 查询卡住 Quick Look 主线程。
- Release 使用 Swift whole-module optimization，并支持 Apple Silicon 与 Intel。

## 性能对比

InnerPeek 的目标不是替代专业压缩工具，而是让“按空格看一眼”这件事足够快。下面是实现机制上的对比：

| 场景 | InnerPeek | Finder 原生预览 | 先解压再查看 | 专业压缩工具 |
| --- | --- | --- | --- | --- |
| 查看文件夹层级 | 原生树形、子目录按需读取 | 通常只显示文件夹摘要 | 需要先生成副本 | 功能完整但启动路径更重 |
| 查看 ZIP 目录 | 读取 central directory，零解压 | 通常无法展开目录 | 需要完整或部分解压 | 可能建立临时缓存 |
| 首次交互 | 只加载当前层，图标异步解析 | 启动轻，但信息有限 | 受解压大小影响 | 取决于索引和缓存 |
| 磁盘占用 | 不创建解压副本 | 无额外副本 | 可能接近压缩包大小 | 通常有缓存或临时目录 |
| 适合任务 | 快速确认内容、找文件 | 看单个文件元数据 | 编辑或批量使用内容 | 解压、压缩、校验、转换 |

InnerPeek 不承诺脱离硬件、磁盘和压缩包结构的固定毫秒数；它把最容易造成卡顿的完整解压、同步图标查询和一次性加载全部目录，从交互路径中移开。

## 后续功能支持

项目会优先保持 Quick Look 的轻量和稳定，再逐步增加以下能力：

- **更深层的按需预览**：在不关闭当前 Quick Look 的情况下进入内部文件夹，并支持空格键返回上一级。
- **更多压缩格式**：在系统安全边界允许的前提下增加 TAR、GZIP、7Z 等格式的目录索引预览。
- **更强的类型图标缓存**：扩展名、UTI 和系统图标的分层缓存，减少大型目录首次滚动时的图标延迟。
- **大目录虚拟化**：对数万文件的目录采用分页或可见区域加载，控制内存和首屏时间。
- **可选的预览设置**：隐藏列、排序方式、显示隐藏文件等设置，默认保持 Finder 风格。
- **更多可访问性支持**：完善 VoiceOver、键盘导航、动态字体和本地化文案。

这些功能会以不后台驻留、不修改原文件、不把 ZIP 全量解压为前提；如果某项功能会明显增加 Quick Look 的启动成本，将保持为可选能力。

## 下载与校验

当前免费分发包是 Ad-Hoc 签名，不是 Developer ID 公证包。首次运行如被 macOS 阻止，可在「隐私与安全性」中允许，或确认来源后执行：

```sh
xattr -dr com.apple.quarantine /Applications/InnerPeek.app
```

校验下载包：

```sh
shasum -a 256 InnerPeek-1.0.5-adhoc.zip
```

对应哈希见同一 Release 中的 `SHA256SUMS`。

## 常见问题

<details>
<summary><strong>为什么看不到文件夹内部内容？</strong></summary>

先确认 Finder 传给 Quick Look 的是文件夹本身，而不是别的文件。受 macOS 保护的目录需要在完全磁盘访问中添加 InnerPeek；授权后重新打开 Finder 预览。

</details>

<details>
<summary><strong>ZIP 会不会被解压到磁盘？</strong></summary>

不会。InnerPeek 只读取 ZIP 的目录索引；内部文件没有真实路径，因此只显示类型图标，不会启动外部解压进程。

</details>

<details>
<summary><strong>为什么首次打开比第二次慢？</strong></summary>

首次打开需要创建 Quick Look 扩展和目录数据；文件夹子目录和图标随后会按需缓存。重复打开会复用系统和应用缓存。

</details>

<details>
<summary><strong>为什么 macOS 提示无法验证开发者？</strong></summary>

当前版本没有付费 Apple Developer 账号，因此使用免费 Ad-Hoc 签名，不能提供 Developer ID 公证。请只从本仓库 Release 下载，并按系统提示允许打开。

</details>

## 隐私与安全

- 所有目录读取、ZIP 索引解析和图标处理都在本机完成。
- 不联网、不上传、不修改原文件。
- 不后台驻留，不创建登录项或常驻服务。
- Quick Look 扩展保持 App Sandbox；主 App 只在设置窗口打开时运行，用真实读取结果检测权限，不后台驻留。

## 项目与反馈

- 项目主页：[github.com/fjd2004711/InnerPeek](https://github.com/fjd2004711/InnerPeek)
- 发布下载：[GitHub Releases](../../releases)
- 欢迎提交 Issue，附上 macOS 版本、文件类型和可复现步骤；不要上传私人文件或受保护目录内容。

## 许可

项目代码采用 [MIT License](LICENSE)。
