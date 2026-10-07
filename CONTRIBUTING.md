# Contributing / 参与贡献

Thanks for helping. English first, 中文在后。

## English

### The easiest contributions are data

Most of InnerPeek's knowledge is JSON in [`Knowledge/`](Knowledge), validated by
[`scripts/validate-knowledge.sh`](scripts/validate-knowledge.sh). You can add these **without writing Swift**:

| You want to add | Edit | Guide |
|---|---|---|
| A file type or extension | `Knowledge/file-types.json` | [adding-file-types](docs/adding-file-types.md) |
| A semantic role | `Knowledge/roles.json` | [adding-roles](docs/adding-roles.md) |
| A related-files pattern (shapefile, model package…) | `Knowledge/relationships.json` | [adding-relationships](docs/adding-relationships.md) |
| A language, framework or tool InnerPeek should recognise | `Knowledge/project-recognition.json` | [knowledge-architecture](docs/knowledge-architecture.md) |
| A risk or missing-file rule | `Knowledge/project-insights.json` | [project-insights](docs/project-insights.md) |
| A translation | `Knowledge/*.json`, `InnerPeekQL/*.lproj` | [localization](docs/localization.md) |

Principles that keep the project trustworthy:

- **Local, read-only, bounded.** No network, no writes, no unbounded reads. Rules read names and small
  manifests only.
- **Evidence over guesses.** A conclusion needs evidence a person can check. Prefer precision: one
  wrong insight costs more trust than ten missing ones.
- **Quiet by default.** Insights appear only when they are worth a reader's attention.
- **Never show secrets.** Findings carry file names, never file contents or URL credentials.

### Before you open a pull request

```sh
scripts/validate-knowledge.sh                 # needs jq
scripts/generate-supported-types.sh           # refresh docs/supported-file-types*.md after editing Knowledge/
Tests/run-file-intelligence-regression.sh     # unit-style regression tests
scripts/run-audit-corpus.sh                   # synthetic and real-world audit cases
```

CI runs the same checks. For a new recognition or insight rule, add **a positive and a negative case**
to `scripts/generate-audit-corpus.sh` and `Tests/AuditCorpus/manifest.json`, so the rule is proved to
fire and proved to stay quiet.

If you add a Swift file, add it to the Xcode project and to the file lists in
`Tests/run-file-intelligence-regression.sh` and `scripts/run-audit-corpus.sh`. Project object IDs in
`project.pbxproj` must stay unique.

### Reporting bugs

Use the issue template. Please attach **Settings → Diagnostics → Copy diagnostics**; it contains no file
contents. Do not upload private files; a description of the folder structure is enough.

### Larger changes

Open an issue first for new archive formats, new permissions, anything that touches the sandbox
entitlements, or anything that could slow down Quick Look start-up.

### Commits

Short imperative subject, a body explaining *why*. Keep unrelated changes in separate commits.

---

## 中文

### 最容易上手的是补数据

InnerPeek 大部分知识都是 [`Knowledge/`](Knowledge) 里的 JSON，由
[`scripts/validate-knowledge.sh`](scripts/validate-knowledge.sh) 校验。下面这些**不需要写 Swift**：

| 想补充 | 修改 | 说明 |
|---|---|---|
| 文件类型或扩展名 | `Knowledge/file-types.json` | [adding-file-types](docs/adding-file-types.md) |
| 语义角色 | `Knowledge/roles.json` | [adding-roles](docs/adding-roles.md) |
| 关联文件模式（Shapefile、模型包……） | `Knowledge/relationships.json` | [adding-relationships](docs/adding-relationships.md) |
| 需要识别的语言、框架或工具 | `Knowledge/project-recognition.json` | [knowledge-architecture](docs/knowledge-architecture.md) |
| 隐患或缺项规则 | `Knowledge/project-insights.json` | [project-insights](docs/project-insights.md) |
| 翻译 | `Knowledge/*.json`、`InnerPeekQL/*.lproj` | [localization](docs/localization.md) |

让项目值得信任的几条原则：

- **本地、只读、有界。** 不联网、不写入、不做无界读取。规则只读文件名和小体积的清单文件。
- **有依据，不猜测。** 结论需要别人能核对的依据。宁可少报：一条错误的洞察比十条缺失更伤信任。
- **默认安静。** 只在值得读者注意时才出现洞察。
- **永远不显示机密。** 结果只带文件名，不带文件内容或 URL 中的凭据。

### 提交 Pull Request 之前

```sh
scripts/validate-knowledge.sh                 # 需要 jq
scripts/generate-supported-types.sh           # 修改 Knowledge/ 后刷新 docs/supported-file-types*.md
Tests/run-file-intelligence-regression.sh     # 回归测试
scripts/run-audit-corpus.sh                   # 合成与真实仓库的审计用例
```

CI 会运行同样的检查。新增识别或洞察规则时，请在 `scripts/generate-audit-corpus.sh` 和
`Tests/AuditCorpus/manifest.json` 里补**一个正例和一个反例**，证明规则会触发，也证明它不会乱触发。

新增 Swift 文件时，要同时加入 Xcode 工程，以及 `Tests/run-file-intelligence-regression.sh` 和
`scripts/run-audit-corpus.sh` 的文件列表。`project.pbxproj` 里的对象 ID 必须唯一。

### 报告问题

请使用 Issue 模板，并附上 **设置 → 诊断 → 复制诊断信息**（不含任何文件内容）。不要上传私人文件，描述一下文件夹结构即可。

### 较大的改动

新的归档格式、新的权限、任何涉及沙盒 entitlements 的改动，或可能拖慢 Quick Look 启动的改动，请先开 Issue 讨论。

### 提交信息

简短的祈使句标题，正文说明*为什么*。无关的改动分开提交。
