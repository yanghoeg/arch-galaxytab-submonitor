#!/usr/bin/env bash
# Bootloader adapter: GRUB

_grub_bootloader_add_param() {
  local param="$1"
  local cfg="/etc/default/grub"

  if grep -qF "$param" "$cfg" 2>/dev/null; then
    log "Already present: $param"
    return 0
  fi

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
