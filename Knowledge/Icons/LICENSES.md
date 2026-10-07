# Bundled brand icons

InnerPeek shows a technology logo when it recognises a framework, language, package manager,
build system or repository host. Only icons for technologies that `project-recognition.json`
(or the repository-provider table) can actually report are bundled.

- **Source:** [Simple Icons](https://github.com/simple-icons/simple-icons) **16.34.0**, files copied unmodified from the published package.
- **Package license:** CC0 1.0 (`SIMPLE-ICONS-LICENSE.md`).
- **Trademarks:** The package license does not transfer any right in the logos themselves. Every logo is a
  trademark or brand asset of its respective owner and is used here only, nominatively, to identify the
  technology that was detected in a folder. InnerPeek is not affiliated with or endorsed by any of them.
  See `SIMPLE-ICONS-DISCLAIMER.md` and each owner's brand guidelines before using these marks for anything else.
- **Rendering:** icons are monochrome templates tinted by the system; colours and shapes are never altered.
- **Adding or removing an icon:** edit `Knowledge/icon-registry.json` and add or delete the SVG in `brands/`.
  `scripts/validate-knowledge.sh` fails on missing assets, unreferenced registry keys and unsafe SVG content.

| Key | Upstream title | File |
|---|---|---|
| `brand.swift` | Swift | `brands/swift.svg` |
| `brand.python` | Python | `brands/python.svg` |
| `brand.javascript` | JavaScript | `brands/javascript.svg` |
| `brand.typescript` | TypeScript | `brands/typescript.svg` |
| `brand.rust` | Rust | `brands/rust.svg` |
| `brand.go` | Go | `brands/go.svg` |
| `brand.java` | OpenJDK | `brands/openjdk.svg` |
| `brand.kotlin` | Kotlin | `brands/kotlin.svg` |
| `brand.c` | C | `brands/c.svg` |
| `brand.cplusplus` | C++ | `brands/cplusplus.svg` |
| `brand.dart` | Dart | `brands/dart.svg` |
| `brand.ruby` | Ruby | `brands/ruby.svg` |
| `brand.php` | PHP | `brands/php.svg` |
| `brand.react` | React | `brands/react.svg` |
| `brand.nextjs` | Next.js | `brands/nextdotjs.svg` |
| `brand.vue` | Vue.js | `brands/vuedotjs.svg` |
| `brand.nuxt` | Nuxt | `brands/nuxt.svg` |
| `brand.django` | Django | `brands/django.svg` |
| `brand.npm` | npm | `brands/npm.svg` |
| `brand.yarn` | Yarn | `brands/yarn.svg` |
| `brand.pnpm` | pnpm | `brands/pnpm.svg` |
| `brand.bun` | Bun | `brands/bun.svg` |
| `brand.poetry` | Poetry | `brands/poetry.svg` |
| `brand.uv` | uv | `brands/uv.svg` |
| `brand.maven` | Apache Maven | `brands/apachemaven.svg` |
| `brand.gradle` | Gradle | `brands/gradle.svg` |
| `brand.xcode` | Xcode | `brands/xcode.svg` |
| `brand.turborepo` | Turborepo | `brands/turborepo.svg` |
| `brand.nx` | Nx | `brands/nx.svg` |
| `brand.cmake` | CMake | `brands/cmake.svg` |
| `brand.git` | Git | `brands/git.svg` |
| `brand.github` | GitHub | `brands/github.svg` |
| `brand.gitlab` | GitLab | `brands/gitlab.svg` |
| `brand.bitbucket` | Bitbucket | `brands/bitbucket.svg` |
