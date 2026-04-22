#!/usr/bin/env bash
# Initramfs adapter: dracut

_dracut_initramfs_add_file() {
  local src="$1"
  local conf="/etc/dracut.conf.d/tabdisp.conf"

  if [[ -f "$conf" ]] && grep -qF "$src" "$conf" 2>/dev/null; then
    log "Already in dracut conf: $src"
    return 0
  fi

  log "Adding to dracut conf: $src"
  run_sudo mkdir -p /etc/dracut.conf.d
  run_append "install_items+=\" ${src} \"" "$conf"
}

_dracut_initramfs_rebuild() {
  run_sudo dracut --force
}
