# Troubleshooting / 故障排查

English first, 中文在后。

---

## English

### Pressing Space shows the generic folder card, not InnerPeek

Finder asks LaunchServices which Quick Look extension should preview a folder. If LaunchServices still
holds registrations of older InnerPeek builds (a copy in Downloads, a DerivedData build, an app in the
Trash), the right one may not win and Finder falls back to its plain card. `pluginkit` tidies deleted
paths by itself; **LaunchServices does not**, so stale records can survive for a long time.

**Easiest fix:** open InnerPeek → Settings (⌘,) → Diagnostics → **Repair Quick Look**. It unregisters
records that point at deleted or Trashed copies, registers and enables the current app, resets the
Quick Look cache and can restart Finder. It never deletes files and never touches other copies you keep.

**By hand** (replace paths with what the first command prints):

```sh
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

$LSR -dump | grep -E '^path:.*InnerPeek'            # every registered copy
$LSR -u "/path/to/an/old/InnerPeek.app"             # unregister each stale one
pluginkit -a /Applications/InnerPeek.app/Contents/PlugIns/InnerPeekQL.appex
pluginkit -e use -i com.innerpeek.InnerPeek.QuickLook
qlmanage -r && qlmanage -r cache
killall Finder QuickLookUIService
```

Then select the folder again. In Finder's list view a selection is not previewed until you press
Space; Gallery view previews as soon as you select.

### InnerPeek does not appear under Quick Look extensions

- Move `InnerPeek.app` to Applications and open it once.
- The published app is ad-hoc signed and not notarised. If macOS blocked it, right-click → Open, or
  System Settings → Privacy & Security → **Open Anyway**.
- Check `pluginkit -m -A -D -i com.innerpeek.InnerPeek.QuickLook -v`. Exactly one line should be listed.

### Previews of Desktop, Documents or Downloads are empty

Grant Full Disk Access (System Settings → Privacy & Security → Full Disk Access → add InnerPeek), then
reopen the preview.

### Sizes or dates are in the wrong language

The preview language is set in Settings → Language & Look. "Follow system" uses the macOS language.
Changes apply to the next preview.

### Attach diagnostics to an issue

1. InnerPeek → Settings → Diagnostics → **Copy diagnostics**. The text contains versions and
   registration paths (your home folder is shown as `~`) and **no file contents**.
2. For a preview that fails, add the Quick Look log of the last minutes:

```sh
/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.apple.quicklook"'
```

(Use `/usr/bin/log`: in zsh a bare `log` is a shell builtin.) Look for `Found extension` and
`loadPreviewSucceeded`; "Did not find any extension matching content type" means Finder did not pick
InnerPeek.

---

## 中文

### 按空格看到的是系统自带的文件夹卡片，不是 InnerPeek

Finder 会向 LaunchServices 询问由哪个 Quick Look 扩展来预览文件夹。如果 LaunchServices 里还留着旧版本的
注册记录（下载目录里的副本、DerivedData 的构建、废纸篓里的旧 App），正确的那份可能没有被选中，Finder 就退回
普通卡片。`pluginkit` 会自己清理已删除的路径，**LaunchServices 不会**，所以旧记录可能长期存在。

**最简单的办法：** 打开 InnerPeek → 设置（⌘,）→ 诊断 → **修复 Quick Look**。它会取消注册指向已删除或废纸篓
副本的记录，注册并启用当前这份，重置 Quick Look 缓存，并可选重启 Finder。不会删除任何文件，也不会动你保留的其他副本。

**手动处理**（路径以第一条命令的输出为准）：

```sh
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

$LSR -dump | grep -E '^path:.*InnerPeek'            # 列出所有已注册的副本
$LSR -u "/path/to/an/old/InnerPeek.app"             # 逐个取消注册旧的
pluginkit -a /Applications/InnerPeek.app/Contents/PlugIns/InnerPeekQL.appex
pluginkit -e use -i com.innerpeek.InnerPeek.QuickLook
qlmanage -r && qlmanage -r cache
killall Finder QuickLookUIService
```

然后重新选中文件夹。Finder 列表视图下，选中并不会立刻预览，需要按空格；画廊视图下选中即预览。

### 在 Quick Look 扩展里看不到 InnerPeek

- 把 `InnerPeek.app` 移到「应用程序」并打开一次。
- 发布的应用是 ad-hoc 签名，没有公证。如果被 macOS 拦截，右键 → 打开，或 系统设置 → 隐私与安全性 → **仍要打开**。
- 运行 `pluginkit -m -A -D -i com.innerpeek.InnerPeek.QuickLook -v`，应该恰好列出一行。

### 桌面、文稿、下载里的预览是空的

授予完全磁盘访问权限（系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 添加 InnerPeek），再重新打开预览。

### 大小或日期的语言不对

预览语言在 设置 → 语言与外观 中选择，「跟随系统」使用 macOS 的语言。修改在下一次预览时生效。

### 提交 Issue 时附上诊断信息

1. InnerPeek → 设置 → 诊断 → **复制诊断信息**。内容只有版本和注册路径（主目录显示为 `~`），**不含任何文件内容**。
2. 如果是某次预览失败，再附上最近几分钟的 Quick Look 日志：

```sh
/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.apple.quicklook"'
```

（请用 `/usr/bin/log`：在 zsh 里直接写 `log` 是 shell 内建命令。）留意 `Found extension` 和
`loadPreviewSucceeded`；出现 “Did not find any extension matching content type” 说明 Finder 没有选择 InnerPeek。
