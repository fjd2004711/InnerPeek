# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-07

**中文摘要：** 文件夹预览在 macOS 27 上重新稳定；新增项目与技术栈识别、仓库健康度、隐患与缺项洞察、
品牌图标、设置与诊断窗口，以及可扩展的多语言支持。

### Fixed

- Folder previews fell back to Finder's generic card on macOS 27 because LaunchServices kept stale
  registrations of older builds. The app can now find and repair them (Settings → Diagnostics).
- Sizes and dates followed the system language even when another preview language was chosen.
- Dominant model weights were reported as a storage concentration; that is expected for a model
  package and is no longer shown.

### Added

- **Project recognition**: languages, frameworks, package managers, build systems and project kinds,
  driven by `Knowledge/project-recognition.json` (66 rules) with evidence you can expand.
- **Repository recognition**: Git repository state, branch, worktrees and remote host without ever
  keeping credentials from remote URLs.
- **Repository health**: README, licence, tests and CI, as a single positive or gap insight.
- **Risk insights**: unignored `.env` files, private keys, npm tokens, credential files, key containers,
  `node_modules`/`.venv` and `xcuserdata`; `.gitignore` aware, ZIP aware, paths only.
- **Missing-file insights**: missing or conflicting lockfiles, Gradle wrapper, `.dockerignore`, Python
  dependency list.
- **Brand icons** (Simple Icons, CC0) in colour or single-colour style.
- **Content metadata** for subtitles, e-mail, calendars, certificates (never key material) and fonts.
- **File types**: 95 types and 663 extensions, with filename patterns for ambiguous formats such as
  machine-learning weights.
- **Settings window**: display toggles, analysis depth and size, language and icon style, diagnostics
  and one-click repair.
- **Localization**: English is the source and fallback; any language can be added as data. Chinese is
  complete. See `docs/localization.md`.
- Documentation: `docs/settings.md`, `docs/project-insights.md`, `docs/troubleshooting.md`,
  contributing and security policies.
- CI checks for knowledge validation, regression tests and the audit corpus.

### Changed

- Preview layout: summary on the left, insights on the right, evidence on demand, then the file tree.
- Insights are limited to three and shown only when worth saying.

### Known issues

- Header corner and scroller colour can differ slightly in some appearances.
- ZIP archives get no project recognition or repository-health judgement.
- Releases are ad-hoc signed and not notarised; see the README for first launch.

## [1.0.6]

Earlier releases: file tree preview for folders and ZIP archives. See the
[GitHub Releases](https://github.com/fjd2004711/InnerPeek/releases) page.
