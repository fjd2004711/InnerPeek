# 支持识别的文件类型

InnerPeek 目前能识别 **95 种文件类型**，覆盖 **663 个扩展名**，以及常见的特殊文件名和文件名模式。识别结果决定图标、类型名称和文件的角色（例如*模型权重*、*清单*、*锁定文件*），洞察（例如“模型包缺少 tokenizer”）也建立在这些角色之上。

> 本页由 `scripts/generate-supported-types.sh` 根据 [`Knowledge/file-types.json`](../Knowledge/file-types.json) 生成。要新增类型，请修改该文件，参见 [adding-file-types](adding-file-types.md)。未列出的文件仍会显示 macOS 提供的类型名称和图标。

其他语言：[English](supported-file-types.md)

## 按类别

### 文档 (17)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| AsciiDoc 文档 | `.adoc` `.asciidoc` | 使用 AsciiDoc 标记语言编写的文档。 |
| LaTeX 源文件 | `.cls` `.dtx` `.ltx` `.sty` `.tex` | LaTeX 文档、样式或文档类文件。 |
| PDF 文档 | `.pdf` | 便携式文档格式文件。 |
| 保存的网页 | `.mht` `.mhtml` `.webarchive` | 连同资源保存为单个文件的网页。 |
| 参考文献库 | `.bbl` `.bib` `.bst` | BibTeX 参考文献库或样式文件。 |
| 图表或排版文档 | `.pub` `.vsd` `.vsdx` `.xps` | Visio 图表、Publisher 文档或 XPS 页面。 |
| 字幕 | `.ass` `.sbv` `.srt` `.ssa` `.sub` `.vtt` | 视频的带时间轴字幕文本。 |
| 文字处理文档 | `.doc` `.docm` `.docx` `.dot` `.dotm` `.dotx` `.odt` `.pages` `.wpd` `.wps` | 可编辑的富文本文件。 |
| 文本文件 | `.markdown` `.md` `.org` `.rst` `.rtf` `.text` `.txt` | 可直接阅读的文本文件。 |
| 日历或联系人 | `.ics` `.vcf` | iCalendar 日程或 vCard 联系人。 |
| 日志文件 | `.log` `.out` `.trace` | 记录应用或系统活动的文本文件。 |
| 演示文稿 | `.key` `.odg` `.odp` `.pot` `.potx` `.pps` `.ppsm` `.ppsx` `.ppt` `.pptm` `.pptx` | 以幻灯片组织的演示文稿。 |
| 电子书 | `.azw` `.azw3` `.chm` `.djvu` `.epub` `.fb2` `.mobi` | 数字书籍文件。 |
| 计算笔记本 | `.ipynb` `.qmd` `.rmd` | 结合代码、文本和输出的文档。 |
| 许可证文件 | `LICENSE` `LICENSE.txt` `COPYING` | 规定使用和分发条件的文件。 |
| 邮件或邮箱文件 | `.eml` `.emlx` `.mbox` `.msg` `.pst` | 保存的邮件或邮箱归档。 |
| 项目说明 | `README` `README.md` `README.rst` | 说明项目或文件夹的文档。 |

### 电子表格 (2)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 分隔表格数据 | `.csv` `.tab` `.tsv` | 以分隔符划分字段的纯文本表格。 |
| 电子表格 | `.numbers` `.ods` `.xls` `.xlsb` `.xlsm` `.xlsx` `.xlt` `.xltm` `.xltx` | 包含表格、公式或图表的工作簿。 |

### 图像 (6)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| JPEG 图像 | `.jfif` `.jpe` `.jpeg` `.jpg` | 压缩的照片图像。 |
| PNG 图像 | `.apng` `.png` | 无损位图图像。 |
| SVG 矢量图像 | `.svg` `.svgz` | 可缩放的矢量图形图像。 |
| 专业图像格式 | `.cur` `.dds` `.dib` `.emf` `.exr` `.hdr` `.j2k` `.jp2` `.jxl` `.pbm` `.pcx` `.pgm` `.pict` `.pnm` `.ppm` `.tga` `.wbmp` `.wmf` | 用于游戏、影视、扫描或旧软件的图像格式。 |
| 位图图像 | `.avif` `.bmp` `.gif` `.heic` `.heif` `.icns` `.ico` `.tif` `.tiff` `.webp` | 采用常见图像格式的位图。 |
| 设计文件 | `.afdesign` `.afphoto` `.ai` `.cdr` `.clip` `.eps` `.fig` `.idml` `.indd` `.kra` `.psb` `.psd` `.sketch` `.xcf` `.xd` | 来自 Photoshop、Illustrator、Sketch、Figma 等工具的分层或矢量设计文件。 |

### RAW 图像 (1)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 相机 RAW 图像 | `.3fr` `.arw` `.cr2` `.cr3` `.dng` `.iiq` `.nef` `.orf` `.pef` `.raf` `.rw2` `.srw` | 由数码相机采集的原始传感器数据。 |

### 音频 (1)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 音频文件 | `.aac` `.ac3` `.aif` `.aifc` `.aiff` `.alac` `.amr` `.ape` `.au` `.caf` `.dts` `.flac` `.m4a` `.m4b` `.m4r` `.mid` `.midi` `.mka` `.mp2` `.mp3` `.oga` `.ogg` `.opus` `.ra` `.sf2` `.wav` `.weba` `.wma` `.wv` | 数字音频录制或音乐文件。 |

### 视频 (1)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 视频文件 | `.3gp` `.asf` `.avi` `.braw` `.divx` `.f4v` `.flv` `.m2ts` `.m2v` `.m4v` `.mk3d` `.mkv` `.mov` `.mp4` `.mpeg` `.mpg` `.mpv` `.mxf` `.ogv` `.r3d` `.rm` `.rmvb` `.vob` `.webm` `.wmv` | 数字视频容器文件。 |

### 归档 (5)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| ZIP 压缩包 | `.ipa` `.jar` `.xpi` `.zip` `.zipx` | 包含一个或多个压缩文件的归档。 |
| 压缩归档 | `.bz2` `.gz` `.lz` `.lzma` `.tar` `.tbz` `.tbz2` `.tgz` `.txz` `.xz` `.zst` | 压缩归档或归档数据流。 |
| 归档映像 | `.7z` `.ace` `.arj` `.cab` `.iso` `.lz4` `.lzh` `.rar` `.sit` `.sitx` `.z` `.zpaq` | 打包的归档或磁盘映像文件。 |
| 磁盘镜像 | `.dmg` `.img` `.ova` `.ovf` `.qcow2` `.sparsebundle` `.sparseimage` `.vhdx` `.vmdk` | 包含整个磁盘或卷的容器。 |
| 软件包 | `.aar` `.appimage` `.crx` `.ear` `.egg` `.flatpak` `.gem` `.nupkg` `.snap` `.war` `.whl` `.xar` | 打包好的库、扩展或应用。 |

### 源代码 (21)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| .NET 源代码 | `.cs` `.fs` `.fsx` `.vb` | 面向 .NET 平台的程序源文件。 |
| C 系列源代码 | `.c` `.cc` `.cp` `.cpp` `.cxx` `.h` `.hpp` `.hxx` `.m` `.mm` | 使用 C、C++ 或 Objective-C 编写的程序源文件。 |
| JVM 源代码 | `.groovy` `.java` `.kt` `.kts` `.scala` | 面向 Java 虚拟机的程序源文件。 |
| JavaScript 源代码 | `.cjs` `.js` `.jsx` `.mjs` | 使用 JavaScript 编写的程序源文件。 |
| Python 源代码 | `.py` `.pyi` `.pyw` `.pyx` | 使用 Python 编写的程序源文件。 |
| SQL 脚本 | `.mysql` `.psql` `.sql` | 结构化查询语言源文件。 |
| Solidity 合约 | `.sol` | Solidity 智能合约源码。 |
| Swift 源代码 | `.swift` | 使用 Swift 编写的程序源文件。 |
| TypeScript 源代码 | `.cts` `.mts` `.ts` `.tsx` | 带类型的 JavaScript 程序源文件。 |
| 其他语言源码 | `.ada` `.adb` `.ads` `.cbl` `.cob` `.coffee` `.cr` `.f` `.f77` `.f90` `.f95` `.for` `.nix` `.pas` `.prolog` | Crystal、COBOL、Pascal、Fortran、Ada、Prolog、CoffeeScript、Nix 等语言的源码。 |
| 函数式语言源代码 | `.cl` `.clj` `.cljc` `.cljs` `.edn` `.el` `.elm` `.hs` `.lhs` `.lisp` `.lsp` `.ml` `.mli` `.purs` `.rkt` `.scm` | Haskell、OCaml、Clojure、Elm、Scheme、Lisp 等语言的源代码。 |
| 基础设施即代码 | `.bicep` `.hcl` `.nomad` `.tf` `.tfvars` | 用于创建基础设施的 Terraform、HCL 或 Bicep 配置。 |
| 数据结构定义 | `.avsc` `.gql` `.graphql` `.proto` `.wsdl` `.xsd` `.xsl` `.xslt` | Protocol Buffers、GraphQL、XML Schema 等接口或数据结构定义。 |
| 模板或组件 | `.astro` `.ejs` `.erb` `.haml` `.hbs` `.j2` `.jade` `.jinja` `.liquid` `.mdx` `.mustache` `.njk` `.pug` `.slim` `.twig` | 会被渲染成 HTML 或文本的模板或组件文件。 |
| 汇编源码 | `.asm` `.nasm` `.s` `.wat` | 汇编语言或 WebAssembly 文本源码。 |
| 着色器源码 | `.cg` `.frag` `.fx` `.glsl` `.hlsl` `.metal` `.shader` `.vert` `.wgsl` | Metal、GLSL、HLSL、WGSL 等 GPU 着色器代码。 |
| 硬件描述语言源码 | `.sv` `.svh` `.v` `.vhd` `.vhdl` | Verilog、SystemVerilog 或 VHDL 设计源码。 |
| 程序源代码 | `.dart` `.erl` `.ex` `.exs` `.go` `.hrl` `.nim` `.rs` `.zig` | 用于编译或解释执行程序的源代码。 |
| 网页源文件 | `.css` `.htm` `.html` `.less` `.sass` `.scss` `.svelte` `.vue` `.xhtml` | 用于网页的标记、样式或组件源文件。 |
| 脚本源代码 | `.bash` `.fish` `.jl` `.lua` `.php` `.pl` `.pm` `.ps1` `.r` `.rb` `.sh` `.zsh` | 脚本语言的源代码。 |
| 自动化脚本 | `.applescript` `.awk` `.bat` `.cmd` `.command` `.psd1` `.psm1` `.rexx` `.scpt` `.scptd` `.tcl` `.tool` `.vbs` `.vim` `.workflow` | Windows 批处理、VBScript、AppleScript、awk、Tcl 或 Vim 脚本。 |

### 配置 (13)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 依赖锁定文件 | `.lock` `package-lock.json` `yarn.lock` `pnpm-lock.yaml` `Cargo.lock` `poetry.lock` `uv.lock` `go.sum` `Gemfile.lock` `Podfile.lock` `Package.resolved` `composer.lock` `bun.lock` `Pipfile.lock` | 记录依赖精确版本的文件。 |
| 备份或临时文件 | `.bak` `.crdownload` `.old` `.orig` `.part` `.swo` `.swp` `.temp` `.tmp` | 备份文件、编辑器交换文件或未完成的下载。 |
| 容器配置 | `Dockerfile` `compose.yml` `docker-compose.yml` | 用于容器构建或运行的配置。 |
| 密钥或凭据库 | `.asc` `.gpg` `.jks` `.kdb` `.kdbx` `.keystore` `.p12` `.pfx` `.pgp` | 私钥、密钥库或密码数据库，可能包含机密信息。 |
| 工具配置 | `.editorconfig` `.npmrc` `.nvmrc` `.prettierrc` `.eslintrc` `.babelrc` `.browserslistrc` `.python-version` `.ruby-version` `.tool-versions` `.swiftlint.yml` `.swift-version` `.clang-format` `.flake8` `.pylintrc` | 用于配置编辑器、代码检查、格式化或版本管理工具的点文件。 |
| 快捷方式或链接 | `.alias` `.desktop` `.fileloc` `.inetloc` `.lnk` `.shortcut` `.url` `.webloc` | 指向网站、应用或其他文件的文件。 |
| 忽略规则 | `.gitignore` `.gitattributes` `.gitmodules` `.gitkeep` `.dockerignore` `.npmignore` `.eslintignore` `.prettierignore` | 列出工具应忽略的路径的文件。 |
| 环境配置 | `.dotenv` `.env` | 键值形式的环境设置。 |
| 环境配置模板 | `.env.example` | 环境变量配置示例。 |
| 种子文件 | `.magnet` `.torrent` | BitTorrent 描述文件。 |
| 系统文件夹元数据 | `.DS_Store` `.localized` `Thumbs.db` `desktop.ini` | 操作系统用来记录文件夹视图设置或缩略图的文件。 |
| 证书 | `.cer` `.crl` `.crt` `.csr` `.der` `.p7b` `.pem` | X.509 证书或证书请求。 |
| 配置文件 | `.cfg` `.conf` `.har` `.ini` `.json` `.json5` `.jsonc` `.jsonl` `.ndjson` `.plist` `.properties` `.toml` `.xml` `.yaml` `.yml` | 结构化的设置或应用数据。 |

### 数据库 (1)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 数据库文件 | `.accdb` `.db` `.db3` `.ldf` `.lmdb` `.mdb` `.mdf` `.ndf` `.rdb` `.realm` `.sdb` `.sqlite` `.sqlite3` `.sqlitedb` | 持久化的结构化数据库存储。 |

### 科学数据 (6)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| NumPy 数组 | `.npy` `.npz` | 以 NumPy 格式保存的科学数组数据。 |
| 医学影像 | `.dcm` `.nii` | DICOM 或 NIfTI 扫描影像。 |
| 地理空间数据 | `.dbf` `.gdb` `.geojson` `.gpkg` `.gpx` `.kml` `.kmz` `.prj` `.shp` `.shx` | 描述地理特征或地图的数据。 |
| 序列化对象 | `.joblib` `.pickle` `.pkl` | 用 pickle 或 joblib 保存的 Python 对象，加载不可信文件可能执行代码。 |
| 生物或化学数据 | `.bam` `.bed` `.cif` `.fa` `.fasta` `.fastq` `.fq` `.gff` `.gtf` `.mol` `.sam` `.sdf` `.xyz` | 序列、比对、注释或分子结构数据。 |
| 科学数据文件 | `.arrow` `.avro` `.cdf` `.dta` `.feather` `.fit` `.fits` `.grb` `.grib` `.grib2` `.h5` `.hdf` `.hdf5` `.jld2` `.mat` `.msgpack` `.nc` `.orc` `.parquet` `.por` `.rdata` `.rds` `.sas7bdat` `.sav` `.tfrecord` `.xpt` | 包含科学或分析数据的专业文件。 |

### AI 模型 (4)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| ONNX 模型 | `.onnx` | 使用 ONNX 格式保存的机器学习模型。 |
| SafeTensors 模型 | `.safetensors` | 以 SafeTensors 格式保存的神经网络权重。 |
| 分词器模型 | `tokenizer.model` `spiece.model` `sentencepiece.model` `*tokenizer*.model` `*sentencepiece*.model` | 把文本切分成词元的 SentencePiece 词表。 |
| 机器学习模型 | `.caffemodel` `.ckpt` `.engine` `.ggml` `.gguf` `.keras` `.mlmodel` `.mlpackage` `.ort` `.pdmodel` `.pdparams` `.pt` `.pte` `.pth` `.tflite` `.trt` `*model*.bin` `*weights*.bin` `*checkpoint*.bin` `*adapter*.bin` `ggml-*.bin` `saved_model.pb` `*model*.pb` `*frozen*.pb` | 用于机器学习的模型权重或模型图。 |

### 3D 与 CAD (5)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| Blender 项目 | `.blend` `.blend1` | 使用 Blender 创建的三维场景。 |
| CAD 设计文件 | `.dwg` `.dxf` `.iges` `.igs` `.rvt` `.skp` `.sldasm` `.sldprt` `.step` `.stp` | 计算机辅助设计模型或图纸。 |
| 三维模型 | `.3ds` `.3mf` `.abc` `.bvh` `.dae` `.fbx` `.glb` `.gltf` `.ifc` `.ms3d` `.obj` `.off` `.ply` `.stl` `.usd` `.usda` `.usdc` `.usdz` `.vrm` `.x3d` | 三维几何体或场景数据。 |
| 三维软件工程文件 | `.3dm` `.c4d` `.dwf` `.fcstd` `.lwo` `.ma` `.max` `.mb` | 来自 3ds Max、Cinema 4D、Maya、Rhino、FreeCAD 等软件的工程文件。 |
| 点云 | `.e57` `.las` `.laz` `.pcd` | 以点集形式保存的三维扫描。 |

### 字体 (1)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| 字体文件 | `.bdf` `.dfont` `.eot` `.fon` `.otf` `.pfa` `.pfb` `.ttc` `.ttf` `.woff` `.woff2` | 数字字体或网页字体。 |

### 可执行文件 (3)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| macOS 应用程序包 | `.app` `.appex` `.bundle` `.framework` `.plugin` | 包含应用或可执行组件的软件包。 |
| 可执行文件或安装包 | `.apk` `.deb` `.dll` `.dylib` `.exe` `.msi` `.pkg` `.rpm` `.so` | 可执行代码、程序库或软件安装包。 |
| 编译产物 | `.a` `.bc` `.class` `.dex` `.lib` `.o` `.pyc` `.pyo` `.rlib` `.wasm` | 编译器生成的字节码、目标文件或静态库。 |

### 项目 (6)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| Apple 开发资源 | `.entitlements` `.intentdefinition` `.mobileprovision` `.nib` `.pbxproj` `.provisionprofile` `.storyboard` `.strings` `.stringsdict` `.tbd` `.xcassets` `.xcdatamodel` `.xcdatamodeld` `.xcscheme` `.xcstrings` `.xib` | Xcode 资源，例如故事板、字符串表、权限声明或描述文件。 |
| Apple 开发项目 | `.playground` `.xcconfig` `.xcodeproj` `.xcworkspace` | Apple 开发工具使用的项目元数据。 |
| 开发项目文件 | `.cmake` `.csproj` `.fsproj` `.gradle` `.idea` `.iml` `.makefile` `.sln` `.vbproj` `.vcxproj` | 软件开发使用的项目或构建元数据。 |
| 构建或任务脚本 | `.bazel` `.bzl` `.sbt` `Jenkinsfile` `Vagrantfile` `Procfile` `Justfile` `Rakefile` `Brewfile` `Tiltfile` `Fastfile` `Gruntfile.js` `gulpfile.js` | Bazel、sbt、Rake、Just 或 Jenkins 流水线等构建规则或任务定义。 |
| 构建配置 | `CMakeLists.txt` `Makefile` | 用于构建软件的指令文件。 |
| 项目清单 | `package.json` `pyproject.toml` `requirements.txt` `Pipfile` `Cargo.toml` `go.mod` `Package.swift` `pom.xml` `build.gradle` `build.gradle.kts` `Gemfile` `composer.json` `Podfile` | 描述软件项目依赖或构建设置的清单文件。 |

### 其他 (2)

| 类型 | 扩展名与文件名 | 说明 |
| --- | --- | --- |
| Protocol Buffers 数据 | `.pb` | 用 Protocol Buffers 序列化的二进制消息。 |
| 二进制数据 | `.bin` | 没有标准结构的原始二进制数据。 |

## 项目与技术栈

除了单个文件，InnerPeek 还会根据结构判断一个文件夹是什么。每个结论都带有可展开查看的依据（清单文件、依赖、目录结构）。规则位于 [`Knowledge/project-recognition.json`](../Knowledge/project-recognition.json)。

- **项目类型** (5): Monorepo 多项目仓库、Web API、Web 应用、Xcode 工作区、Xcode 项目
- **语言** (14): C、C#、C++、Dart、Go、Java、JavaScript、Kotlin、PHP、Python、Ruby、Rust、Swift、TypeScript
- **框架** (18): AppKit、Astro、Django、Electron、FastAPI、Flask、Flutter、Next.js、Nuxt、PyTorch、React、Spring Boot、Svelte、SvelteKit、SwiftUI、TensorFlow、UIKit、Vue
- **包管理器** (12): Bun、Cargo、Go Modules、Gradle、Maven、Poetry、Swift Package Manager、Yarn、npm、pip、pnpm、uv
- **构建系统** (6): CMake、Docker、Make、Nx、Turborepo、Xcode
- **仓库实践** (11): .gitignore、README、代码所有者、依赖自动更新、变更日志、安全策略、持续集成、文档目录、测试、许可证、贡献指南

其他能识别的结构包括 Git 仓库（GitHub 及其他托管方）、Transformer 模型包、Shapefile、照片 RAW + JPEG 配对和 Docker 项目，参见 [`Knowledge/relationships.json`](../Knowledge/relationships.json)。
