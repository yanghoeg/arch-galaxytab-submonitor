#!/usr/bin/env bash
# Park and unpark the virtual output.
#
# drm.edid_firmware + video=<connector>:e force the connector on for the whole
# uptime -- that is the point of them, the tablet has no way to assert hotplug.
# The cost is that KWin sees a permanently "connected" 2960x1848 screen whether
# or not a tablet is anywhere near it, and puts it at 0,0: on top of whatever
# real monitor is already there.
#
# Two overlapping outputs are not a drawing bug, they are a geometry bug. KWin
# assigns each window to one output and maximises it into that output's
# rectangle. Windows that land on the virtual one fill only its area and look
# like maximise is broken. Measured on a 5120x2880 panel at scale 2.5:
# "maximised" windows came out 1480x924 inside a 2048x1152 desktop.
#
# So the virtual output is enabled only for the length of a tablet session, and
# always placed past the right edge of the real outputs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

CONNECTOR="HDMI-A-1"
SCALE=2
# How long to keep insisting. `off` runs at session start, racing KWin's own
# restore of the layout it saved last time, so one successful call is not proof:
# re-check and repeat.
ATTEMPTS=5
INTERVAL=2

usage() {
  cat <<USAGE
arch-galaxytab-submonitor virtual output control

Usage: $(basename "$0") <on|off|status> [OPTIONS]

  on       Enable the output and place it to the right of every real screen
  off      Disable it, and keep checking that it stayed disabled
  status   Report the current state; exit 1 if it overlaps a real screen

Options:
  --connector <name>   DRM connector name  (default: HDMI-A-1)
  --scale <factor>     Scale to apply if the output comes up at 1  (default: 2)
  --attempts <n>       Retries for 'off'  (default: 5)
  -h, --help           Show this help
USAGE
}

# ── Reading the layout ────────────────────────────────────────────────────────

# One line per output: NAME STATE X,Y WxH
outputs_table() {
  kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
    /^Output:/ { if (name != "") print name, state, geom; name=$3; state="?"; geom="0,0 0x0"; next }
    /^[[:space:]]*enabled[[:space:]]*$/  { state="enabled";  next }
    /^[[:space:]]*disabled[[:space:]]*$/ { state="disabled"; next }
    /^[[:space:]]*Geometry:/             { geom=$2" "$3;     next }
    END { if (name != "") print name, state, geom }
  '
}

field_of() { outputs_table | awk -v n="$1" -v f="$2" '$1 == n { print $f }'; }
state_of() { field_of "$1" 2; }

scale_of() {
  kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
    | awk -v c="$1" '$1 == "Output:" { f = ($3 == c) } f && /Scale:/ { print $2; exit }'
}

mode_of() {
  local dir
  dir=$(echo /sys/class/drm/card*-"$1" | cut -d' ' -f1)
  head -1 "$dir/modes" 2>/dev/null
}

# Rightmost logical x any *other* enabled output reaches. That is where the
# virtual one goes: adjacent, so KWin does not renormalise it back over a
# neighbour, and past everything, so no window lands on it by accident.
right_edge_beyond() {
  outputs_table | awk -v skip="$1" '
    $1 != skip && $2 == "enabled" {
      split($3, p, ","); split($4, s, "x")
      if (p[1] + s[1] > max) max = p[1] + s[1]
    }
    END { print max + 0 }
  '
}

# Names of enabled outputs whose rectangle intersects this one.
overlaps_of() {
  outputs_table | awk -v me="$1" '
    { split($3, p, ","); split($4, s, "x")
      if ($1 == me) { found = 1; mx = p[1]; my = p[2]; mw = s[1]; mh = s[2] }
      else if ($2 == "enabled") { n++; nm[n] = $1; ox[n] = p[1]; oy[n] = p[2]; ow[n] = s[1]; oh[n] = s[2] } }
    END {
      if (!found) exit 0
      for (i = 1; i <= n; i++)
        if (mx < ox[i] + ow[i] && ox[i] < mx + mw && my < oy[i] + oh[i] && oy[i] < my + mh) print nm[i]
    }
  '
}

# kscreen-doctor answers over D-Bus, so at session start it can be up before
# KWin is ready to describe its outputs. Wait for the connector to appear rather
# than guessing a sleep.
wait_for_kwin() {
  local _
  for _ in $(seq 1 30); do
    [[ -n "$(state_of "$CONNECTOR")" ]] && return 0
    sleep 1
  done
  return 1
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_on() {
  local dir
  dir=$(echo /sys/class/drm/card*-"$CONNECTOR" | cut -d' ' -f1)
  if [[ ! -d "$dir" ]]; then
    echo "connector $CONNECTOR not found — run ./scripts/verify.sh"; return 1
  elif [[ "$(cat "$dir/status" 2>/dev/null)" != "connected" ]]; then
    echo "$CONNECTOR is not connected — the kernel parameters did not take, run ./scripts/verify.sh"; return 1
  fi
  wait_for_kwin || { echo "kscreen-doctor cannot see $CONNECTOR — is this a Plasma session?"; return 1; }

  local x ops=()
  x=$(right_edge_beyond "$CONNECTOR")
  ops+=("output.${CONNECTOR}.enable" "output.${CONNECTOR}.position.${x},0")
  # Only when it comes up at 1. A scale you picked by hand is yours to keep.
  [[ "$(scale_of "$CONNECTOR")" == "1" ]] && ops+=("output.${CONNECTOR}.scale.${SCALE}")

  if ! kscreen-doctor "${ops[@]}" >/dev/null 2>&1; then
    echo "kscreen-doctor rejected: ${ops[*]}"; return 1
  fi

  local clash
  clash=$(overlaps_of "$CONNECTOR" | paste -sd, -)
  if [[ -n "$clash" ]]; then
    echo "enabled but still overlapping $clash — windows there will not maximise correctly"; return 1
  fi
  echo "$(mode_of "$CONNECTOR"), scale $(scale_of "$CONNECTOR") at $(field_of "$CONNECTOR" 3)"
}

cmd_off() {
  wait_for_kwin || { echo "kscreen-doctor cannot see $CONNECTOR — is this a Plasma session?"; return 1; }
  local _
  for _ in $(seq 1 "$ATTEMPTS"); do
    [[ "$(state_of "$CONNECTOR")" == "disabled" ]] && { echo "parked (disabled)"; return 0; }
    kscreen-doctor "output.${CONNECTOR}.disable" >/dev/null 2>&1
    sleep "$INTERVAL"
  done
  if [[ "$(state_of "$CONNECTOR")" == "disabled" ]]; then
    echo "parked (disabled)"; return 0
  fi
  echo "still enabled after $ATTEMPTS attempts — something is re-enabling it"; return 1
}

cmd_status() {
  local state clash
  state=$(state_of "$CONNECTOR")
  [[ -z "$state" ]] && { echo "$CONNECTOR: unknown to kscreen-doctor"; return 1; }
  if [[ "$state" == "disabled" ]]; then
    echo "parked (disabled)"; return 0
  fi
  clash=$(overlaps_of "$CONNECTOR" | paste -sd, -)
  if [[ -n "$clash" ]]; then
    echo "$(mode_of "$CONNECTOR"), scale $(scale_of "$CONNECTOR") at $(field_of "$CONNECTOR" 3) — OVERLAPS $clash"; return 1
  fi
  echo "$(mode_of "$CONNECTOR"), scale $(scale_of "$CONNECTOR") at $(field_of "$CONNECTOR" 3)"
}

# ── CLI ───────────────────────────────────────────────────────────────────────

[[ $# -eq 0 ]] && { usage >&2; exit 1; }
ACTION="$1"; shift
while [[ $# -gt 0 ]]; do
  case $1 in
    --connector) validate_connector_name "${2:-}"; CONNECTOR="$2"; shift ;;
    --scale)     [[ "${2:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "Invalid scale: '${2:-}'"; SCALE="$2"; shift ;;
    --attempts)  [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Invalid attempt count: '${2:-}'"; ATTEMPTS="$2"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

command -v kscreen-doctor >/dev/null || die "kscreen-doctor not found (package: libkscreen / kscreen)"

case "$ACTION" in
  on)     cmd_on ;;
  off)    cmd_off ;;
  status) cmd_status ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown action: $ACTION" >&2; usage >&2; exit 1 ;;
esac
