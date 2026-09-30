# Adding a File Type

Edit `Knowledge/file-types.json` and add one definition. Use a lowercase kebab-case `id`, lowercase extensions without a leading dot, and at least one existing role from `Knowledge/roles.json`.

Every definition needs English and Simplified Chinese `name` and `description` values. A type can have several roles, for example `package.json` uses both `manifest` and `configuration`.

Run `scripts/validate-knowledge.sh` before opening a pull request. Adding a type does not require Swift changes.
