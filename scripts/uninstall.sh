#!/usr/bin/env bash
# Reverse everything install.sh does, in the opposite order. Dry-run by default,
# exactly like the installer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

DRY_RUN=true
PURGE=false
BOOTLOADER_OVERRIDE=""
INITRAMFS_OVERRIDE=""
PKG_OVERRIDE=""
EDID_CONNECTOR="HDMI-A-1"
EDID_PROFILE="tabs9_60hz"
# The LizardByte packages ("sunshine" builds from source, "sunshine-bin" ships a
# prebuilt binary) install the same unit under a reverse-DNS name.
SUNSHINE_PKG="sunshine-bin"
SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"

usage() {
  cat <<USAGE
arch-galaxytab-submonitor uninstaller

Usage: $(basename "$0") [OPTIONS]

Options:
  --apply                Apply changes (default: dry-run)
  --purge                Also uninstall the sunshine package
  --bootloader <name>    Override bootloader adapter  [systemd_boot | grub]
  --initramfs  <name>    Override initramfs adapter   [mkinitcpio | dracut]
  --pkg        <name>    Override package manager     [yay | paru | pacman]
  --connector  <name>    DRM connector name           (default: HDMI-A-1)
  --sunshine-pkg <name>  Sunshine package             (default: sunshine-bin)
  --profile    <name>    EDID mode profile            (default: tabs9_60hz)
  -h, --help             Show this help

Sunshine's own configuration under ~/.config/sunshine is never touched --
it holds your pairing keys. Remove it by hand if you want a clean slate.
USAGE
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --apply)       DRY_RUN=false ;;
    --purge)       PURGE=true ;;
    --bootloader)  validate_adapter_name "bootloader" "${2:-}"; BOOTLOADER_OVERRIDE="$2"; shift ;;
    --initramfs)   validate_adapter_name "initramfs"  "${2:-}"; INITRAMFS_OVERRIDE="$2";  shift ;;
    --pkg)         validate_adapter_name "pkg"        "${2:-}"; PKG_OVERRIDE="$2";        shift ;;
    --profile)     validate_adapter_name "profile"    "${2:-}"; EDID_PROFILE="$2";        shift ;;
    --connector)   validate_connector_name "${2:-}";            EDID_CONNECTOR="$2";      shift ;;
    --sunshine-pkg) validate_pkg_name "${2:-}";                 SUNSHINE_PKG="$2";        shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

source "$SCRIPT_DIR/lib/bootstrap.sh"

log_header "arch-galaxytab-submonitor uninstall"
log_kv "Mode"          "$(if $DRY_RUN; then echo 'dry-run  (--apply to make changes)'; else echo 'APPLY'; fi)"
log_kv "Bootloader"    "$BOOTLOADER"
log_kv "Initramfs"     "$INITRAMFS"
log_kv "Pkg manager"   "$PKG_MANAGER"
log_kv "DRM connector" "$EDID_CONNECTOR"
log_kv "EDID profile"  "$EDID_PROFILE"
echo

log_step "udev: remove uinput rules"
run_sudo rm -f /etc/udev/rules.d/60-tabdisp-uinput.rules
run_sudo udevadm control --reload-rules

log_step "Sunshine: drop capabilities and group membership"
run_cmd systemctl --user disable --now "$SUNSHINE_UNIT"
if [[ "$DRY_RUN" == "true" ]]; then
  log "[dry-run] sudo setcap -r \$(command -v sunshine)"
else
  if sunshine_bin=$(command -v sunshine 2>/dev/null); then
    # A binary with no capability set makes setcap -r fail; that is not an error.
    sudo setcap -r "$sunshine_bin" 2>/dev/null || log "No capabilities were set."
  else
    log "sunshine binary not found — nothing to strip."
  fi
fi
if [[ "$DRY_RUN" == "true" ]] || getent group sunshine-uinput >/dev/null; then
  run_sudo gpasswd -d "$USER" sunshine-uinput
  run_sudo groupdel sunshine-uinput
else
  log "Group sunshine-uinput does not exist — skipping."
fi

if [[ "$PURGE" == "true" ]]; then
  log_step "Sunshine: uninstall package"
  if [[ "$DRY_RUN" == "true" ]] || port_pkg_is_installed "$SUNSHINE_PKG"; then
    port_pkg_remove "$SUNSHINE_PKG"
  else
    log "Not installed — skipping."
  fi
fi

log_step "Kernel: remove DRM params for connector ${EDID_CONNECTOR}"
port_bootloader_remove_param "drm.edid_firmware=${EDID_CONNECTOR}:edid/${EDID_PROFILE}.bin"
port_bootloader_remove_param "video=${EDID_CONNECTOR}:e"

log_step "Initramfs: drop the EDID blob and rebuild"
port_initramfs_remove_file "/usr/lib/firmware/edid/${EDID_PROFILE}.bin"
port_initramfs_rebuild

log_step "EDID: remove the installed blob"
run_sudo rm -f "/usr/lib/firmware/edid/${EDID_PROFILE}.bin"

echo
log_header "Done"
if [[ "$DRY_RUN" == "true" ]]; then
  log "Re-run with --apply to apply changes."
else
  log "Reboot to release the virtual display."
  log "Group membership changes take effect after logging out."
fi
