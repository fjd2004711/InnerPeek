# Adding a Relationship

Simple filename-and-role relationships belong in `Knowledge/relationships.json`. Use `required` for anchor filenames, `requiredAnyFilenames` for one-of groups, and `optionalRoles` for members that complete the relationship. Set `minimumOptionalMatches` when at least one optional member is required.

Relationships that depend on basename matching, directory structure, or file-content parsing stay as specialized Swift detectors. Run `scripts/validate-knowledge.sh` and the Stage 1–5 regression before submitting a change.
