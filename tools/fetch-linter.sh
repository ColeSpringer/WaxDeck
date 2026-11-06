#!/usr/bin/env bash
# Print the path of a pinned linter, fetched on first use into the user's
# cache, where every checkout, worktree and archive tree on the machine
# finds it. `make workflow-lint` and `make shell-lint` lint with these
# builds here and in CI, so a finding cannot depend on whose machine ran
# the check.
#
#   tools/fetch-linter.sh actionlint|shellcheck
#
# Moving a version: set it below and replace each of that tool's
# checksums with its release's own digest for the archive (`gh api
# repos/rhysd/actionlint/releases/tags/v<version>`, or the same for
# koalaman/shellcheck, lists them).
set -euo pipefail

tool=${1:-}
case "$tool" in
  actionlint | shellcheck) ;;
  *)
    echo "usage: tools/fetch-linter.sh actionlint|shellcheck" >&2
    exit 2
    ;;
esac

# The platforms both linters publish builds for. Windows on ARM runs the
# x86_64 shellcheck build under emulation.
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) plat=linux-x86_64 ;;
  Linux/aarch64 | Linux/arm64) plat=linux-arm64 ;;
  Linux/armv6l | Linux/armv7l) plat=linux-armv6 ;;
  Darwin/x86_64) plat=darwin-x86_64 ;;
  Darwin/arm64) plat=darwin-arm64 ;;
  MINGW*/x86_64 | MSYS*/x86_64 | CYGWIN*/x86_64) plat=windows-x86_64 ;;
  MINGW*/aarch64 | MSYS*/aarch64) plat=windows-arm64 ;;
  *)
    echo "fetch-linter: no pinned $tool build for $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

# Each tool's version, then this platform's release archive and its
# sha256. The binary sits at the root of every archive but shellcheck's
# tarballs, which nest it in a versioned folder.
case "$tool" in
  actionlint)
    v=1.7.12 flag=-version member=actionlint
    case "$plat" in
      linux-x86_64) asset=actionlint_${v}_linux_amd64.tar.gz sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
      linux-arm64) asset=actionlint_${v}_linux_arm64.tar.gz sha256=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 ;;
      linux-armv6) asset=actionlint_${v}_linux_armv6.tar.gz sha256=ae4a0a5227578e66f5d00ee02788d5c64fdae1fa6484ab88ceaeee9359c28fa4 ;;
      darwin-x86_64) asset=actionlint_${v}_darwin_amd64.tar.gz sha256=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
      darwin-arm64) asset=actionlint_${v}_darwin_arm64.tar.gz sha256=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
      windows-x86_64) asset=actionlint_${v}_windows_amd64.zip sha256=6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9 ;;
      windows-arm64) asset=actionlint_${v}_windows_arm64.zip sha256=cadcf7ea4efe3a68728893813643cebe1185e5b1d4be5b96245f65c9a4d5ea41 ;;
    esac
    url=https://github.com/rhysd/actionlint/releases/download/v$v/$asset
    ;;
  shellcheck)
    v=0.11.0 flag=--version member=shellcheck-v$v/shellcheck
    case "$plat" in
      linux-x86_64) asset=shellcheck-v$v.linux.x86_64.tar.gz sha256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6 ;;
      linux-arm64) asset=shellcheck-v$v.linux.aarch64.tar.gz sha256=68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc ;;
      linux-armv6) asset=shellcheck-v$v.linux.armv6hf.tar.gz sha256=89f29e76e881122416eb95947f812b1496ff9a46d1e1676abe1e3f3f903b0f46 ;;
      darwin-x86_64) asset=shellcheck-v$v.darwin.x86_64.tar.gz sha256=c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51 ;;
      darwin-arm64) asset=shellcheck-v$v.darwin.aarch64.tar.gz sha256=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f ;;
      windows-*) asset=shellcheck-v$v.zip sha256=8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e ;;
    esac
    url=https://github.com/koalaman/shellcheck/releases/download/v$v/$asset
    ;;
esac
exe=
case "$plat" in windows-*) exe=.exe ;; esac
case "$asset" in *.zip) member=$tool$exe ;; esac

cache="${XDG_CACHE_HOME:-$HOME/.cache}/waxdeck/linters"
dir="$cache/$tool-v$v.$plat"
bin="$dir/$tool$exe"

sha256_of() {
  if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

if [ ! -x "$bin" ]; then
  echo "fetch-linter: $url" >&2
  mkdir -p "$cache"
  work="$(mktemp -d "$cache/fetch.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  curl -fsSL -o "$work/$asset" "$url"
  got=$(sha256_of "$work/$asset")
  if [ "$got" != "$sha256" ]; then
    echo "fetch-linter: $asset hashes to $got, not the pinned $sha256" >&2
    exit 1
  fi
  case "$asset" in
    *.zip) unzip -q "$work/$asset" "$member" -d "$work" ;;
    *) tar -xzf "$work/$asset" -C "$work" "$member" ;;
  esac
  new="$work/$member"
  # Run before it is cached: a build this machine cannot execute must not
  # land where every later run would trust it.
  if ! said=$("$new" "$flag" 2>&1) || [[ $said != *"$v"* ]]; then
    echo "fetch-linter: the $plat $tool build does not run here: $said" >&2
    exit 1
  fi
  mkdir -p "$dir"
  # Renamed into place, unless a concurrent fetch got there first.
  [ -x "$bin" ] || mv -f "$new" "$bin"
fi

# On Windows, actionlint takes -shellcheck as a drive-letter path, and
# Git's bash runs the binary by one just as well.
if [ -n "$exe" ]; then cygpath -m "$bin"; else printf '%s\n' "$bin"; fi
