#!/usr/bin/env bash
# Port layer: auto-detection + dispatcher functions.
# Adapters implement _<adapter>_<port> functions; dispatchers call them by name.

# ── Detection ─────────────────────────────────────────────────────────────────

port_detect_bootloader() {
  # systemd-boot sets Loader* EFI vars under this GUID — readable without root
  local efi_var
  efi_var=$(ls /sys/firmware/efi/efivars/LoaderInfo-4a67b082-* 2>/dev/null | head -1)
  [[ -n "$efi_var" ]] && { echo "systemd_boot"; return; }
  [[ -f /etc/default/grub ]] && { echo "grub"; return; }
  die "Cannot detect bootloader. Override with --bootloader [systemd_boot|grub]."
}

port_detect_initramfs() {
  command -v mkinitcpio &>/dev/null && { echo "mkinitcpio"; return; }
  command -v dracut     &>/dev/null && { echo "dracut";     return; }
  die "Cannot detect initramfs tool. Override with --initramfs [mkinitcpio|dracut]."
}

port_detect_pkg_manager() {
  for h in yay paru aura; do
    command -v "$h" &>/dev/null && { echo "$h"; return; }
  done
  echo "pacman"
}

# ── Dispatchers ───────────────────────────────────────────────────────────────
# Each function delegates to the concrete implementation selected at startup.
# Variables BOOTLOADER, INITRAMFS, PKG_MANAGER must be set before calling.

port_bootloader_add_param()   { "_${BOOTLOADER}_bootloader_add_param"   "$@"; }
port_bootloader_list_params() { "_${BOOTLOADER}_bootloader_list_params"; }

port_initramfs_add_file()     { "_${INITRAMFS}_initramfs_add_file"      "$@"; }
port_initramfs_rebuild()      { "_${INITRAMFS}_initramfs_rebuild"; }

port_pkg_install()            { "_${PKG_MANAGER}_pkg_install"           "$@"; }
port_pkg_is_installed()       { "_${PKG_MANAGER}_pkg_is_installed"      "$1"; }
