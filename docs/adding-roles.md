# Adding a Role

Roles are the stable vocabulary shared by file recognition and relationship rules. Add a role to `Knowledge/roles.json` only when an existing role cannot express the file's meaning.

Use a concise camelCase id and provide an `en` name; other languages are optional (see [localization.md](localization.md)). Keep the vocabulary small and reusable across formats. Run `scripts/validate-knowledge.sh` after editing.
