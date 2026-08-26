#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=true
BOOTLOADER_OVERRIDE=""
INITRAMFS_OVERRIDE=""
PKG_OVERRIDE=""
EDID_CONNECTOR="HDMI-A-1"
EDID_PROFILE="tabs9_60hz"
# The LizardByte packages ("sunshine" builds from source, "sunshine-bin" ships a
# prebuilt binary) install the same unit under a reverse-DNS name.
SUNSHINE_PKG="sunshine-bin"
SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"
# Empty means "leave Sunshine's capture target alone".
SUNSHINE_OUTPUT=""
# Autostart is the point of the project, but re-running --apply should not
# silently undo a deliberate "systemctl --user disable".
SUNSHINE_ENABLE=true
# A user unit that parks the virtual output at every login, so a session that
# ended with it still enabled cannot leave it overlapping a real screen.
OUTPUT_RESET_UNIT="tabdisp-virtual-output.service"
OUTPUT_RESET_ENABLE=true

# ── CLI ───────────────────────────────────────────────────────────────────────
usage() {
  cat <<USAGE
arch-galaxytab-submonitor installer

Usage: $(basename "$0") [OPTIONS]

Options:
  --apply                Apply changes (default: dry-run)
  --bootloader <name>    Override bootloader adapter  [systemd_boot | grub]
  --initramfs  <name>    Override initramfs adapter   [mkinitcpio | dracut]
  --pkg        <name>    Override package manager     [yay | paru | pacman]
  --connector  <name>    DRM connector name           (default: HDMI-A-1)
  --sunshine-pkg <name>  Sunshine package             (default: sunshine-bin)
  --sunshine-output <n>  Display index Sunshine captures. Without it Sunshine
                         keeps capturing the built-in panel, not the virtual
                         output. List candidates after the first run with:
                         journalctl --user -u <unit> | grep 'Found monitor'
  --no-enable            Start Sunshine without enabling autostart. By default
                         the service is enabled for the graphical session, so a
                         later --apply would otherwise re-enable it for you.
  --no-output-reset      Install the login-time "park the virtual output" unit
                         but leave it disabled. By default it is enabled, which
                         is what stops the virtual screen from coming back on
                         top of a real monitor after an untidy shutdown.
  --profile    <name>    EDID mode profile            (default: tabs9_60hz)
                         see: python3 edid/generate.py --help
  -h, --help             Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --apply)       DRY_RUN=false ;;
    --bootloader)  validate_adapter_name "bootloader" "${2:-}"; BOOTLOADER_OVERRIDE="$2"; shift ;;
    --initramfs)   validate_adapter_name "initramfs"  "${2:-}"; INITRAMFS_OVERRIDE="$2";  shift ;;
    --pkg)         validate_adapter_name "pkg"        "${2:-}"; PKG_OVERRIDE="$2";        shift ;;
    --profile)     validate_adapter_name "profile"    "${2:-}"; EDID_PROFILE="$2";        shift ;;
    --connector)   validate_connector_name "${2:-}";            EDID_CONNECTOR="$2";      shift ;;
    --sunshine-pkg) validate_pkg_name "${2:-}";                 SUNSHINE_PKG="$2";        shift ;;
    --sunshine-output) validate_output_name "${2:-}";           SUNSHINE_OUTPUT="$2";     shift ;;
    --no-enable)   SUNSHINE_ENABLE=false ;;
    --no-output-reset) OUTPUT_RESET_ENABLE=false ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# ── Detect the platform and load the matching adapters ────────────────────────
source "$SCRIPT_DIR/lib/bootstrap.sh"

# ── Load core ─────────────────────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/core.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
log_header "arch-galaxytab-submonitor"
log_kv "Mode"          "$(if $DRY_RUN; then echo 'dry-run  (--apply to make changes)'; else echo 'APPLY'; fi)"
log_kv "Bootloader"    "$BOOTLOADER"
log_kv "Initramfs"     "$INITRAMFS"
log_kv "Pkg manager"   "$PKG_MANAGER"
log_kv "DRM connector" "$EDID_CONNECTOR"
log_kv "EDID profile"  "$EDID_PROFILE"
echo

run_install
