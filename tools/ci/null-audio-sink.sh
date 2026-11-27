#!/usr/bin/env bash
# Starts a PulseAudio daemon of its own, whose one output is a null sink,
# and prints its address for PULSE_SERVER. The e2e engine projects play
# real audio and fail a play without an output; a runner has no sound
# device, and a null sink keeps time without making a sound. It runs on
# its own socket and touches no sound server a desktop is running. It
# installs PulseAudio only in CI; stop it with `pactl -s <address> exit`.
#
#   null-audio-sink.sh   (prints e.g. unix:/tmp/wax-null-audio.Ab12Cd/native)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
if ! command -v pulseaudio > /dev/null; then
  if [ -z "${CI:-}" ]; then
    echo "null-audio-sink.sh: pulseaudio is not installed" >&2
    exit 1
  fi
  "$here/apt-install.sh" pulseaudio >&2
fi

# Its own runtime directory: a daemon already running for this user keeps
# its pid file and socket in the default one, and would refuse a second.
dir=$(mktemp -d "${TMPDIR:-/tmp}/wax-null-audio.XXXXXX")
PULSE_RUNTIME_PATH=$dir pulseaudio -n --daemonize --exit-idle-time=-1 \
  --load="module-native-protocol-unix socket=$dir/native auth-anonymous=1" \
  --load="module-null-sink sink_name=wax-null" >&2
echo "unix:$dir/native"
