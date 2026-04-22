#!/usr/bin/env bash
# Initramfs adapter: mkinitcpio

_mkinitcpio_initramfs_add_file() {
  local src="$1"
  local conf="/etc/mkinitcpio.conf"

  if grep -qF "$src" "$conf" 2>/dev/null; then
    log "Already in mkinitcpio.conf FILES: $src"
    return 0
  fi

  log "Adding to mkinitcpio.conf FILES: $src"
  # Prepend into FILES=(...) — works for both FILES=() and FILES=(existing ...)
  run_sudo sed -i "s|^FILES=(|FILES=(${src} |" "$conf"
}

_mkinitcpio_initramfs_rebuild() {
  run_sudo mkinitcpio -P
}
