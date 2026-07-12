#!/usr/bin/env bash
# Generate the Dart API client (dart-dio) from api/openapi.yaml into
# app/packages/waxdeck_api_gen. Requires Node (npx); provisions its own JRE
# into tools/.cache if none is on PATH. Pinned generator version lives in
# tools/openapitools.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/api/openapi.yaml"
OUT="$ROOT/app/packages/waxdeck_api_gen"
CACHE="$ROOT/tools/.cache"

# --- 1. Java 17+ (openapi-generator is a JVM tool) ----------------------------
have_java() { command -v java >/dev/null 2>&1; }
if ! have_java && [ -x "$CACHE/jre/bin/java" ]; then
  export JAVA_HOME="$CACHE/jre" PATH="$CACHE/jre/bin:$PATH"
fi
if ! have_java; then
  echo "generate-dart: no java found; fetching Temurin 21 JRE into tools/.cache/jre" >&2
  mkdir -p "$CACHE"
  os=linux; [ "$(uname -s)" = Darwin ] && os=mac
  arch=x64; [ "$(uname -m)" = aarch64 ] || [ "$(uname -m)" = arm64 ] && arch=aarch64
  curl -fsSL -o "$CACHE/jre.tar.gz" \
    "https://api.adoptium.net/v3/binary/latest/21/ga/${os}/${arch}/jre/hotspot/normal/eclipse"
  rm -rf "$CACHE/jre" "$CACHE/jre-extract"
  mkdir -p "$CACHE/jre-extract"
  tar -xzf "$CACHE/jre.tar.gz" -C "$CACHE/jre-extract"
  mv "$CACHE/jre-extract"/* "$CACHE/jre"
  rmdir "$CACHE/jre-extract"
  rm "$CACHE/jre.tar.gz"
  export JAVA_HOME="$CACHE/jre" PATH="$CACHE/jre/bin:$PATH"
fi

# --- 2. Generate (version pinned in tools/openapitools.json) -------------------
cd "$ROOT/tools"
npx --yes @openapitools/openapi-generator-cli generate \
  -i "$SPEC" \
  -g dart-dio \
  -o "$OUT" \
  --additional-properties=pubName=waxdeck_api_gen,pubVersion=0.1.0,pubDescription=Generated-WaxDeck-API-client-do-not-edit

# --- 3. Make the generated package a workspace member --------------------------
# The dart-dio template still emits a pre-3.5 SDK lower bound, which forbids
# `resolution: workspace`; lift it to the workspace's language version.
sed -i.bak "s|sdk: '>=2.18.0 <4.0.0'|sdk: ^3.12.0|" "$OUT/pubspec.yaml" && rm -f "$OUT/pubspec.yaml.bak"
if ! grep -q '^resolution: workspace' "$OUT/pubspec.yaml"; then
  printf '\nresolution: workspace\n' >>"$OUT/pubspec.yaml"
fi
# Drop generator litter that doesn't belong in the repo, and quiet analyzer
# noise (unused imports, etc.) inside the generated package only. The
# workspace analyze gate stays strict everywhere else.
# (test/ holds empty TODO scaffolds, doc/ is regenerable markdown; neither
# earns a place in the repo.)
rm -rf "$OUT/.openapi-generator" "$OUT/git_push.sh" "$OUT/.gitignore" "$OUT/.travis.yml" \
  "$OUT/test" "$OUT/doc"
cat >"$OUT/analysis_options.yaml" <<'EOF'
# Generated package (make generate): lints relaxed for generator output.
analyzer:
  errors:
    unused_import: ignore
    unused_element: ignore
    unused_field: ignore
    deprecated_member_use: ignore
EOF

# --- 4. built_value codegen (.g.dart) ------------------------------------------
cd "$ROOT/app"
dart pub get
cd "$OUT"
dart run build_runner build --delete-conflicting-outputs

echo "generate-dart: OK -> $OUT"
