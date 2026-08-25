#!/usr/bin/env bash
# Shared bootstrap for the entry-point scripts: load helpers, detect the
# platform, and pull in the adapters that were selected.
#
# The caller must set SCRIPT_DIR, and may pre-set BOOTLOADER_OVERRIDE,
# INITRAMFS_OVERRIDE or PKG_OVERRIDE from its own CLI parsing.

source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/ports.sh"

BOOTLOADER="${BOOTLOADER_OVERRIDE:-$(port_detect_bootloader)}"
INITRAMFS="${INITRAMFS_OVERRIDE:-$(port_detect_initramfs)}"
PKG_MANAGER="${PKG_OVERRIDE:-$(port_detect_pkg_manager)}"

for _adapter in \
    "$SCRIPT_DIR/adapters/bootloader/${BOOTLOADER}.sh" \
    "$SCRIPT_DIR/adapters/initramfs/${INITRAMFS}.sh" \
    "$SCRIPT_DIR/adapters/pkg/${PKG_MANAGER}.sh"; do
  [[ -f "$_adapter" ]] || die "Adapter not found: $_adapter"
  # shellcheck source=/dev/null
  source "$_adapter"
done
