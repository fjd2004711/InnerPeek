#!/bin/zsh
set -euo pipefail

out="${1:?usage: generate-audit-corpus.sh OUTPUT_DIR}"
rm -rf "$out"
mkdir -p "$out/synthetic" "$out/semi-realistic"
write() { local filepath="$1"; local bytes="${2:-8}"; mkdir -p "${filepath:h}"; dd if=/dev/zero of="$filepath" bs=1 count="$bytes" 2>/dev/null; }
zip_case() { local source="$1"; local target="$2"; (cd "$out/$source" && /usr/bin/zip -q -r "$out/$target" .); }

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
