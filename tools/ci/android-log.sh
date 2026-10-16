# shellcheck shell=bash
# The device-log facts the Android runner reads in more than one place,
# defined once so that its retry decision and lost-android.sh can never
# come to disagree about what a dropped transport looks like. Sourced;
# WAX_LOGCAT names the log the runner collects.

# What the guest's adbd logs when its host transport dies: the line
# every observed drop left.
ADBD_DROP_RE=' adbd +: .*(connection terminated|destroying transport)'

# Whether WAX_LOGCAT, from line $1 on, holds a transport drop. Given a
# port as $2, only a drop after the app last announced its VM service on
# that port counts - the drop that takes the tool's link to the app with
# it. One pass that reads to the end: a reader that leaves at its first
# match kills the writer with SIGPIPE, which pipefail reports as none.
logcat_dropped() {
  local from=$1 port=${2:-}
  tail -n "+$from" "$WAX_LOGCAT" 2> /dev/null | awk -v port="$port" -v re="$ADBD_DROP_RE" '
    port != "" && index($0, "listening on http://127.0.0.1:" port "/") { armed = 1; dropped = 0; next }
    (port == "" || armed) && $0 ~ re { dropped = 1 }
    END { exit !dropped }'
}

# The tool's forward to the app's VM service, "<host-port> <device-port>",
# from its verbose trace $1; nothing when it has made none.
tool_forward() {
  local line
  line=$(grep -oE 'Forwarded host port [0-9]+ to device port [0-9]+' "$1" 2> /dev/null | tail -n 1 || true)
  [ -z "$line" ] || sed -E 's/.* ([0-9]+) to device port ([0-9]+)$/\1 \2/' <<< "$line"
}
