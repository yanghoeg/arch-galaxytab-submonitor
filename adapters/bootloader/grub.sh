#!/usr/bin/env bash
# Bootloader adapter: GRUB

_grub_bootloader_add_param() {
  local param="$1"
  local cfg="/etc/default/grub"

  if file_has "$cfg" "$param"; then
    log "Already present: $param"
    return 0
  fi

  backup_file "$cfg"
  log "Appending to GRUB_CMDLINE_LINUX_DEFAULT"
  # Insert before the closing quote of GRUB_CMDLINE_LINUX_DEFAULT="..."
  run_sudo sed -i \
    "s|\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"|\1 ${param}\"|" \
    "$cfg"
  run_sudo grub-mkconfig -o /boot/grub/grub.cfg
}

_grub_bootloader_list_params() {
  grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub 2>/dev/null
}

_grub_bootloader_remove_param() {
  local param="$1"
  local cfg="/etc/default/grub"

  if ! file_has "$cfg" "$param"; then
    log "Not present: $param"
    return 0
  fi

  log "Removing from GRUB_CMDLINE_LINUX_DEFAULT: $param"
  run_sudo sed -i \
    "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s| *$(sed_escape "$param")||" \
    "$cfg"
  run_sudo grub-mkconfig -o /boot/grub/grub.cfg
}
