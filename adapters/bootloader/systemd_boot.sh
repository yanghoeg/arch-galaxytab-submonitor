#!/usr/bin/env bash
# Bootloader adapter: systemd-boot

_systemd_boot_entry_file() {
  local esp
  esp=$(bootctl --print-esp-path 2>/dev/null) || esp="/boot"
  local dir="${esp}/loader/entries"

  # Match on the running initrd image name (from /proc/cmdline, world-readable)
  # e.g. "initrd=\initramfs-linux-zen.img" → "initramfs-linux-zen.img"
  local initrd_name
  initrd_name=$(grep -o 'initramfs-[^ ]*\.img' /proc/cmdline | head -1)

  local f
  if [[ -n "$initrd_name" ]]; then
    # -F: fixed string — prevents '.' in filename from being regex-interpreted
    f=$(grep -Frl "$initrd_name" "$dir" 2>/dev/null | head -1)
    [[ -z "$f" ]] && f=$(sudo grep -Frl "$initrd_name" "$dir" 2>/dev/null | head -1)
  fi

  # Fallback: first entry with an initrd line
  if [[ -z "$f" ]]; then
    f=$(grep -rl "^initrd" "$dir" 2>/dev/null | sort | head -1)
    [[ -z "$f" ]] && f=$(sudo grep -rl "^initrd" "$dir" 2>/dev/null | sort | head -1)
  fi

  [[ -n "$f" ]] && echo "$f" && return
  return 1
}

_systemd_boot_bootloader_add_param() {
  local param="$1"
  local entry
  entry=$(_systemd_boot_entry_file) \
    || die "No systemd-boot entry found. Check /boot/loader/entries or pass --bootloader."

  if grep -qF "$param" "$entry" 2>/dev/null; then
    log "Already present: $param"
    return 0
  fi

  log "Adding to options in: $(basename "$entry")"
  # Use | as delimiter — param contains '/' (e.g. edid/tabs9_120hz.bin)
  run_sudo sed -i "/^options / s|$| ${param}|" "$entry"
}

_systemd_boot_bootloader_list_params() {
  local entry
  entry=$(_systemd_boot_entry_file) || { warn "No entry file found."; return 1; }
  grep "^options" "$entry"
}
