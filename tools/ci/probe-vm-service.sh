#!/usr/bin/env bash
# Asks a Dart VM service what its isolates are doing, over plain HTTP.
#
#   probe-vm-service.sh <service-url> <out-dir> [label]
#
# The VM service answers JSON-RPC over HTTP GET as well as over its
# websocket - http://host:port/<token>/getVM - and DDS forwards the
# same form, so a hung app can be asked for its isolate list, each
# isolate's pause state, and a stack, with no debugger attached. The
# raw answers land under <out-dir> as <label>.*.json; a one-line digest
# per isolate goes to stdout. Exits non-zero only when the service did
# not answer at all.
set -uo pipefail

URL=${1:?usage: probe-vm-service.sh <service-url> <out-dir> [label]}
OUT=${2:?usage: probe-vm-service.sh <service-url> <out-dir> [label]}
LABEL=${3:-vm}
URL="${URL%/}/"
mkdir -p "$OUT"

get() {
  curl -sS -m 10 "$URL$1"
}

vm="$OUT/$LABEL.getVM.json"
if ! get getVM > "$vm" 2> "$OUT/$LABEL.getVM.err"; then
  echo "probe-vm-service: $URL did not answer getVM: $(head -c 200 "$OUT/$LABEL.getVM.err")"
  exit 1
fi
if ! jq -e '.result.isolates' "$vm" > /dev/null 2>&1; then
  echo "probe-vm-service: $URL answered getVM with: $(head -c 300 "$vm")"
  exit 1
fi
echo "probe-vm-service: $URL is pid $(jq -r '.result.pid' "$vm"), $(jq -r '.result.isolates | length' "$vm") isolate(s), $(jq -r '.result.version' "$vm" | cut -d' ' -f1-2)"

n=0
while read -r id; do
  n=$((n + 1))
  enc=$(printf '%s' "$id" | jq -sRr @uri)
  iso="$OUT/$LABEL.isolate-$n.json"
  stack="$OUT/$LABEL.stack-$n.json"
  get "getIsolate?isolateId=$enc" > "$iso" 2> /dev/null || true
  get "getStack?isolateId=$enc" > "$stack" 2> /dev/null || true
  name=$(jq -r '.result.name // "?"' "$iso" 2> /dev/null || echo '?')
  runnable=$(jq -r '.result.runnable // "?"' "$iso" 2> /dev/null || echo '?')
  pause=$(jq -r '.result.pauseEvent.kind // "?"' "$iso" 2> /dev/null || echo '?')
  frames=$(jq -r '[.result.frames[:6][]? | .function.name // .kind] | join(" < ")' "$stack" 2> /dev/null || true)
  echo "probe-vm-service:   $id $name runnable=$runnable pause=$pause${frames:+ stack: $frames}"
done < <(jq -r '.result.isolates[]?.id' "$vm")
