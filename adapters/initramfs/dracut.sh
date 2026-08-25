#!/usr/bin/env bash
# Initramfs adapter: dracut

_dracut_initramfs_add_file() {
  local src="$1"
  local conf="/etc/dracut.conf.d/tabdisp.conf"

  if file_exists "$conf" && file_has "$conf" "$src"; then
    log "Already in dracut conf: $src"
    return 0
  fi

  log "Adding to dracut conf: $src"
  run_sudo mkdir -p /etc/dracut.conf.d
  run_append "install_items+=\" ${src} \"" "$conf"
  # shellcheck disable=SC2034  # read by _core_initramfs once sourced
  INITRAMFS_DIRTY=true
}

_dracut_initramfs_rebuild() {
  run_sudo dracut --force
}

_dracut_initramfs_remove_file() {
  # install added a dedicated drop-in, so removing the whole file is exact.
  local conf="/etc/dracut.conf.d/tabdisp.conf"

  if ! file_exists "$conf"; then
    log "Not present: $conf"
    return 0
  fi

  log "Removing dracut drop-in: $conf"
  run_sudo rm -f "$conf"
}
