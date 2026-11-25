# Localization

InnerPeek ships in English and Simplified Chinese, and is built so that **adding a language never requires
changing Swift code**. English is the source language and the fallback for everything.

## What gets translated

| Where | What | How |
|---|---|---|
| `InnerPeekQL/<lang>.lproj/Localizable.strings` | Interface labels and buttons | Standard Apple `.strings` file, same keys as `en.lproj` |
| `Knowledge/messages.json` | Sentences the analysis engine writes (insights, verdicts, repository messages, metadata labels) | Keyed by the **English text**; add your language tag under it |
| Texts inside `Knowledge/*.json` | File type names and descriptions, roles, project technologies, health checks | Each text is an object like `{"en": "Fonts", "fr": "Polices"}` |

Currently 642 texts are translatable. Run the report to see exactly what a language still needs:

```sh
scripts/i18n-report.sh fr             # coverage per file
scripts/i18n-report.sh fr --missing   # every untranslated English text
```

## Adding a language, step by step

Use a BCP 47 tag such as `fr`, `de`, `ja`, `pt-BR`, `zh-Hant`.

1. **Knowledge texts and messages (no code).** In `Knowledge/messages.json` and each `Knowledge/*.json`, add your tag next to `en`:
   ```json
   "Unknown File": { "zh-Hans": "未知文件", "fr": "Fichier inconnu" }
   ```
   You can translate a few entries per pull request; untranslated ones keep showing English.
2. **Interface strings.** Copy `InnerPeekQL/en.lproj` to `InnerPeekQL/<tag>.lproj`, translate the values, and add the region
   to the Xcode project (File inspector, Localization). Keep every key identical to English.
3. **Check.** `scripts/validate-knowledge.sh` must pass, then `scripts/i18n-report.sh <tag>` shows your coverage.

## Rules the validator enforces

- English (`en`) is the only mandatory language in knowledge files.
- Language tags must look like BCP 47 (`fr`, `pt-BR`, `zh-Hant`), not words like `French`.
- **A translation must contain exactly the same placeholders as the English text.** `%@` is replaced at run time
  (for example a file name or a count), and `%%` is a literal percent sign. Do not translate, drop, add or reorder them.
  `"%@ branch"` may become `"branche %@"`, but not `"branche"`.
- In `messages.json` the key is the English source text; never put `en` under it.
- Interface `.strings` files may not define keys that English does not.

## Which translation is shown

For the user's language InnerPeek tries, in order: language-script-region, language-script, language-region, language,
and then English. Traditional Chinese (`zh-Hant`, or `zh` with region TW, HK or MO) falls back to Simplified Chinese
before English, because it is far more readable than English; add `zh-Hant` entries and they win automatically.

Names joined into one sentence (for example the health summary "Found: README, Tests") use that language's own names and
separator.

## Writing good translations

- Translate meaning, not words. Technical terms that developers use untranslated (for example `tokenizer`, `monorepo`) can stay in English.
- Keep brand and format names as they are (Swift, GitHub, PDF).
- Prefer short phrases; the preview is compact.
- Dates, numbers and sizes are formatted by macOS in the user's locale; do not format them in the text.

## Adding or changing English text in code

Write the English sentence in code and add it to `Knowledge/messages.json` with its translations:

```swift
text("One file dominates analyzed size")   // looked up in messages.json by this exact text
```

If you change the English wording, change the key in `messages.json` too; otherwise the translations stop matching and
the text shows in English. The validator does not flag unreferenced keys, so search the code for the old wording.
