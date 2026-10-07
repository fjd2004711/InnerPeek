# Project insights: risks and missing files

Two kinds of insight come from `Knowledge/project-insights.json`. Both are data: adding a rule
never needs Swift or UI changes. `scripts/validate-knowledge.sh` checks the shape, and
`Schemas/project-insights.schema.json` documents it.

## Risk rules (`risks`)

Flag files that should not be shared by accident.

| Field | Meaning |
|---|---|
| `entryKind` | `file` or `directory` |
| `names` / `paths` | Name globs (`*` only, case-insensitive) matched anywhere in the analysed tree, and exact relative paths |
| `excludeNames` | Names that are templates (`.env.example`) |
| `excludePathComponents` | Folders whose contents are ignored (`tests`, `fixtures`) |
| `contentPattern` | Regular expression run on the first 4 KB. The match is discarded; contents are never stored, shown or logged |
| `trustedWithoutContent` | Names that count in an archive, where nothing can be read |
| `scope` | `repository`: only in a Git repository or an archive. `any`: everywhere |
| `respectsGitignore` | Skip files that `.gitignore` already covers |
| `severity`, `priority` | Ranking among the (at most three) visible insights |

How it behaves:

- **Findings carry paths only.** Detail text names the file, never what is inside it.
- **`.gitignore` aware.** Root and nested `.gitignore` files plus `.git/info/exclude` are read
  (each at most 64 KB, at most 24 files). Rules are evaluated in order, `!` negates, a trailing
  slash means directories only, `**` spans folders, an ignored parent ignores its contents. A
  global excludes file is unknown to the check, so the wording is "is not covered by .gitignore"
  and never "is committed".
- **Hidden files count.** The visible listing skips dot files, so the scanner lists the root
  separately. Archives use every central-directory entry.
- **Bounded.** At most 12 content reads per folder, 40 paths per finding, no symlinks followed.
- **Templates and fixtures are quiet.** `.env.example` and keys under `tests/` or `fixtures/`
  are not reported.

## Stack rules (`stack`)

Flag missing or conflicting project files, judged from **root-level names only**.

| Field | Meaning |
|---|---|
| `requiresFact` | A recognised fact (for example `language.python`) at `medium` or `high` confidence |
| `requiresRepository` | Only inside a Git repository |
| `allPresent` / `anyPresent` | Files that must exist (names, globs, or `dir/file` paths) |
| `multiplePresent` | A conflict: at least `atLeast` of the listed files exist |
| `nonePresent` | Files that must be absent. Root names only, no slashes |

An absence claim is only made when the root listing is complete, so a rule can never say
"missing" about something it could not see. Archives are judged like the folder they were made
from: a single wrapping folder is looked through.

Choose rules for precision. A rule that fires on many healthy projects teaches people to
ignore insights. Prefer an extra `allPresent` condition (for example `src/main.rs` before asking
for `Cargo.lock`, since libraries rightly omit it) over a broad rule with exceptions.

## Adding a rule

1. Add the object to `risks` or `stack` with an English `title`/`detail` (other languages are
   optional; see `docs/localization.md`).
2. Add a positive and a negative case to `scripts/generate-audit-corpus.sh` and
   `Tests/AuditCorpus/manifest.json`.
3. Run `scripts/validate-knowledge.sh` and `scripts/run-audit-corpus.sh`.
