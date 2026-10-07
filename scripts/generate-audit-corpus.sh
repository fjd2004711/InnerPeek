#!/bin/zsh
set -euo pipefail

out="${1:?usage: generate-audit-corpus.sh OUTPUT_DIR}"
rm -rf "$out"
mkdir -p "$out/synthetic" "$out/semi-realistic"
write() { local filepath="$1"; local bytes="${2:-8}"; mkdir -p "${filepath:h}"; dd if=/dev/zero of="$filepath" bs=1 count="$bytes" 2>/dev/null; }
zip_case() { local source="$1"; local target="$2"; (cd "$out/$source" && /usr/bin/zip -q -r "$out/$target" .); }
git_fixture() { local name="$1"; local head="$2"; local remote="${3:-}"; mkdir -p "$out/synthetic/$name/.git"; print -r -- "$head" > "$out/synthetic/$name/.git/HEAD"; [[ -z "$remote" ]] || print -r -- $'[remote "origin"]\n\turl = '"$remote" > "$out/synthetic/$name/.git/config"; }

# Synthetic corpus: clean, bounded cases used for stable regression expectations.
write "$out/synthetic/transformer-complete/config.json" 3
write "$out/synthetic/transformer-complete/tokenizer.json" 3
write "$out/synthetic/transformer-complete/tokenizer_config.json" 3
write "$out/synthetic/transformer-complete/model.safetensors" 2048
write "$out/synthetic/transformer-abnormal/config.json" 3
write "$out/synthetic/transformer-abnormal/tokenizer.json" 3
write "$out/synthetic/transformer-abnormal/model.safetensors" 8
for ext in shp shx dbf prj; do write "$out/synthetic/shapefile-complete/map.$ext" 12; done
write "$out/synthetic/shapefile-incomplete/map.shp" 12
write "$out/synthetic/shapefile-incomplete/map.dbf" 12
write "$out/synthetic/node-docker/package.json" 47
write "$out/synthetic/node-docker/pnpm-lock.yaml" 23
write "$out/synthetic/node-docker/Dockerfile" 13
write "$out/synthetic/node-docker/compose.yml" 13
write "$out/synthetic/node-docker/src/index.ts" 20
write "$out/synthetic/latex/main.tex" 20
write "$out/synthetic/latex/references.bib" 20
write "$out/synthetic/latex/figures/plot.png" 20
write "$out/synthetic/photo-raw/001.CR3" 100
write "$out/synthetic/photo-raw/001.JPG" 80
write "$out/synthetic/photo-raw/002.CR3" 100
write "$out/synthetic/photo-raw/002.JPG" 80
write "$out/synthetic/generic-mixed/report.pdf" 20
write "$out/synthetic/generic-mixed/photo.jpg" 20
write "$out/synthetic/generic-mixed/data.csv" 20
write "$out/synthetic/generic-mixed/notes.txt" 20
write "$out/synthetic/generic-mixed/opaque.zzz" 20
write "$out/synthetic/storage-concentration/large.dat" 800
write "$out/synthetic/storage-concentration/a.txt" 100
write "$out/synthetic/storage-concentration/b.txt" 100
for i in {0..3}; do write "$out/synthetic/balanced/file-$i.txt" 250; done

# Stage 10A: deterministic local-only Git metadata fixtures. None invokes Git
# or carries a usable credential; the credential fixture uses a fake token.
git_fixture git-github-https "ref: refs/heads/main" "https://github.com/example/demo.git"
git_fixture git-github-ssh "ref: refs/heads/dev" "git@github.com:example/demo.git"
git_fixture git-gitlab "ref: refs/heads/main" "https://gitlab.com/example/demo.git"
git_fixture git-bitbucket "ref: refs/heads/main" "https://bitbucket.org/example/demo.git"
git_fixture git-custom-remote "ref: refs/heads/release" "ssh://git@git.example.test/team/demo.git"
git_fixture git-no-remote "ref: refs/heads/main"
git_fixture git-detached-head "0123456789012345678901234567890123456789" "https://github.com/example/demo.git"
mkdir -p "$out/synthetic/github-metadata-no-git/.github/workflows"
write "$out/synthetic/github-metadata-no-git/README.md" 10
mkdir -p "$out/synthetic/malformed-git/.git"
print -r -- "not-a-valid-head" > "$out/synthetic/malformed-git/.git/HEAD"
mkdir -p "$out/synthetic/git-worktree-pointer/linked-git"
print -r -- "gitdir: linked-git" > "$out/synthetic/git-worktree-pointer/.git"
print -r -- "ref: refs/heads/worktree" > "$out/synthetic/git-worktree-pointer/linked-git/HEAD"
print -r -- $'[remote "upstream"]\n\turl = https://github.com/example/worktree.git' > "$out/synthetic/git-worktree-pointer/linked-git/config"
git_fixture credential-bearing-remote "ref: refs/heads/main" "https://username:fake-token@github.com/example/demo.git"
mkdir -p "$out/synthetic/generic-folder"
git_fixture credential-bearing-scp "ref: refs/heads/main" "ghp_fakeusertoken:x-oauth-basic@github.com:example/demo.git"
git_fixture git-gitlab-subgroup "ref: refs/heads/main" "https://gitlab.com/group/sub/demo.git"
git_fixture git-ssh-port "ref: refs/heads/main" "ssh://git@github.com:22/example/demo.git"
git_fixture git-bitbucket-ssh "ref: refs/heads/main" "git@bitbucket.org:example/demo.git"
git_fixture git-uppercase-host "ref: refs/heads/main" "https://GitHub.com/example/demo.git"
# Linked worktree: HEAD lives in the worktree directory, remotes in the common directory.
mkdir -p "$out/synthetic/git-linked-worktree/main-repo/.git/worktrees/wt" "$out/synthetic/git-linked-worktree/wt"
print -r -- "ref: refs/heads/main" > "$out/synthetic/git-linked-worktree/main-repo/.git/HEAD"
print -r -- $'[remote "origin"]\n\turl = https://github.com/example/linked.git' > "$out/synthetic/git-linked-worktree/main-repo/.git/config"
print -r -- "ref: refs/heads/feature" > "$out/synthetic/git-linked-worktree/main-repo/.git/worktrees/wt/HEAD"
print -r -- "../.." > "$out/synthetic/git-linked-worktree/main-repo/.git/worktrees/wt/commondir"
print -r -- "gitdir: ../main-repo/.git/worktrees/wt" > "$out/synthetic/git-linked-worktree/wt/.git"
git_fixture git-github-transformer "ref: refs/heads/main" "https://github.com/example/model.git"
write "$out/synthetic/git-github-transformer/config.json" 3
write "$out/synthetic/git-github-transformer/tokenizer.json" 3
write "$out/synthetic/git-github-transformer/model.safetensors" 2048
git_fixture git-github-node "ref: refs/heads/main" "https://github.com/example/node.git"
write "$out/synthetic/git-github-node/package.json" 20
write "$out/synthetic/git-github-node/pnpm-lock.yaml" 20
write "$out/synthetic/git-github-node/Dockerfile" 20
write "$out/synthetic/git-github-node/compose.yml" 20

# Stage 10C: declarative project recognition fixtures. Manifests are tiny but real
# enough for the bounded readers; none contains a usable credential.
put() { local filepath="$1"; shift; mkdir -p "${filepath:h}"; print -r -- "$*" > "$filepath"; }
proj() { print -r -- "$out/synthetic/$1"; }
p=$(proj proj-nextjs-pnpm-monorepo)
put $p/package.json '{"name":"web","workspaces":["apps/*"],"dependencies":{"next":"14.0.0","react":"18.2.0"},"devDependencies":{"typescript":"5.4.0"}}'
put $p/pnpm-lock.yaml 'lockfileVersion: 9'
put $p/pnpm-workspace.yaml $'packages:\n  - apps/*'
put $p/turbo.json '{"tasks":{}}'
put $p/tsconfig.json '{}'
put $p/next.config.ts 'export default {}'
p=$(proj proj-django-poetry)
put $p/pyproject.toml $'[tool.poetry]\nname = "site"\n\n[tool.poetry.dependencies]\npython = "^3.12"\nDjango = "^5.0"\n'
put $p/poetry.lock '# lock'
put $p/manage.py 'import django'
p=$(proj proj-python-uv-pip)
put $p/pyproject.toml $'[project]\nname = "svc"\ndependencies = [\n  "Django>=5.0",  # web\n  "requests",\n]\n\n[tool.uv]\ndev-dependencies = []\n'
put $p/uv.lock 'version = 1'
put $p/requirements.txt $'# exported\nDjango==5.0\n'
p=$(proj proj-swift-package-xcode)
put $p/Package.swift '// swift-tools-version:5.9'
mkdir -p $p/App.xcodeproj
p=$(proj proj-rust-workspace)
put $p/Cargo.toml $'[workspace]\nmembers = ["crates/*"]\n\n[workspace.dependencies]\nserde = "1"\n'
put $p/Cargo.lock '# lock'
p=$(proj proj-go-module)
put $p/go.mod $'module example.com/svc\n\ngo 1.22\n\nrequire (\n\tgithub.com/gin-gonic/gin v1.9.1\n)\n'
put $p/go.sum 'sum'
p=$(proj proj-kotlin-gradle)
put $p/build.gradle.kts 'plugins { kotlin("jvm") version "1.9.0"; java }'
put $p/settings.gradle.kts 'rootProject.name = "app"'
put $p/gradlew '#!/bin/sh'
p=$(proj proj-maven-java)
put $p/pom.xml '<project><artifactId>demo</artifactId></project>'
p=$(proj proj-conflicting-lockfiles)
put $p/package.json '{"name":"both","dependencies":{}}'
put $p/package-lock.json '{}'
put $p/pnpm-lock.yaml 'lockfileVersion: 9'
p=$(proj proj-malformed-manifests)
put $p/package.json '{ this is not json'
put $p/pyproject.toml $'[[[ nonsense\n= = =\ndependencies = [ "unterminated'
put $p/Cargo.toml '[[['
put $p/go.mod $'require (\n\tunterminated'
p=$(proj proj-credential-manifest)
put $p/package.json '{"name":"leaky","dependencies":{"next":"14.0.0"},"publishConfig":{"_authToken":"npm_FAKEsecretTOKEN0123"},"//":"ghp_FAKEsecretGITHUB"}'
p=$(proj proj-oversize-manifest)
mkdir -p $p; { printf '{"dependencies":{"next":"1"},"pad":"'; head -c 300000 /dev/zero | tr '\0' 'a'; printf '"}'; } > $p/package.json
p=$(proj proj-symlink-manifest)
mkdir -p $p $out/synthetic/proj-symlink-target
put $out/synthetic/proj-symlink-target/real.json '{"dependencies":{"next":"1","react":"1"}}'
ln -s ../proj-symlink-target/real.json $p/package.json

# Semi-realistic corpus deliberately includes noise and generated artifacts.
write "$out/semi-realistic/messy-python/pyproject.toml" 30
write "$out/semi-realistic/messy-python/uv.lock" 30
write "$out/semi-realistic/messy-python/src/main.py" 20
write "$out/semi-realistic/messy-python/tests/test_main.py" 20
write "$out/semi-realistic/messy-python/output.csv" 20
write "$out/semi-realistic/messy-python/notes.txt" 20
write "$out/semi-realistic/messy-python/old/README.md" 20
write "$out/semi-realistic/messy-node/package.json" 30
write "$out/semi-realistic/messy-node/pnpm-lock.yaml" 30
write "$out/semi-realistic/messy-node/src/index.ts" 20
write "$out/semi-realistic/messy-node/dist/bundle.js" 20
write "$out/semi-realistic/messy-node/notes.txt" 20
write "$out/semi-realistic/messy-node/backup.zip" 20
write "$out/semi-realistic/research/paper.tex" 30
write "$out/semi-realistic/research/references.bib" 30
write "$out/semi-realistic/research/figures/chart.png" 20
write "$out/semi-realistic/research/data.csv" 20
write "$out/semi-realistic/research/results.npy" 20
write "$out/semi-realistic/research/notebook.ipynb" 20
write "$out/semi-realistic/ai-experiment/config.json" 3
write "$out/semi-realistic/ai-experiment/tokenizer.json" 3
write "$out/semi-realistic/ai-experiment/model.safetensors" 8
write "$out/semi-realistic/ai-experiment/train.py" 20
write "$out/semi-realistic/ai-experiment/metrics.csv" 20
write "$out/semi-realistic/ai-experiment/checkpoint-old/weights.bin" 20
write "$out/semi-realistic/ai-experiment/screenshot.png" 20
write "$out/semi-realistic/downloads/manual.pdf" 20
write "$out/semi-realistic/downloads/installer.dmg" 20
write "$out/semi-realistic/downloads/archive.zip" 20
write "$out/semi-realistic/downloads/photo.jpg" 20
write "$out/semi-realistic/downloads/data.json" 20
write "$out/semi-realistic/downloads/opaque.file" 20
write "$out/semi-realistic/backup/project-copy.zip" 20
write "$out/semi-realistic/backup/project-copy/README.md" 20
write "$out/semi-realistic/backup/project-copy/data.csv" 20
write "$out/semi-realistic/backup/old-notes.txt" 20
write "$out/semi-realistic/messy-photos/001.CR3" 100
write "$out/semi-realistic/messy-photos/001.JPG" 80
write "$out/semi-realistic/messy-photos/001.XMP" 20
write "$out/semi-realistic/messy-photos/screenshot.png" 20
write "$out/semi-realistic/messy-photos/video.mov" 100
zip_case synthetic/transformer-complete synthetic/transformer-complete.zip
zip_case synthetic/node-docker synthetic/node-docker.zip
zip_case synthetic/generic-mixed synthetic/generic-mixed.zip
zip_case semi-realistic/downloads semi-realistic/random-zip.zip
