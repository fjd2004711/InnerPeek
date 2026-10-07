# Legacy Quick Look generator (experimental)

This folder holds an early `.qlgenerator` plug-in that rendered folder previews as HTML on macOS 14 and
older. **macOS 15 and later no longer load `.qlgenerator` plug-ins**, and folder previews are provided
by the Quick Look extension in `InnerPeekQL/`, so the generator is **not needed and not installed** by
the app or the release DMG.

It is kept for reference and for anyone who wants to experiment on an older system:

```sh
scripts/build-generator.sh            # builds build/InnerPeek.qlgenerator
scripts/build-generator.sh --install  # also installs to ~/Library/QuickLook and resets Quick Look
```

It is not covered by the regression tests and may be removed in a future release.
