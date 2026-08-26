#!/usr/bin/env bash
# Read-only post-install check. Answers "did the virtual display actually come
# up, and is the input path wired?" Makes no changes of any kind.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

EDID_CONNECTOR="HDMI-A-1"
EDID_PROFILE="tabs9_60hz"
SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"

usage() {
  cat <<USAGE
arch-galaxytab-submonitor verifier (read-only)

Usage: $(basename "$0") [OPTIONS]

Options:
  --connector <name>   DRM connector name   (default: HDMI-A-1)
  --profile   <name>   EDID mode profile    (default: tabs9_60hz)
  -h, --help           Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --connector) validate_connector_name "${2:-}"; EDID_CONNECTOR="$2"; shift ;;
    --profile)   validate_adapter_name "profile" "${2:-}"; EDID_PROFILE="$2"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

N_PASS=0; N_FAIL=0; N_WARN=0
ok()   { echo "  [ ok ] $*"; N_PASS=$((N_PASS + 1)); }
bad()  { echo "  [FAIL] $*"; N_FAIL=$((N_FAIL + 1)); }
soft() { echo "  [warn] $*"; N_WARN=$((N_WARN + 1)); }

EDID_BLOB="/usr/lib/firmware/edid/${EDID_PROFILE}.bin"
# Filled in from the installed blob below, so the connector check compares
# against what is actually deployed rather than a hardcoded resolution.
EXPECTED_RES=""
CONNECTOR_DIR=$(echo /sys/class/drm/card*-"${EDID_CONNECTOR}" | cut -d' ' -f1)

log_header "arch-galaxytab-submonitor verify"
log_kv "DRM connector" "$EDID_CONNECTOR"
log_kv "EDID profile"  "$EDID_PROFILE"

log_step "EDID firmware"
if [[ -f "$EDID_BLOB" ]]; then
  ok "blob installed: $EDID_BLOB ($(stat -c%s "$EDID_BLOB") bytes)"
  if command -v edid-decode &>/dev/null; then
    # edid-decode insists the HDMI spec wants EDID 1.3 whenever an HDMI VSDB is
    # present. Dropping to 1.3 introduces two worse failures, so that one line
    # is expected; anything else is a real problem.
    edid_failures=$(edid-decode --check "$EDID_BLOB" 2>&1 \
      | sed -n '/Failures:/,/^EDID conformity/p' \
      | grep -E "^\\s+\\S" | grep -v "requires EDID 1.3 instead of 1.4" || true)
    if [[ -z "$edid_failures" ]]; then
      ok "edid-decode: no unexpected conformity failures"
    else
      bad "edid-decode conformity failures:"
      echo "$edid_failures" | sed 's/^/         /'
    fi
    decoded=$(edid-decode "$EDID_BLOB" 2>/dev/null)
    EXPECTED_RES=$(awk '/DTD 1:/ { print $3; exit }' <<<"$decoded")
    [[ -n "$EXPECTED_RES" ]] && ok "blob advertises: $EXPECTED_RES"

    # Without a CTA-861 block carrying the HDMI OUI the kernel classifies the
    # sink as DVI and prunes anything above 165 MHz, so this is the single
    # check that decides whether the mode survives at all.
    if grep -q "OUI 00-0C-03" <<<"$decoded"; then
      ok "CTA-861 block present with HDMI VSDB (OUI 00-0C-03)"
    else
      bad "no HDMI VSDB — the sink will be treated as DVI and capped at 165 MHz"
    fi

    clock_mhz=$(awk '/DTD 1:/ { print $9; exit }' <<<"$decoded")
    if [[ -n "$clock_mhz" ]] && (( $(printf '%.0f' "$clock_mhz") > 340 )); then
      if grep -q "OUI C4-5D-D8" <<<"$decoded"; then
        ok "HDMI Forum VSDB present (needed above 340 MHz; blob is ${clock_mhz} MHz)"
      else
        bad "${clock_mhz} MHz exceeds 340 MHz but no HDMI Forum VSDB is declared"
      fi
    fi
  else
    soft "edid-decode not installed — cannot validate the blob (pacman -S edid-decode)"
  fi
else
  bad "blob missing: $EDID_BLOB"
fi

log_step "Kernel command line"
for param in \
    "drm.edid_firmware=${EDID_CONNECTOR}:edid/${EDID_PROFILE}.bin" \
    "video=${EDID_CONNECTOR}:e"; do
  if grep -qF "$param" /proc/cmdline; then
    ok "active: $param"
  else
    bad "not on the running kernel command line: $param  (reboot pending?)"
  fi
done

log_step "Initramfs"
# /boot is normally root-only, so even this read-only check needs sudo. Without
# it we cannot tell "absent" from "unreadable", and must not claim the former.
initramfs_tool=""
command -v lsinitcpio &>/dev/null && initramfs_tool=lsinitcpio
[[ -z "$initramfs_tool" ]] && command -v lsinitrd &>/dev/null && initramfs_tool=lsinitrd

if [[ -z "$initramfs_tool" ]]; then
  soft "no initramfs inspection tool available — skipped"
elif ! sudo -n true 2>/dev/null; then
  soft "cannot read /boot without root — re-run where sudo works to check this"
else
  initramfs_hit=0
  initramfs_seen=0
  while IFS= read -r img; do
    initramfs_seen=$((initramfs_seen + 1))
    if sudo -n "$initramfs_tool" "$img" 2>/dev/null | grep -q "${EDID_PROFILE}.bin"; then
      ok "EDID blob is inside $(basename "$img")"
      initramfs_hit=1
    fi
  done < <(sudo -n find /boot -maxdepth 1 -name 'initramfs-*.img' 2>/dev/null)

  if [[ $initramfs_seen -eq 0 ]]; then
    soft "no initramfs images found under /boot"
  elif [[ $initramfs_hit -eq 0 ]]; then
    bad "EDID blob is in none of the $initramfs_seen initramfs image(s) under /boot"
  fi
fi

log_step "DRM connector"
if [[ -d "$CONNECTOR_DIR" ]]; then
  ok "connector present: $(basename "$CONNECTOR_DIR")"
  status=$(cat "$CONNECTOR_DIR/status" 2>/dev/null || echo unknown)
  if [[ "$status" == "connected" ]]; then
    ok "status: connected"
  else
    bad "status: $status  (the forced EDID has not taken effect)"
  fi
  # sysfs attributes always stat as 4096 bytes, so test the content, not -s.
  top_mode=$(head -1 "$CONNECTOR_DIR/modes" 2>/dev/null)
  if [[ -n "$top_mode" ]]; then
    ok "preferred mode: $top_mode"
    if [[ -z "$EXPECTED_RES" ]]; then
      soft "could not read the expected resolution from the blob — not compared"
    elif [[ "$top_mode" == "$EXPECTED_RES" ]]; then
      ok "preferred mode matches the installed blob"
    else
      bad "preferred mode is $top_mode, blob advertises $EXPECTED_RES"
    fi
  else
    bad "no modes listed for this connector"
  fi
else
  bad "connector not found: /sys/class/drm/card*-${EDID_CONNECTOR}"
fi

log_step "Sunshine"
if sunshine_bin=$(command -v sunshine 2>/dev/null); then
  ok "binary: $sunshine_bin"
  if command -v getcap &>/dev/null; then
    caps=$(getcap "$sunshine_bin" 2>/dev/null)
    if [[ "$caps" == *cap_sys_admin* ]]; then
      ok "capabilities: $caps"
    else
      bad "cap_sys_admin not set on $sunshine_bin"
    fi
  else
    soft "getcap not available — cannot check capabilities"
  fi
  sunshine_conf="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf"
  sunshine_output=$(sed -n 's/^[[:space:]]*output_name[[:space:]]*=[[:space:]]*//p' \
                    "$sunshine_conf" 2>/dev/null | tail -1)
  if [[ -n "$sunshine_output" ]]; then
    ok "capture target: output_name = $sunshine_output"
  else
    soft "output_name is unset — Sunshine captures its default display,"
    echo  "         usually the built-in panel rather than the virtual output"
  fi

  # Autostart and "is it running right now" are independent: --no-enable and a
  # manual systemctl --user disable both leave a perfectly usable service.
  unit_state=$(systemctl --user is-active "$SUNSHINE_UNIT" 2>/dev/null)
  if [[ "$unit_state" == "active" ]]; then
    ok "user service running"
  else
    bad "user service is $unit_state"
  fi
  if systemctl --user is-enabled "$SUNSHINE_UNIT" &>/dev/null; then
    ok "autostart enabled (graphical-session.target)"
  else
    soft "autostart is disabled — start it by hand, or re-run the installer"
  fi
else
  bad "sunshine binary not found"
fi

log_step "Screen layout"
OUTPUT_RESET_UNIT="tabdisp-virtual-output.service"
OUTPUT_RESET_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/${OUTPUT_RESET_UNIT}"
if [[ -f "$OUTPUT_RESET_PATH" ]]; then
  ok "login-time reset installed: $OUTPUT_RESET_UNIT"
  exec_line=$(sed -n 's/^ExecStart=//p' "$OUTPUT_RESET_PATH" | head -1)
  exec_bin=${exec_line%% *}
  if [[ ! -x "$exec_bin" ]]; then
    # The unit points into the checkout, so moving the repo silently breaks it.
    bad "its ExecStart is gone: $exec_bin  (re-run install.sh --apply from the new path)"
  elif systemctl --user is-enabled --quiet "$OUTPUT_RESET_UNIT" 2>/dev/null; then
    ok "enabled — the virtual output is parked at every login"
  else
    soft "installed but not enabled, so an untidy shutdown leaves the virtual"
    echo  "         output overlapping a real screen at the next login"
  fi
else
  soft "no login-time reset unit — install with install.sh --apply, or accept"
  echo  "         that a session ending badly leaves the outputs overlapping"
fi

# The failure this guards against, checked directly rather than inferred.
if layout=$("$SCRIPT_DIR/scripts/virtual-output.sh" status --connector "$EDID_CONNECTOR" 2>&1); then
  ok "virtual output: $layout"
else
  bad "virtual output: $layout"
fi

log_step "Input return path"
if getent group sunshine-uinput >/dev/null; then
  ok "group exists: sunshine-uinput"
  if id -nG "$USER" | grep -qw sunshine-uinput; then
    ok "$USER is in sunshine-uinput (active in this session)"
  elif getent group sunshine-uinput | grep -qw "$USER"; then
    soft "$USER is in sunshine-uinput but the session predates it — log out and back in"
  else
    bad "$USER is not a member of sunshine-uinput"
  fi
else
  bad "group sunshine-uinput does not exist"
fi

if [[ -f /etc/udev/rules.d/60-tabdisp-uinput.rules ]]; then
  ok "udev rule installed"
else
  bad "udev rule missing: /etc/udev/rules.d/60-tabdisp-uinput.rules"
fi

# Sunshine's own packaging ships a uaccess rule. When it is present the session
# user gets /dev/uinput through a logind ACL no matter what group we set, so
# report the effective posture instead of implying the group is a boundary.
if grep -rqs uaccess /usr/lib/udev/rules.d/60-sunshine.rules \
                     /etc/udev/rules.d/60-sunshine.rules; then
  soft "Sunshine's own 60-sunshine.rules grants uinput via uaccess, so the"
  echo  "         sunshine-uinput group is not an access boundary"
  echo  "         (see docs/troubleshooting.md)"
fi

if [[ -e /dev/uinput ]]; then
  ok "/dev/uinput: $(stat -c'%G %a' /dev/uinput)"
else
  bad "/dev/uinput does not exist (modprobe uinput)"
fi

echo
log_header "Summary"
log "$N_PASS passed, $N_FAIL failed, $N_WARN warnings"
[[ $N_FAIL -eq 0 ]] || exit 1
