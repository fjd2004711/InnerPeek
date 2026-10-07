# Supported file types

InnerPeek recognises **95 file types** covering **663 extensions**, plus well-known file names and name patterns. Recognition drives the icon, the type name and the role of a file (for example *model weights*, *manifest*, *lockfile*), which in turn powers insights such as "model package is missing a tokenizer".

> This page is generated from [`Knowledge/file-types.json`](../Knowledge/file-types.json) by `scripts/generate-supported-types.sh`. To add a type, edit that file; see [adding-file-types](adding-file-types.md). Anything not listed still gets the type name and icon macOS provides.

Other languages: [简体中文](supported-file-types.zh-Hans.md)

## By category

### Documents (17)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| AsciiDoc document | `.adoc` `.asciidoc` | A document written in AsciiDoc markup. |
| Bibliography | `.bbl` `.bib` `.bst` | A BibTeX bibliography or style file. |
| Calendar or contact | `.ics` `.vcf` | An iCalendar event or vCard contact. |
| Computational Notebook | `.ipynb` `.qmd` `.rmd` | Document combining code, text and outputs. |
| Diagram or publication | `.pub` `.vsd` `.vsdx` `.xps` | A Visio diagram, Publisher document or XPS page. |
| Email message or mailbox | `.eml` `.emlx` `.mbox` `.msg` `.pst` | A saved email message or mailbox archive. |
| LaTeX source | `.cls` `.dtx` `.ltx` `.sty` `.tex` | A LaTeX document, style or class file. |
| License File | `LICENSE` `LICENSE.txt` `COPYING` | Terms governing use and distribution. |
| Log File | `.log` `.out` `.trace` | Text record of application or system activity. |
| PDF Document | `.pdf` | Portable Document Format document. |
| Presentation | `.key` `.odg` `.odp` `.pot` `.potx` `.pps` `.ppsm` `.ppsx` `.ppt` `.pptm` `.pptx` | Slide-based presentation document. |
| Project Documentation | `README` `README.md` `README.rst` | Documentation explaining a project or folder. |
| Saved web page | `.mht` `.mhtml` `.webarchive` | A web page saved with its resources in one file. |
| Subtitles | `.ass` `.sbv` `.srt` `.ssa` `.sub` `.vtt` | Timed subtitle or caption text for a video. |
| Text Document | `.markdown` `.md` `.org` `.rst` `.rtf` `.text` `.txt` | Human-readable text document. |
| Word Processing Document | `.doc` `.docm` `.docx` `.dot` `.dotm` `.dotx` `.odt` `.pages` `.wpd` `.wps` | Editable rich-text document. |
| eBook | `.azw` `.azw3` `.chm` `.djvu` `.epub` `.fb2` `.mobi` | Digital book file. |

### Spreadsheets (2)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Delimited Table | `.csv` `.tab` `.tsv` | Plain-text table with delimiter-separated values. |
| Spreadsheet | `.numbers` `.ods` `.xls` `.xlsb` `.xlsm` `.xlsx` `.xlt` `.xltm` `.xltx` | Workbook containing tables, formulas or charts. |

### Images (6)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Design file | `.afdesign` `.afphoto` `.ai` `.cdr` `.clip` `.eps` `.fig` `.idml` `.indd` `.kra` `.psb` `.psd` `.sketch` `.xcf` `.xd` | A layered or vector design file from Photoshop, Illustrator, Sketch, Figma and similar tools. |
| JPEG Image | `.jfif` `.jpe` `.jpeg` `.jpg` | Compressed photographic image. |
| PNG Image | `.apng` `.png` | Lossless raster image. |
| Raster Image | `.avif` `.bmp` `.gif` `.heic` `.heif` `.icns` `.ico` `.tif` `.tiff` `.webp` | Raster image in a common image format. |
| SVG Vector Image | `.svg` `.svgz` | Scalable vector graphics image. |
| Specialist image | `.cur` `.dds` `.dib` `.emf` `.exr` `.hdr` `.j2k` `.jp2` `.jxl` `.pbm` `.pcx` `.pgm` `.pict` `.pnm` `.ppm` `.tga` `.wbmp` `.wmf` | An image in a format used for games, film, scanning or legacy software. |

### RAW images (1)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Camera RAW Image | `.3fr` `.arw` `.cr2` `.cr3` `.dng` `.iiq` `.nef` `.orf` `.pef` `.raf` `.rw2` `.srw` | Raw sensor data captured by a digital camera. |

### Audio (1)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Audio File | `.aac` `.ac3` `.aif` `.aifc` `.aiff` `.alac` `.amr` `.ape` `.au` `.caf` `.dts` `.flac` `.m4a` `.m4b` `.m4r` `.mid` `.midi` `.mka` `.mp2` `.mp3` `.oga` `.ogg` `.opus` `.ra` `.sf2` `.wav` `.weba` `.wma` `.wv` | Digital audio recording or music file. |

### Videos (1)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Video File | `.3gp` `.asf` `.avi` `.braw` `.divx` `.f4v` `.flv` `.m2ts` `.m2v` `.m4v` `.mk3d` `.mkv` `.mov` `.mp4` `.mpeg` `.mpg` `.mpv` `.mxf` `.ogv` `.r3d` `.rm` `.rmvb` `.vob` `.webm` `.wmv` | Digital video container. |

### Archives (5)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Archive Image | `.7z` `.ace` `.arj` `.cab` `.iso` `.lz4` `.lzh` `.rar` `.sit` `.sitx` `.z` `.zpaq` | Packaged archive or disk-image file. |
| Compressed Archive | `.bz2` `.gz` `.lz` `.lzma` `.tar` `.tbz` `.tbz2` `.tgz` `.txz` `.xz` `.zst` | Compressed archive or archive stream. |
| Disk image | `.dmg` `.img` `.ova` `.ovf` `.qcow2` `.sparsebundle` `.sparseimage` `.vhdx` `.vmdk` | A container that holds a whole disk or volume. |
| Package archive | `.aar` `.appimage` `.crx` `.ear` `.egg` `.flatpak` `.gem` `.nupkg` `.snap` `.war` `.whl` `.xar` | A packaged library, extension or application. |
| ZIP Archive | `.ipa` `.jar` `.xpi` `.zip` `.zipx` | Archive containing one or more compressed files. |

### Source Code (21)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| .NET Source Code | `.cs` `.fs` `.fsx` `.vb` | Program source for the .NET platform. |
| Assembly source | `.asm` `.nasm` `.s` `.wat` | Assembly language or WebAssembly text source. |
| Automation script | `.applescript` `.awk` `.bat` `.cmd` `.command` `.psd1` `.psm1` `.rexx` `.scpt` `.scptd` `.tcl` `.tool` `.vbs` `.vim` `.workflow` | A Windows batch, VBScript, AppleScript, awk, Tcl or Vim script. |
| C-family Source Code | `.c` `.cc` `.cp` `.cpp` `.cxx` `.h` `.hpp` `.hxx` `.m` `.mm` | Program source written in C, C++ or Objective-C. |
| Functional language source | `.cl` `.clj` `.cljc` `.cljs` `.edn` `.el` `.elm` `.hs` `.lhs` `.lisp` `.lsp` `.ml` `.mli` `.purs` `.rkt` `.scm` | Source code in Haskell, OCaml, Clojure, Elm, Scheme, Lisp and related languages. |
| Hardware description source | `.sv` `.svh` `.v` `.vhd` `.vhdl` | Verilog, SystemVerilog or VHDL design source. |
| Infrastructure as code | `.bicep` `.hcl` `.nomad` `.tf` `.tfvars` | Terraform, HCL or Bicep configuration that provisions infrastructure. |
| JVM Source Code | `.groovy` `.java` `.kt` `.kts` `.scala` | Program source for the Java virtual machine. |
| JavaScript Source Code | `.cjs` `.js` `.jsx` `.mjs` | Program source written in JavaScript. |
| Other language source | `.ada` `.adb` `.ads` `.cbl` `.cob` `.coffee` `.cr` `.f` `.f77` `.f90` `.f95` `.for` `.nix` `.pas` `.prolog` | Source in Crystal, COBOL, Pascal, Fortran, Ada, Prolog, CoffeeScript, Nix or a similar language. |
| Program Source Code | `.dart` `.erl` `.ex` `.exs` `.go` `.hrl` `.nim` `.rs` `.zig` | Source code for a compiled or interpreted program. |
| Python Source Code | `.py` `.pyi` `.pyw` `.pyx` | Program source written in Python. |
| SQL Script | `.mysql` `.psql` `.sql` | Structured Query Language source file. |
| Schema definition | `.avsc` `.gql` `.graphql` `.proto` `.wsdl` `.xsd` `.xsl` `.xslt` | Protocol Buffers, GraphQL, XML Schema or similar interface definitions. |
| Script Source Code | `.bash` `.fish` `.jl` `.lua` `.php` `.pl` `.pm` `.ps1` `.r` `.rb` `.sh` `.zsh` | Source code for a scripting language. |
| Shader source | `.cg` `.frag` `.fx` `.glsl` `.hlsl` `.metal` `.shader` `.vert` `.wgsl` | GPU shader code such as Metal, GLSL, HLSL or WGSL. |
| Solidity contract | `.sol` | Solidity smart-contract source. |
| Swift Source Code | `.swift` | Program source written in Swift. |
| Template or component | `.astro` `.ejs` `.erb` `.haml` `.hbs` `.j2` `.jade` `.jinja` `.liquid` `.mdx` `.mustache` `.njk` `.pug` `.slim` `.twig` | A template or component file that is rendered into HTML or text. |
| TypeScript Source Code | `.cts` `.mts` `.ts` `.tsx` | Typed JavaScript program source. |
| Web Source File | `.css` `.htm` `.html` `.less` `.sass` `.scss` `.svelte` `.vue` `.xhtml` | Markup, style or component source for the web. |

### Configuration (13)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Backup or temporary file | `.bak` `.crdownload` `.old` `.orig` `.part` `.swo` `.swp` `.temp` `.tmp` | A backup, editor swap file or unfinished download. |
| Certificate | `.cer` `.crl` `.crt` `.csr` `.der` `.p7b` `.pem` | An X.509 certificate or certificate request. |
| Configuration File | `.cfg` `.conf` `.har` `.ini` `.json` `.json5` `.jsonc` `.jsonl` `.ndjson` `.plist` `.properties` `.toml` `.xml` `.yaml` `.yml` | Structured settings or application data. |
| Container Configuration | `Dockerfile` `compose.yml` `docker-compose.yml` | Build or runtime configuration for containers. |
| Dependency lockfile | `.lock` `package-lock.json` `yarn.lock` `pnpm-lock.yaml` `Cargo.lock` `poetry.lock` `uv.lock` `go.sum` `Gemfile.lock` `Podfile.lock` `Package.resolved` `composer.lock` `bun.lock` `Pipfile.lock` | A file that pins exact dependency versions. |
| Environment Configuration | `.dotenv` `.env` | Key-value environment settings. |
| Environment Template | `.env.example` | Example environment-variable configuration. |
| Ignore rules | `.gitignore` `.gitattributes` `.gitmodules` `.gitkeep` `.dockerignore` `.npmignore` `.eslintignore` `.prettierignore` | A file that lists paths a tool should skip. |
| Key or credential store | `.asc` `.gpg` `.jks` `.kdb` `.kdbx` `.keystore` `.p12` `.pfx` `.pgp` | A private key, keystore or password database. It may contain secrets. |
| Shortcut or link | `.alias` `.desktop` `.fileloc` `.inetloc` `.lnk` `.shortcut` `.url` `.webloc` | A file that points to a website, application or another file. |
| System folder metadata | `.DS_Store` `.localized` `Thumbs.db` `desktop.ini` | A file the operating system creates to remember folder view settings or thumbnails. |
| Tool configuration | `.editorconfig` `.npmrc` `.nvmrc` `.prettierrc` `.eslintrc` `.babelrc` `.browserslistrc` `.python-version` `.ruby-version` `.tool-versions` `.swiftlint.yml` `.swift-version` `.clang-format` `.flake8` `.pylintrc` | A dotfile that configures an editor, linter, formatter or version manager. |
| Torrent file | `.magnet` `.torrent` | A BitTorrent descriptor. |

### Databases (1)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Database File | `.accdb` `.db` `.db3` `.ldf` `.lmdb` `.mdb` `.mdf` `.ndf` `.rdb` `.realm` `.sdb` `.sqlite` `.sqlite3` `.sqlitedb` | Persistent structured database storage. |

### Scientific Data (6)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Biology or chemistry data | `.bam` `.bed` `.cif` `.fa` `.fasta` `.fastq` `.fq` `.gff` `.gtf` `.mol` `.sam` `.sdf` `.xyz` | Sequence, alignment, annotation or molecular structure data. |
| Geospatial Data | `.dbf` `.gdb` `.geojson` `.gpkg` `.gpx` `.kml` `.kmz` `.prj` `.shp` `.shx` | Data describing geographic features or maps. |
| Medical image | `.dcm` `.nii` | A DICOM or NIfTI scan. |
| NumPy Array | `.npy` `.npz` | Scientific array data stored in NumPy format. |
| Scientific Data File | `.arrow` `.avro` `.cdf` `.dta` `.feather` `.fit` `.fits` `.grb` `.grib` `.grib2` `.h5` `.hdf` `.hdf5` `.jld2` `.mat` `.msgpack` `.nc` `.orc` `.parquet` `.por` `.rdata` `.rds` `.sas7bdat` `.sav` `.tfrecord` `.xpt` | Specialized file containing scientific or analytical data. |
| Serialized object | `.joblib` `.pickle` `.pkl` | A Python object saved with pickle or joblib. Loading untrusted files can run code. |

### AI models (4)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Machine Learning Model | `.caffemodel` `.ckpt` `.engine` `.ggml` `.gguf` `.keras` `.mlmodel` `.mlpackage` `.ort` `.pdmodel` `.pdparams` `.pt` `.pte` `.pth` `.tflite` `.trt` `*model*.bin` `*weights*.bin` `*checkpoint*.bin` `*adapter*.bin` `ggml-*.bin` `saved_model.pb` `*model*.pb` `*frozen*.pb` | Model weights or model graph for machine learning. |
| ONNX Model | `.onnx` | Machine-learning model stored in ONNX format. |
| SafeTensors Model | `.safetensors` | Neural-network weights stored in the SafeTensors format. |
| Tokenizer model | `tokenizer.model` `spiece.model` `sentencepiece.model` `*tokenizer*.model` `*sentencepiece*.model` | A SentencePiece vocabulary used to split text into tokens. |

### 3D & CAD (5)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| 3D Model | `.3ds` `.3mf` `.abc` `.bvh` `.dae` `.fbx` `.glb` `.gltf` `.ifc` `.ms3d` `.obj` `.off` `.ply` `.stl` `.usd` `.usda` `.usdc` `.usdz` `.vrm` `.x3d` | Three-dimensional geometry or scene data. |
| 3D application project | `.3dm` `.c4d` `.dwf` `.fcstd` `.lwo` `.ma` `.max` `.mb` | A project file from 3ds Max, Cinema 4D, Maya, Rhino, FreeCAD or similar. |
| Blender Project | `.blend` `.blend1` | 3D scene created with Blender. |
| CAD Design File | `.dwg` `.dxf` `.iges` `.igs` `.rvt` `.skp` `.sldasm` `.sldprt` `.step` `.stp` | Computer-aided design model or drawing. |
| Point cloud | `.e57` `.las` `.laz` `.pcd` | A 3D scan stored as points. |

### Fonts (1)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Font File | `.bdf` `.dfont` `.eot` `.fon` `.otf` `.pfa` `.pfb` `.ttc` `.ttf` `.woff` `.woff2` | Digital typeface or web font. |

### Executables (3)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Compiled code | `.a` `.bc` `.class` `.dex` `.lib` `.o` `.pyc` `.pyo` `.rlib` `.wasm` | Bytecode, object code or a static library produced by a compiler. |
| Executable or Installer | `.apk` `.deb` `.dll` `.dylib` `.exe` `.msi` `.pkg` `.rpm` `.so` | Executable code, library or software installer. |
| macOS Application Bundle | `.app` `.appex` `.bundle` `.framework` `.plugin` | Bundle containing an application or executable component. |

### Projects (6)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Apple Development Project | `.playground` `.xcconfig` `.xcodeproj` `.xcworkspace` | Project metadata for Apple development tools. |
| Apple development resource | `.entitlements` `.intentdefinition` `.mobileprovision` `.nib` `.pbxproj` `.provisionprofile` `.storyboard` `.strings` `.stringsdict` `.tbd` `.xcassets` `.xcdatamodel` `.xcdatamodeld` `.xcscheme` `.xcstrings` `.xib` | An Xcode resource such as a storyboard, string table, entitlement or provisioning profile. |
| Build Configuration | `CMakeLists.txt` `Makefile` | Instructions for building software. |
| Build or task script | `.bazel` `.bzl` `.sbt` `Jenkinsfile` `Vagrantfile` `Procfile` `Justfile` `Rakefile` `Brewfile` `Tiltfile` `Fastfile` `Gruntfile.js` `gulpfile.js` | A build-rule or task-runner definition such as Bazel, sbt, Rake, Just or a Jenkins pipeline. |
| Development Project File | `.cmake` `.csproj` `.fsproj` `.gradle` `.idea` `.iml` `.makefile` `.sln` `.vbproj` `.vcxproj` | Project or build metadata for software development. |
| Project Manifest | `package.json` `pyproject.toml` `requirements.txt` `Pipfile` `Cargo.toml` `go.mod` `Package.swift` `pom.xml` `build.gradle` `build.gradle.kts` `Gemfile` `composer.json` `Podfile` | Manifest describing a software project's dependencies or build settings. |

### Other (2)

| Type | Extensions and names | What it is |
| --- | --- | --- |
| Binary data | `.bin` | Raw binary data with no standard structure. |
| Protocol Buffers data | `.pb` | A binary message serialized with Protocol Buffers. |

## Projects and technologies

Beyond single files, InnerPeek recognises what a folder is from its structure. Each conclusion carries evidence (a manifest, a dependency, a file layout) that you can expand in the preview. Rules live in [`Knowledge/project-recognition.json`](../Knowledge/project-recognition.json).

- **Project kinds** (5): Monorepo, Web API, Web Application, Xcode Project, Xcode Workspace
- **Languages** (14): C, C#, C++, Dart, Go, Java, JavaScript, Kotlin, PHP, Python, Ruby, Rust, Swift, TypeScript
- **Frameworks** (18): AppKit, Astro, Django, Electron, FastAPI, Flask, Flutter, Next.js, Nuxt, PyTorch, React, Spring Boot, Svelte, SvelteKit, SwiftUI, TensorFlow, UIKit, Vue
- **Package managers** (12): Bun, Cargo, Go Modules, Gradle, Maven, Poetry, Swift Package Manager, Yarn, npm, pip, pnpm, uv
- **Build systems** (6): CMake, Docker, Make, Nx, Turborepo, Xcode
- **Repository practices** (11): .gitignore, CI, Changelog, Code owners, Contributing guide, Dependency updates, Documentation, License, README, Security policy, Tests

Other recognised structures include Git repositories (GitHub and other hosts), Transformer model packages, Shapefiles, photo RAW + JPEG pairs and Docker projects; see [`Knowledge/relationships.json`](../Knowledge/relationships.json).
