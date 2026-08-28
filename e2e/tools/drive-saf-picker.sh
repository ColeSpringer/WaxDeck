#!/usr/bin/env bash
# Taps the Android system tree picker through to the probe folder, from
# outside the app.
#
# integration_test/saf_channel_test.dart opens ACTION_OPEN_DOCUMENT_TREE
# and waits for a grant. Nothing inside that process can answer: the
# picker belongs to DocumentsUI, and `flutter test` already holds the
# device's one instrumentation slot, so androidx.test.uiautomator cannot
# run beside it. The taps come over adb instead, beside the test rather
# than inside it - which is what the test's header has always assumed.
#
#   drive-saf-picker.sh [serial]
#
# Idempotent by construction rather than a fixed sequence: each pass
# dumps the window, taps the most specific thing it recognises, and
# looks again. Which root DocumentsUI opens at, and whether the drawer
# is already showing, are then things the loop discovers instead of
# things it assumes - and a tap that changed nothing is just another
# pass.
#
# The tap ladder is keyed on DocumentsUI's English labels, which is
# what the locale check below is for: an emulator in another language
# would otherwise fail as an inscrutable timeout. Label drift between
# DocumentsUI versions is a known risk of driving it this way, and the
# ladder answers it only by trying several spellings of each step.
#
# Exits 0 when the picker is gone (granted, or dismissed by someone
# else), 1 if it never appeared or never closed.
set -euo pipefail

SERIAL="${1:-emulator-5554}"

# Matched as a substring of the package name: AOSP images ship
# com.android.documentsui and google_apis images ship
# com.google.android.documentsui, and the picker is the same activity
# in both.
PICKER_PKG="android.documentsui"

# Two budgets, because the two waits are nothing alike. The picker
# cannot open until `flutter test` has built and installed the app,
# which on a cold CI runner is minutes; driving it once it is up is
# seconds, and the test's own pick budget is two minutes, so this
# gives up first and a picker that drifted reads as a driver failure
# rather than as the channel timing out.
WAIT="${SAF_PICKER_WAIT:-600}"
TIMEOUT="${SAF_PICKER_TIMEOUT:-90}"

DUMP=""
DUMP_PATH=/data/local/tmp/wax-picker.xml

adb_() { adb -s "$SERIAL" "$@"; }

# The window's view hierarchy, one node per line; non-zero when the
# device would not give one. Written under /data/local/tmp rather than
# /sdcard, because the picker browses /sdcard and a dump file left in
# the tree would show up in the listing being driven.
#
# Removed before every dump and required to be non-empty afterwards:
# uiautomator can decline a dump while the UI animates, sometimes
# without failing, and a stale file served as this pass's hierarchy
# would have the loop tapping coordinates from a screen that is gone.
dump() {
  local xml
  adb_ shell rm -f "$DUMP_PATH" >/dev/null 2>&1 || true
  adb_ shell uiautomator dump "$DUMP_PATH" >/dev/null 2>&1 || return 1
  xml="$(adb_ exec-out cat "$DUMP_PATH" 2>/dev/null | tr '>' '\n')"
  [ -n "$xml" ] || return 1
  printf '%s\n' "$xml"
}

# The centre of the first visible node whose XML carries $1, as "x y".
# Zero-area nodes are skipped: DocumentsUI keeps collapsed views in the
# tree, and tapping one is a pass that can never make progress.
node_center() {
  local needle="$1" line x1 y1 x2 y2
  while IFS= read -r line; do
    [[ "$line" == *"$needle"* ]] || continue
    [[ "$line" =~ bounds=\"\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]\" ]] || continue
    x1="${BASH_REMATCH[1]}"
    y1="${BASH_REMATCH[2]}"
    x2="${BASH_REMATCH[3]}"
    y2="${BASH_REMATCH[4]}"
    ((x2 > x1 && y2 > y1)) || continue
    echo "$(((x1 + x2) / 2)) $(((y1 + y2) / 2))"
    return 0
  done <<<"$DUMP"
  return 1
}

# Taps the first of the given XML fragments that is on screen.
tap_any() {
  local needle point
  for needle in "$@"; do
    if point="$(node_center "$needle")"; then
      echo "drive-saf-picker: tap $needle at $point"
      # shellcheck disable=SC2086
      adb_ shell input tap $point
      return 0
    fi
  done
  return 1
}

# Whether $1 is anywhere in the hierarchy, tappable or not.
showing() { [[ "$DUMP" == *"$1"* ]]; }

# The emulator's primary storage reads as the device model in the roots
# drawer; older builds and some images call it "Internal storage". Not
# fatal when it cannot be read - the loop has other ways in, and under
# `pipefail` an unanswered adb would otherwise end the driver here.
model="$(adb_ shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"

# Named before the ladder can fail on it: every step below matches an
# English label, so a device in another language is a driver problem to
# say out loud rather than a two-minute wait ending in nothing.
locale="$(adb_ shell getprop persist.sys.locale 2>/dev/null | tr -d '\r' || true)"
[ -n "$locale" ] ||
  locale="$(adb_ shell getprop ro.product.locale 2>/dev/null | tr -d '\r' || true)"
case "$locale" in
en* | '') ;;
*)
  echo "drive-saf-picker: the tap ladder needs an English device; this one is $locale" >&2
  exit 1
  ;;
esac

deadline=$(($(date +%s) + WAIT))
appeared=0
while (($(date +%s) < deadline)); do
  if ! DUMP="$(dump)"; then
    # A refused dump says nothing about what is on screen, and reading
    # it as "the picker closed" would end the driver with DocumentsUI
    # still up and nobody left to tap it.
    sleep 1
    continue
  fi
  if ! showing "$PICKER_PKG"; then
    if ((appeared)); then
      echo "drive-saf-picker: the picker is gone"
      exit 0
    fi
    sleep 1
    continue
  fi
  if ((!appeared)); then
    echo "drive-saf-picker: the picker is up"
    appeared=1
    deadline=$(($(date +%s) + TIMEOUT))
  fi

  # Most specific first. The confirmation dialog's own button before
  # anything behind it, and exact text values throughout, so "Allow"
  # cannot match "Don't allow".
  if tap_any 'text="Allow"' 'text="ALLOW"'; then
    sleep 1
    continue
  fi
  # Disc1 exists only inside the probe folder, so it is what says the
  # picker is standing in the directory to grant - "use this folder"
  # is offered for every directory, including the wrong ones.
  if showing 'text="Disc1"' &&
    tap_any 'text="USE THIS FOLDER"' 'text="Use this folder"'; then
    sleep 1
    continue
  fi
  if tap_any 'text="WaxProbe"' 'text="Music"'; then
    sleep 1
    continue
  fi
  if [ -n "$model" ] && tap_any "text=\"$model\""; then
    sleep 1
    continue
  fi
  if tap_any 'text="Internal storage"' 'content-desc="Show roots"'; then
    sleep 1
    continue
  fi
  echo "drive-saf-picker: nothing recognised on screen; looking again"
  sleep 1
done

if ((appeared)); then
  echo "drive-saf-picker: the picker was up but never closed (${TIMEOUT}s)" >&2
else
  echo "drive-saf-picker: the picker never opened (${WAIT}s)" >&2
fi
exit 1
