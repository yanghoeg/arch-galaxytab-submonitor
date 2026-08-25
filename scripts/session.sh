#!/usr/bin/env bash
# Day-to-day launcher: start Sunshine and answer "can I connect from the tablet
# right now?" before you go and find out the hard way.
#
# This is deliberately NOT install.sh. The installer rewrites the bootloader
# entry and can rebuild the initramfs; it has no business running every time you
# want to use the second screen. The virtual output itself needs nothing here --
# it comes up from the kernel command line at boot.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

EDID_CONNECTOR="HDMI-A-1"
SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"
NO_START=false

usage() {
  cat <<USAGE
arch-galaxytab-submonitor session check

Starts Sunshine if it is not running, then reports whether everything the
tablet needs is in place. Changes nothing else.

Usage: $(basename "$0") [OPTIONS]

Options:
  --no-start           Only report; do not start Sunshine
  --connector <name>   DRM connector name  (default: HDMI-A-1)
  -h, --help           Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-start)  NO_START=true ;;
    --connector) validate_connector_name "${2:-}"; EDID_CONNECTOR="$2"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

N_BAD=0
row()  { printf "  %-16s %s\n" "$1" "$2"; }
bad()  { printf "  %-16s %s\n" "$1" "$2"; N_BAD=$((N_BAD + 1)); }

log_header "arch-galaxytab-submonitor session"
echo

# ── The virtual output ────────────────────────────────────────────────────────
CONNECTOR_DIR=$(echo /sys/class/drm/card*-"${EDID_CONNECTOR}" | cut -d' ' -f1)
if [[ ! -d "$CONNECTOR_DIR" ]]; then
  bad "virtual output" "connector ${EDID_CONNECTOR} not found"
elif [[ "$(cat "$CONNECTOR_DIR/status" 2>/dev/null)" != "connected" ]]; then
  bad "virtual output" "not connected — run ./scripts/verify.sh"
else
  mode=$(head -1 "$CONNECTOR_DIR/modes" 2>/dev/null)
  scale=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
          | awk -v c="$EDID_CONNECTOR" '$0 ~ c {f=1} f && /Scale:/ {print $2; exit}')
  if [[ "$scale" == "1" ]]; then
    # Not fatal, but at scale 1 the desktop is unusably small on a tablet.
    bad "virtual output" "${mode:-?} at scale 1 — text will be half size, try: kscreen-doctor output.${EDID_CONNECTOR}.scale.2"
  else
    row "virtual output" "${mode:-?}${scale:+, scale $scale}"
  fi
fi

# ── Sunshine ──────────────────────────────────────────────────────────────────
was=$(systemctl --user is-active "$SUNSHINE_UNIT" 2>/dev/null)
if [[ "$was" != "active" ]] && [[ "$NO_START" == "false" ]]; then
  systemctl --user start "$SUNSHINE_UNIT" 2>/dev/null
  for _ in $(seq 1 400); do
    [[ "$(systemctl --user is-active "$SUNSHINE_UNIT" 2>/dev/null)" == "active" ]] && break
  done
fi
now=$(systemctl --user is-active "$SUNSHINE_UNIT" 2>/dev/null)
if [[ "$now" == "active" ]]; then
  row "sunshine" "$([[ "$was" == "active" ]] && echo "already running" || echo "started (was $was)")"
else
  bad "sunshine" "$now — journalctl --user -u $SUNSHINE_UNIT"
fi

# ── What it will capture, and with what ───────────────────────────────────────
conf="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf"
target=$(sed -n 's/^[[:space:]]*output_name[[:space:]]*=[[:space:]]*//p' "$conf" 2>/dev/null | tail -1)
# Sunshine re-enumerates on every start and every stream, so the journal holds
# many copies. Take the last full pass: as many trailing lines as there are
# distinct monitors, which is the ordering output_name indexes into.
all_monitors=$(journalctl --user -u "$SUNSHINE_UNIT" --no-pager 2>/dev/null \
               | sed -n 's/.*\[wayland\] Found monitor: //p')
n_monitors=$(sort -u <<<"$all_monitors" | grep -c .)
monitors=$(tail -n "${n_monitors:-0}" <<<"$all_monitors")
if [[ -z "$target" ]]; then
  bad "capture target" "output_name unset — Sunshine will grab its default display"
else
  name=$(sed -n "$((target + 1))p" <<<"$monitors")
  row "capture target" "output_name = $target${name:+  -> $name}"
fi

encoder=$(journalctl --user -u "$SUNSHINE_UNIT" --no-pager 2>/dev/null \
          | sed -n 's/.*Found HEVC encoder: //p' | tail -1)
if [[ -z "$encoder" ]]; then
  row "encoder" "not probed yet (probes on first connection)"
elif [[ "$encoder" == *software* ]]; then
  bad "encoder" "$encoder — see docs/troubleshooting.md"
else
  row "encoder" "$encoder"
fi

# ── The path the tablet takes in ──────────────────────────────────────────────
if ! systemctl is-active --quiet nftables 2>/dev/null; then
  row "firewall" "nftables not active — nothing is being filtered"
elif sudo -n nft list chain inet filter input 2>/dev/null | grep -q 47989; then
  row "firewall" "active, Sunshine ports open"
else
  bad "firewall" "active but no rule for Sunshine's ports — the tablet will be dropped"
fi

link=$(ip -br addr 2>/dev/null | awk '/^enp[0-9a-z]*u[0-9]/ && $2!="DOWN" {print $1" "$3; exit}')
if [[ -n "$link" ]]; then
  row "tethering" "$link"
else
  bad "tethering" "no USB tethering interface is up — enable it on the tablet"
fi

if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
  if timeout 5 avahi-browse -atp 2>/dev/null | grep -q _nvstream._tcp; then
    row "discovery" "advertised over mDNS"
  else
    row "discovery" "avahi running but Sunshine is not advertising yet"
  fi
else
  row "discovery" "avahi-daemon inactive — add the host by address in Moonlight"
fi

echo
if [[ $N_BAD -eq 0 ]]; then
  log_header "Ready — open Moonlight on the tablet"
else
  log_header "$N_BAD problem(s) above"
  exit 1
fi
