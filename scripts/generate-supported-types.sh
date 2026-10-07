#!/bin/zsh
# Generates docs/supported-file-types*.md from the knowledge files so the list never drifts.
#   scripts/generate-supported-types.sh           # rewrite the files
#   scripts/generate-supported-types.sh --check   # fail if they are out of date (used by CI)
set -euo pipefail

repo_root="${0:A:h:h}"
knowledge="$repo_root/Knowledge"
mode="${1:-}"

render() {
  local lang="$1"
  jq -r --arg lang "$lang" \
    --slurpfile messages "$knowledge/messages.json" \
    --slurpfile project "$knowledge/project-recognition.json" '
  def t($o): $o[$lang] // $o.en;
  def cat($c): ($messages[0].messages[$c] // {}) as $m | ($m[$lang] // $c);
  def cell: gsub("\\|"; "\\|");
  def code: "`" + . + "`";
  def zh: $lang == "zh-Hans";
  def L($en; $cn): if zh then $cn else $en end;

  # Display order and the English message key for each category.
  def order: [
    ["document","Documents"],["spreadsheet","Spreadsheets"],["image","Images"],["rawImage","RAW images"],
    ["audio","Audio"],["video","Videos"],["archive","Archives"],["sourceCode","Source Code"],
    ["configuration","Configuration"],["database","Databases"],["scientificData","Scientific Data"],
    ["aiModel","AI models"],["threeD","3D & CAD"],["font","Fonts"],["executable","Executables"],
    ["project","Projects"],["unknown","Other"]
  ];

  . as $types
  | ($types | length) as $count
  | ([$types[] | (.extensions | length)] | add) as $extensions
  | (
      L("# Supported file types"; "# 支持识别的文件类型"),
      "",
      L("InnerPeek recognises **\($count) file types** covering **\($extensions) extensions**, plus well-known file names and name patterns. Recognition drives the icon, the type name and the role of a file (for example *model weights*, *manifest*, *lockfile*), which in turn powers insights such as \"model package is missing a tokenizer\".";
        "InnerPeek 目前能识别 **\($count) 种文件类型**，覆盖 **\($extensions) 个扩展名**，以及常见的特殊文件名和文件名模式。识别结果决定图标、类型名称和文件的角色（例如*模型权重*、*清单*、*锁定文件*），洞察（例如“模型包缺少 tokenizer”）也建立在这些角色之上。"),
      "",
      L("> This page is generated from [`Knowledge/file-types.json`](../Knowledge/file-types.json) by `scripts/generate-supported-types.sh`. To add a type, edit that file; see [adding-file-types](adding-file-types.md). Anything not listed still gets the type name and icon macOS provides.";
        "> 本页由 `scripts/generate-supported-types.sh` 根据 [`Knowledge/file-types.json`](../Knowledge/file-types.json) 生成。要新增类型，请修改该文件，参见 [adding-file-types](adding-file-types.md)。未列出的文件仍会显示 macOS 提供的类型名称和图标。"),
      "",
      L("Other languages: [简体中文](supported-file-types.zh-Hans.md)"; "其他语言：[English](supported-file-types.md)"),
      "",
      L("## By category"; "## 按类别"),
      "",
      (order[] as $pair
        | ($types | map(select(.category == $pair[0])) | sort_by(t(.name))) as $items
        | select($items | length > 0)
        | "### \(cat($pair[1])) (\($items | length))",
          "",
          L("| Type | Extensions and names | What it is |"; "| 类型 | 扩展名与文件名 | 说明 |"),
          "| --- | --- | --- |",
          ($items[]
            | ( [ (.extensions[] | "." + . | code), ((.filenames // [])[] | code), ((.filenamePatterns // [])[] | code) ] | join(" ") ) as $names
            | "| \(t(.name) | cell) | \($names | cell) | \(t(.description) | cell) |"),
          ""),
      L("## Projects and technologies"; "## 项目与技术栈"),
      "",
      L("Beyond single files, InnerPeek recognises what a folder is from its structure. Each conclusion carries evidence (a manifest, a dependency, a file layout) that you can expand in the preview. Rules live in [`Knowledge/project-recognition.json`](../Knowledge/project-recognition.json).";
        "除了单个文件，InnerPeek 还会根据结构判断一个文件夹是什么。每个结论都带有可展开查看的依据（清单文件、依赖、目录结构）。规则位于 [`Knowledge/project-recognition.json`](../Knowledge/project-recognition.json)。"),
      "",
      ( [["projectKind", L("Project kinds"; "项目类型")], ["language", L("Languages"; "语言")], ["framework", L("Frameworks"; "框架")],
         ["packageManager", L("Package managers"; "包管理器")], ["buildSystem", L("Build systems"; "构建系统")], ["practice", L("Repository practices"; "仓库实践")]][]
        | . as $row
        | ($project[0].facts | map(select(.kind == $row[0]) | t(.name)) | unique) as $names
        | select($names | length > 0)
        | "- **\($row[1])** (\($names | length)): \($names | join(L(", "; "、")))"),
      "",
      L("Other recognised structures include Git repositories (GitHub and other hosts), Transformer model packages, Shapefiles, photo RAW + JPEG pairs and Docker projects; see [`Knowledge/relationships.json`](../Knowledge/relationships.json).";
        "其他能识别的结构包括 Git 仓库（GitHub 及其他托管方）、Transformer 模型包、Shapefile、照片 RAW + JPEG 配对和 Docker 项目，参见 [`Knowledge/relationships.json`](../Knowledge/relationships.json)。")
    )' "$knowledge/file-types.json"
}

rc=0
for pair in "en:supported-file-types.md" "zh-Hans:supported-file-types.zh-Hans.md"; do
  lang="${pair%%:*}"; file="$repo_root/docs/${pair#*:}"
  content="$(render "$lang")"
  if [[ "$mode" == "--check" ]]; then
    if [[ "$(cat "$file" 2>/dev/null)" != "$content" ]]; then print -u2 "out of date: docs/${file:t} (run scripts/generate-supported-types.sh)"; rc=1; fi
  else
    print -r -- "$content" > "$file"
  fi
done
exit $rc
