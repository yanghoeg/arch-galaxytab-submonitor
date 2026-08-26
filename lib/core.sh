#!/usr/bin/env bash
# Core install logic. Knows WHAT to configure; HOW is delegated to ports.
# Depends on: lib/util.sh, lib/ports.sh, and the loaded adapter functions.

# Rebuilding the initramfs is the slowest thing here — on a Secure Boot system it
# drags kernel re-signing along with it — so only do it when the EDID blob or the
# initramfs config actually changed. The adapters set this when they edit.
INITRAMFS_DIRTY=false

# ── Steps ─────────────────────────────────────────────────────────────────────

_core_edid() {
  log_step "EDID: generate & install"

  # .gitignore's policy: synthetic blobs live under edid/generated/.
  local src="${SCRIPT_DIR}/edid/generated/${EDID_PROFILE}.bin"
  local dst="/usr/lib/firmware/edid/${EDID_PROFILE}.bin"

  if [[ ! -f "$src" ]]; then
    if [[ ! -f "${SCRIPT_DIR}/edid/generate.py" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        warn "edid/generate.py missing — would generate ${src}"
      else
        die "edid/generate.py not found. Run edid/generate.py first or place a pre-built .bin at: $src"
      fi
    else
      log "Generating EDID binary (CVT-RB2, profile ${EDID_PROFILE})..."
      run_cmd mkdir -p "${SCRIPT_DIR}/edid/generated"
      run_cmd python3 "${SCRIPT_DIR}/edid/generate.py" --profile "$EDID_PROFILE" --output "$src"
    fi
  else
    log "EDID binary exists: $src"
  fi

  run_sudo mkdir -p /usr/lib/firmware/edid
  if [[ "$DRY_RUN" == "true" ]]; then
    run_sudo cp "$src" "$dst"
    INITRAMFS_DIRTY=true
  elif sudo cmp -s "$src" "$dst" 2>/dev/null; then
    log "Installed blob is already identical: $dst"
  else
    run_sudo cp "$src" "$dst"
    INITRAMFS_DIRTY=true
  fi
  port_initramfs_add_file "$dst"
}

_core_kernel_params() {
  log_step "Kernel: DRM params for connector ${EDID_CONNECTOR}"
  port_bootloader_add_param "drm.edid_firmware=${EDID_CONNECTOR}:edid/${EDID_PROFILE}.bin"
  port_bootloader_add_param "video=${EDID_CONNECTOR}:e"
}

_core_initramfs() {
  log_step "Initramfs: rebuild"
  if [[ "$INITRAMFS_DIRTY" != "true" ]]; then
    log "Neither the blob nor the config changed — skipping rebuild."
    return 0
  fi
  port_initramfs_rebuild
}

_core_sunshine() {
  log_step "Sunshine: install (${SUNSHINE_PKG})"
  if port_pkg_is_installed "$SUNSHINE_PKG"; then
    log "Already installed — skipping."
  else
    port_pkg_install "$SUNSHINE_PKG"
  fi

  log_step "Sunshine: capabilities"
  # setcap replaces the whole capability set, and the LizardByte packages ship
  # cap_sys_admin,cap_sys_nice already. Re-apply both so cap_sys_nice survives.
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] sudo setcap cap_sys_admin,cap_sys_nice+p \$(command -v sunshine)"
  else
    local sunshine_bin
    sunshine_bin="$(command -v sunshine 2>/dev/null)" \
      || die "sunshine binary not found after install."
    sudo setcap cap_sys_admin,cap_sys_nice+p "$sunshine_bin"
  fi

  log_step "Sunshine: uinput group + systemd user service"
  run_sudo groupadd -f sunshine-uinput
  run_sudo usermod -aG sunshine-uinput "$USER"
  if [[ "${SUNSHINE_ENABLE:-true}" == "true" ]]; then
    run_cmd systemctl --user enable --now "$SUNSHINE_UNIT"
  else
    log "--no-enable: starting without touching your autostart setting."
    run_cmd systemctl --user start "$SUNSHINE_UNIT"
  fi
}

_core_sunshine_output() {
  log_step "Sunshine: capture target"
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf"

  if [[ -z "${SUNSHINE_OUTPUT:-}" ]]; then
    log "No --sunshine-output given — Sunshine keeps capturing its default"
    log "display, which is usually the built-in panel rather than the virtual"
    log "one. Once Sunshine has run at least once, list the candidates with:"
    log "  journalctl --user -u ${SUNSHINE_UNIT} | grep 'Found monitor'"
    log "then re-run with --sunshine-output <index>."
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] set 'output_name = ${SUNSHINE_OUTPUT}' in ${conf}"
    return 0
  fi

  mkdir -p "$(dirname "$conf")"
  backup_file "$conf"
  if [[ -f "$conf" ]] && grep -qE '^[[:space:]]*output_name[[:space:]]*=' "$conf"; then
    sed -i "s|^[[:space:]]*output_name[[:space:]]*=.*|output_name = ${SUNSHINE_OUTPUT}|" "$conf"
    log "Updated output_name in $conf"
  else
    printf 'output_name = %s\n' "$SUNSHINE_OUTPUT" >> "$conf"
    log "Added output_name to $conf"
  fi
  run_cmd systemctl --user restart "$SUNSHINE_UNIT"
}

_core_output_reset() {
  log_step "Session: park the virtual output at login"

  # Why this exists: the connector is forced on for the whole uptime, so KWin
  # sees the same set of screens whether or not a tablet is connected, and
  # restores whatever layout it saved last. End a session with the virtual
  # output still enabled -- reboot, crash, shutdown from the tablet -- and it
  # comes back at 0,0 on top of a real monitor. session.sh --stop handles the
  # tidy case; this handles the rest.
  local src="${SCRIPT_DIR}/systemd/${OUTPUT_RESET_UNIT}.in"
  local unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  local script="${SCRIPT_DIR}/scripts/virtual-output.sh"

  [[ -f "$src" ]] || die "Unit template not found: $src"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] install ${unit_dir}/${OUTPUT_RESET_UNIT}"
    log "[dry-run]   ExecStart=${script} off --connector ${EDID_CONNECTOR}"
  else
    mkdir -p "$unit_dir"
    # The unit points back into this checkout. Moving or deleting the repo
    # breaks it -- systemctl --user status will say exactly that.
    sed -e "s|@SCRIPT@|${script}|g" -e "s|@CONNECTOR@|${EDID_CONNECTOR}|g" \
      "$src" > "${unit_dir}/${OUTPUT_RESET_UNIT}"
    systemctl --user daemon-reload
    log "Installed: ${unit_dir}/${OUTPUT_RESET_UNIT}"
  fi

  if [[ "${OUTPUT_RESET_ENABLE:-true}" == "true" ]]; then
    # enable, not enable --now: running it here would park an output you may be
    # using right now. It takes effect at the next login.
    run_cmd systemctl --user enable "$OUTPUT_RESET_UNIT"
  else
    log "--no-output-reset: unit installed but left disabled."
  fi
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
  _core_sunshine_output
  _core_output_reset
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
