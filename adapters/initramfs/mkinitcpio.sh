#!/usr/bin/env bash
# Initramfs adapter: mkinitcpio

_mkinitcpio_initramfs_add_file() {
  local src="$1"
  local conf="/etc/mkinitcpio.conf"

  if file_has "$conf" "$src"; then
    log "Already in mkinitcpio.conf FILES: $src"
    return 0
  fi

  backup_file "$conf"
  log "Adding to mkinitcpio.conf FILES: $src"
  # Prepend into FILES=(...) — works for both FILES=() and FILES=(existing ...)
  run_sudo sed -i "s|^FILES=(|FILES=(${src} |" "$conf"
  # shellcheck disable=SC2034  # read by _core_initramfs once sourced
  INITRAMFS_DIRTY=true
}

_mkinitcpio_initramfs_rebuild() {
  run_sudo mkinitcpio -P
}

_mkinitcpio_initramfs_remove_file() {
  local src="$1"
  local conf="/etc/mkinitcpio.conf"

  if ! file_has "$conf" "$src"; then
    log "Not present in mkinitcpio.conf FILES: $src"
    return 0
  fi

  log "Removing from mkinitcpio.conf FILES: $src"
  run_sudo sed -i "/^FILES=(/ s|$(sed_escape "$src") *||" "$conf"
}
