#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=true
BOOTLOADER_OVERRIDE=""
INITRAMFS_OVERRIDE=""
PKG_OVERRIDE=""
EDID_CONNECTOR="HDMI-A-1"
EDID_PROFILE="tabs9_120hz"

# ── CLI ───────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
arch-galaxytab-submonitor installer

Usage: $(basename "$0") [OPTIONS]

Options:
  --apply                Apply changes (default: dry-run)
  --bootloader <name>    Override bootloader adapter  [systemd_boot | grub]
  --initramfs  <name>    Override initramfs adapter   [mkinitcpio | dracut]
  --pkg        <name>    Override package manager     [yay | paru | pacman]
  --connector  <name>    DRM connector name           (default: HDMI-A-1)
  -h, --help             Show this help
EOF
}

_validate_adapter_name() {
  # Prevent path traversal: only allow [a-z0-9_] in adapter names
  [[ "$2" =~ ^[a-z0-9_]+$ ]] || { echo "Invalid $1 name: '$2' (only a-z 0-9 _ allowed)" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --apply)       DRY_RUN=false ;;
    --bootloader)  _validate_adapter_name "bootloader" "$2"; BOOTLOADER_OVERRIDE="$2"; shift ;;
    --initramfs)   _validate_adapter_name "initramfs"  "$2"; INITRAMFS_OVERRIDE="$2";  shift ;;
    --pkg)         _validate_adapter_name "pkg"        "$2"; PKG_OVERRIDE="$2";        shift ;;
    --connector)   EDID_CONNECTOR="$2";      shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# ── Load utilities and port declarations ──────────────────────────────────────
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/ports.sh"

# ── Detect adapters ────────────────────────────────────────────────────────────
BOOTLOADER="${BOOTLOADER_OVERRIDE:-$(port_detect_bootloader)}"
INITRAMFS="${INITRAMFS_OVERRIDE:-$(port_detect_initramfs)}"
PKG_MANAGER="${PKG_OVERRIDE:-$(port_detect_pkg_manager)}"

# ── Load concrete adapters into scope ─────────────────────────────────────────
for _adapter in \
    "$SCRIPT_DIR/adapters/bootloader/${BOOTLOADER}.sh" \
    "$SCRIPT_DIR/adapters/initramfs/${INITRAMFS}.sh" \
    "$SCRIPT_DIR/adapters/pkg/${PKG_MANAGER}.sh"; do
  [[ -f "$_adapter" ]] || die "Adapter not found: $_adapter"
  # shellcheck source=/dev/null
  source "$_adapter"
done

# ── Load core ─────────────────────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/core.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
log_header "arch-galaxytab-submonitor"
log_kv "Mode"          "$(if $DRY_RUN; then echo 'dry-run  (--apply to make changes)'; else echo 'APPLY'; fi)"
log_kv "Bootloader"    "$BOOTLOADER"
log_kv "Initramfs"     "$INITRAMFS"
log_kv "Pkg manager"   "$PKG_MANAGER"
log_kv "DRM connector" "$EDID_CONNECTOR"
echo

run_install
