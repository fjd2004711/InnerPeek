# Adding a File Type

Edit `Knowledge/file-types.json` and add one definition. Use a lowercase kebab-case `id`, lowercase extensions without a leading dot, and at least one existing role from `Knowledge/roles.json`.

Every definition needs an English `name` and `description`. Other languages are optional (see [localization.md](localization.md)); a missing translation simply shows English. A definition may also list `filenamePatterns` (case-insensitive globs using `*`) to match whole file names such as `*model*.bin`. A type can have several roles, for example `package.json` uses both `manifest` and `configuration`.

Run `scripts/validate-knowledge.sh` before opening a pull request. Adding a type does not require Swift changes.
