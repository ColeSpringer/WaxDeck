#!/usr/bin/env bash
# The waxdeck/share channel test with its chooser handled from outside.
#
#   run-share-probe.sh [serial]
#
# Runs integration_test/share_channel_test.dart, which shares a card twice.
# Each share opens the system chooser over the app; this sees it take the
# focus, checks the chooser holds a read grant on the card the app wrote
# (the grant a receiving app reads the image through), and dismisses it
# with BACK, which is what lets the test go on. Both shares must be seen
# and granted.
#
# On failure it captures what the device looked like - a screenshot, the
# view hierarchy, and the activity and URI grant dumps - into
# $SHARE_ARTIFACTS, and a chooser without its grant is captured as it
# stands, into chooser-<n>/: by the time `flutter test` returns it has
# uninstalled the app, and the grant with it. The directory is emptied
# first, so a retry never uploads the previous attempt's device as
# evidence for this one.
set -euo pipefail

SERIAL="${1:-emulator-5554}"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "$TOOLS/../../app/app" && pwd)"
ARTIFACTS="${SHARE_ARTIFACTS:-${RUNNER_TEMP:-/tmp}/wax-share-artifacts}"
CARD="content://com.colespringer.waxdeck.shares/share-cards/wax-share-probe.png"
SHARES=2

test_pid=""
capture() {
  local dir="$1"
  mkdir -p "$dir"
  adb -s "$SERIAL" exec-out screencap -p >"$dir/device.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /data/local/tmp/wax-failure.xml \
    >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /data/local/tmp/wax-failure.xml \
    >"$dir/device.xml" 2>/dev/null || true
  adb -s "$SERIAL" shell dumpsys activity activities >"$dir/activities.txt" 2>/dev/null || true
  adb -s "$SERIAL" shell dumpsys activity permissions >"$dir/uri-grants.txt" 2>/dev/null || true
  echo "run-share-probe: captured the device into $dir" >&2
}

cleanup() {
  local status=$?
  trap - EXIT
  if [ -n "$test_pid" ]; then
    kill "$test_pid" 2>/dev/null || true
  fi
  if [ "$status" -ne 0 ]; then
    capture "$ARTIFACTS"
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$ARTIFACTS"

# The default display's focused window and focused activity, a line each.
# From `dumpsys window displays`: `dumpsys window windows` no longer
# carries the focus lines (API 35 prints none), and a read that finds
# nothing looks exactly like a chooser that never opened. Read whole, then
# matched: a `grep -q` in a pipeline under pipefail reads the producer's
# SIGPIPE as the pipeline failing.
focus() {
  local displays
  displays=$(adb -s "$SERIAL" shell dumpsys window displays 2>/dev/null || true)
  printf '%s\n' "$displays" | awk '
    { sub(/\r$/, "") }
    /^  Display: mDisplayId=/ { on = ($0 ~ /mDisplayId=0( |$)/) }
    on && sub(/^  mCurrentFocus=/, "") { window = $0 }
    on && sub(/^  mFocusedApp=/, "") { app = $0 }
    END { print window; print app }'
}

# Whether the chooser activity $1 holds a read grant on the card. By
# owner, not by the URI alone: both shares grant the same URI, and the
# first chooser's grant outlives it long enough to stand in for a second
# that granted nothing.
granted() {
  local grants
  grants=$(adb -s "$SERIAL" shell dumpsys activity permissions 2>/dev/null || true)
  printf '%s\n' "$grants" | awk -v card="$CARD" -v owner="* $1 " '
    index($0, card) { inside = 1; reading = 0; next }
    inside && /UriPermission\{|^  \* UID/ { inside = 0 }
    inside && /readOwners:/ { reading = 1; next }
    inside && /writeOwners:/ { reading = 0; next }
    inside && reading && index($0, owner) { found = 1 }
    END { exit !found }'
}

# Answers a system error dialog, an app not responding or one that
# stopped, standing over the chooser: it holds the focus, so BACK would
# go to it. Wait before Close, as drive-saf-picker.sh does.
answer_error_dialog() {
  local xml id line
  adb -s "$SERIAL" shell uiautomator dump /data/local/tmp/wax-share-dialog.xml \
    >/dev/null 2>&1 || return 1
  xml=$(adb -s "$SERIAL" exec-out cat /data/local/tmp/wax-share-dialog.xml 2>/dev/null |
    tr '>' '\n' || true)
  for id in aerr_wait aerr_close; do
    while IFS= read -r line; do
      [[ $line == *"resource-id=\"android:id/$id\""* ]] || continue
      [[ $line =~ bounds=\"\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]\" ]] || continue
      echo "run-share-probe: answering the dialog over the chooser ($id)" >&2
      adb -s "$SERIAL" shell input tap \
        $(((BASH_REMATCH[1] + BASH_REMATCH[3]) / 2)) $(((BASH_REMATCH[2] + BASH_REMATCH[4]) / 2))
      return 0
    done <<<"$xml"
  done
  return 1
}

cd "$APP"
# The reporter flags the CI runner asks for, split on purpose; a local run
# leaves them unset.
# shellcheck disable=SC2086
flutter test ${WAX_FLUTTER_TEST_FLAGS:-} integration_test/share_channel_test.dart -d "$SERIAL" &
test_pid=$!

seen=0
grants=0
# Every change of focus is said, so a run that never sees a chooser says
# what held the screen instead - or that nothing could be read.
said=""
# A chooser is known by its activity, which outlives a rebuilt window,
# and each one counts once. It gets BACK when its own window holds the
# focus, and again only if it still stands ten seconds on: a second press
# sent as it closes lands on the app and backs the test out.
counted=" "
pressed=""
pressed_at=0
answered_at=0
while kill -0 "$test_pid" 2>/dev/null; do
  window=""
  app=""
  { IFS= read -r window; IFS= read -r app; } < <(focus) || true
  if [ "$window|$app" != "$said" ]; then
    echo "run-share-probe: focus is ${window:-unreadable}, in ${app:-unreadable}" >&2
    said="$window|$app"
  fi
  if [[ $app == *ChooserActivity* ]]; then
    chooser=${app%% *}
    if [[ $counted != *" $chooser "* ]]; then
      counted="$counted$chooser "
      seen=$((seen + 1))
      if granted "$chooser"; then
        grants=$((grants + 1))
      else
        echo "run-share-probe: chooser $seen holds no grant on $CARD" >&2
        capture "$ARTIFACTS/chooser-$seen"
      fi
    fi
    if [[ $window == *ChooserActivity* ]]; then
      if [ "$chooser" != "$pressed" ] || ((SECONDS - pressed_at >= 10)); then
        adb -s "$SERIAL" shell input keyevent KEYCODE_BACK
        pressed=$chooser
        pressed_at=$SECONDS
      fi
    elif [ -n "$window" ] && [ "$window" != null ] && ((SECONDS - answered_at >= 5)); then
      answered_at=$SECONDS
      answer_error_dialog || true
    fi
  fi
  sleep 0.5
done

status=0
wait "$test_pid" || status=$?
test_pid=""
if [ "$seen" -ne "$SHARES" ]; then
  echo "run-share-probe: saw $seen of $SHARES choosers open" >&2
  [ "$status" -ne 0 ] || status=1
fi
if [ "$grants" -ne "$seen" ]; then
  [ "$status" -ne 0 ] || status=1
fi
exit "$status"
