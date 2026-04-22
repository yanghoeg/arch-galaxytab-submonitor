#!/usr/bin/env bash
# Core install logic. Knows WHAT to configure; HOW is delegated to ports.
# Depends on: lib/util.sh, lib/ports.sh, and the loaded adapter functions.

# ── Steps ─────────────────────────────────────────────────────────────────────

_core_edid() {
  log_step "EDID: generate & install"

  local src="${SCRIPT_DIR}/edid/${EDID_PROFILE}.bin"
  local dst="/usr/lib/firmware/edid/${EDID_PROFILE}.bin"

  if [[ ! -f "$src" ]]; then
    if [[ ! -f "${SCRIPT_DIR}/edid/generate.py" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        warn "edid/generate.py not yet implemented — would generate ${src}"
      else
        die "edid/generate.py not found. Run edid/generate.py first or place a pre-built .bin at: $src"
      fi
    else
      log "Generating EDID binary (CVT-RB2 2960×1848@120Hz)..."
      run_cmd python3 "${SCRIPT_DIR}/edid/generate.py" --output "$src"
    fi
  else
    log "EDID binary exists: $src"
  fi

  run_sudo mkdir -p /usr/lib/firmware/edid
  run_sudo cp "$src" "$dst"
  port_initramfs_add_file "$dst"
}

_core_kernel_params() {
  log_step "Kernel: DRM params for connector ${EDID_CONNECTOR}"
  port_bootloader_add_param "drm.edid_firmware=${EDID_CONNECTOR}:edid/${EDID_PROFILE}.bin"
  port_bootloader_add_param "video=${EDID_CONNECTOR}:e"
}

_core_initramfs() {
  log_step "Initramfs: rebuild"
  port_initramfs_rebuild
}

_core_sunshine() {
  log_step "Sunshine: install"
  if port_pkg_is_installed sunshine; then
    log "Already installed — skipping."
  else
    port_pkg_install sunshine
  fi

  log_step "Sunshine: capabilities"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] sudo setcap cap_sys_admin+p \$(command -v sunshine)"
  else
    local sunshine_bin
    sunshine_bin="$(command -v sunshine 2>/dev/null)" \
      || die "sunshine binary not found after install."
    sudo setcap cap_sys_admin+p "$sunshine_bin"
  fi

  log_step "Sunshine: uinput group + systemd user service"
  run_sudo groupadd -f sunshine-uinput
  run_sudo usermod -aG sunshine-uinput "$USER"
  run_cmd systemctl --user enable --now sunshine
}

_core_udev() {
  log_step "udev: uinput access rules"
  run_sudo install -Dm644 \
    "${SCRIPT_DIR}/udev/60-tabdisp-uinput.rules" \
    "/etc/udev/rules.d/60-tabdisp-uinput.rules"
  run_sudo udevadm control --reload-rules
}

# ── Entry point ───────────────────────────────────────────────────────────────

run_install() {
  [[ "$DRY_RUN" == "true" ]] && log "Dry-run: no system changes will be made."

  _core_edid
  _core_kernel_params
  _core_initramfs
  _core_sunshine
  _core_udev

  echo ""
  log_header "Done"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Re-run with --apply to apply changes."
  else
    log "Reboot to activate the virtual display."
    log "Then run: ./scripts/verify.sh"
  fi
}
