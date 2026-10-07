#!/bin/zsh
# Creates small, made-up projects used for README screenshots (see scripts/render-screenshots.sh).
# Nothing here comes from a real machine: names, remotes and "secrets" are fictional.
# Usage: scripts/make-demo-fixtures.sh <empty-output-directory>
set -euo pipefail

out="${1:?usage: make-demo-fixtures.sh <output-directory>}"
[[ -d "$out" && -z "$(ls -A "$out")" ]] || { print -u2 "output directory must exist and be empty"; exit 1; }

put() { local f="$1"; shift; mkdir -p "${f:h}"; print -r -- "$*" > "$f"; }
# A file of roughly <kb> kilobytes of readable filler.
filler() { local f="$1" kb="$2"; mkdir -p "${f:h}"; yes "// demo content: this line only exists to give the file a realistic size." | head -c $(( kb * 1024 )) > "$f" || true; }
sparse() { local f="$1" size="$2"; mkdir -p "${f:h}"; /usr/bin/truncate -s "$size" "$f"; }
repo() { mkdir -p "$1/.git"; print -r -- "ref: refs/heads/main" > "$1/.git/HEAD"; printf '[remote "origin"]\n\turl = %s\n' "$2" > "$1/.git/config"; }

# 1. A well-kept web application: framework, tech stack and complete project basics.
p="$out/acme-dashboard"
repo "$p" "https://github.com/acme-labs/acme-dashboard.git"
put "$p/package.json" '{"name":"acme-dashboard","version":"2.4.0","scripts":{"dev":"next dev","test":"vitest"},"dependencies":{"next":"14.2.3","react":"18.3.1","react-dom":"18.3.1"},"devDependencies":{"typescript":"5.4.5","vitest":"1.6.0"}}'
put "$p/package-lock.json" '{"lockfileVersion":3}'
put "$p/tsconfig.json" '{"compilerOptions":{"strict":true}}'
put "$p/next.config.js" 'module.exports = {}'
put "$p/README.md" '# Acme Dashboard'
put "$p/LICENSE" 'MIT License'
put "$p/.gitignore" $'node_modules/\n.next/\n.env\n'
put "$p/.github/workflows/ci.yml" 'on: push'
put "$p/Dockerfile" 'FROM node:20'
put "$p/.dockerignore" 'node_modules'
for n in page layout globals; do filler "$p/app/$n.tsx" 38; done
for n in Chart Sidebar Table Header Card; do filler "$p/components/$n.tsx" 26; done
filler "$p/lib/api.ts" 44; filler "$p/lib/format.ts" 17
filler "$p/tests/api.test.ts" 22; filler "$p/tests/format.test.ts" 14
sparse "$p/public/hero.png" 160k; sparse "$p/public/logo.svg" 3k
mkdir -p "$p/node_modules/.bin"; filler "$p/node_modules/next/index.js" 8

# 2. A small Python service with rough edges: a stray .env, no licence, no tests.
p="$out/weather-bot"
repo "$p" "https://github.com/example-dev/weather-bot.git"
put "$p/requirements.txt" $'flask==3.0.3\nrequests==2.32.3\n'
put "$p/README.md" '# Weather Bot'
put "$p/.env" 'WEATHER_API_KEY=demo-not-a-real-key'
put "$p/Dockerfile" 'FROM python:3.12'
filler "$p/app/main.py" 7; filler "$p/app/routes.py" 5; filler "$p/app/forecast.py" 8; filler "$p/app/utils.py" 2
put "$p/app/__init__.py" ''
sparse "$p/data/cities.csv" 260k; sparse "$p/data/forecast-cache.json" 140k

# 3. A language-model package: weights, configuration and tokenizer all present.
p="$out/tiny-llama-chat"
put "$p/config.json" '{"model_type":"llama","hidden_size":2048,"num_hidden_layers":22}'
put "$p/generation_config.json" '{"temperature":0.7}'
put "$p/tokenizer_config.json" '{"model_max_length":2048}'
put "$p/special_tokens_map.json" '{"bos_token":"<s>"}'
put "$p/README.md" '# tiny-llama-chat'
sparse "$p/tokenizer.json" 1800k
sparse "$p/model.safetensors" 2200m

# 4. A release archive that accidentally contains an environment file.
a="$out/_zip-source/acme-site"
put "$a/index.html" '<!doctype html>'
put "$a/README.md" '# Acme site'
put "$a/.env" 'SMTP_PASSWORD=demo-not-a-real-password'
filler "$a/assets/app.js" 220; filler "$a/assets/vendor.js" 260; filler "$a/assets/style.css" 120
sparse "$a/assets/banner.jpg" 300k; sparse "$a/assets/logo.png" 90k
for n in regular medium bold; do sparse "$a/assets/inter-$n.woff2" 140k; done
(cd "$a" && /usr/bin/zip -q -r "$out/acme-site-release.zip" .)
