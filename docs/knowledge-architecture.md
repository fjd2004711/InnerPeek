# Community Knowledge Architecture

InnerPeek separates knowledge from behavior:

```text
Knowledge/file-types.json  ->  File Type  ->  Semantic Role
Knowledge/relationships.json  ->  declarative relationship detector
Swift specialized detectors  ->  basename, directory, and content rules
```

The knowledge files are bundled with the Quick Look extension. Community additions should normally touch only JSON and documentation. `scripts/validate-knowledge.sh` checks JSON shape, duplicate ids and extensions, role references, categories, and localization coverage.
