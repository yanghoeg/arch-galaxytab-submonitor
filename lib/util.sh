#!/usr/bin/env bash
# Shared helpers — sourced by install.sh before anything else.

# ── Logging ───────────────────────────────────────────────────────────────────
log()        { echo "  $*"; }
log_kv()     { printf "  %-18s %s\n" "$1:" "$2"; }
log_step()   { echo ""; echo "▸ $*"; }
log_header() { echo "══ $* ══"; }
die()        { echo "[ERROR] $*" >&2; exit 1; }
warn()       { echo "[WARN]  $*" >&2; }

# ── Dry-run aware executors ────────────────────────────────────────────────────

# run_cmd: run a command, or print it in dry-run mode.
run_cmd() {
  if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# run_sudo: like run_cmd but prepends sudo on actual execution.
run_sudo() {
  if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "  [dry-run] sudo $*"
  else
    sudo "$@"
  fi
}

# run_append LINE FILE: append a line to a file (sudo), dry-run aware.
# Avoids the pipe-into-sudo quoting mess.
run_append() {
  local line="$1" file="$2"
  if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "  [dry-run] echo '$line' | sudo tee -a $file"
  else
    printf '%s\n' "$line" | sudo tee -a "$file" > /dev/null
  fi
}

# ── String helpers ────────────────────────────────────────────────────────────

# sed_escape STRING: escape regex metacharacters so STRING matches literally
# inside a sed s|...|...| expression. Paths carry '.' and '/'; without this a
# removal pattern can match more than it should.
sed_escape() { printf '%s' "$1" | sed 's/[\\^$.*[]/\\&/g; s/|/\\|/g'; }

# validate_adapter_name KIND NAME: reject anything that could escape the
# adapters/ directory when interpolated into a source path.
validate_adapter_name() {
  [[ "$2" =~ ^[a-z0-9_]+$ ]] \
    || die "Invalid $1 name: '$2' (only a-z 0-9 _ allowed)"
}

# validate_connector_name NAME: DRM connector names are letters, digits and
# dashes. This value is interpolated into kernel parameters and sed scripts.
validate_connector_name() {
  [[ "$1" =~ ^[A-Za-z0-9-]+$ ]] \
    || die "Invalid connector name: '$1' (only A-Z a-z 0-9 - allowed)"
}

# validate_pkg_name NAME: Arch package names allow letters, digits and @._+-
validate_pkg_name() {
  [[ "$1" =~ ^[A-Za-z0-9@._+-]+$ ]] \
    || die "Invalid package name: '$1'"
}

# /boot is commonly root-only (drwx------), so a plain [[ -f ]] or grep against
# a bootloader entry silently reports "absent" for an unprivileged user. That
# turns the adapters' idempotency checks into false negatives and duplicates
# kernel parameters on a second run. These two read-only helpers fall back to
# sudo, and deliberately run even under --dry-run because they only inspect.

# file_exists PATH
file_exists() { [[ -f "$1" ]] || sudo test -f "$1" 2>/dev/null; }

# file_has PATH LITERAL
file_has() {
  grep -qF "$2" "$1" 2>/dev/null || sudo grep -qF "$2" "$1" 2>/dev/null
}

# backup_file PATH: keep a timestamped copy before editing an existing file.
# Only the bootloader entry and initramfs config need this -- they are
# boot-critical and edited in place.
backup_file() {
  local src="$1"
  file_exists "$src" || return 0
  local dst
  dst="${src}.bak.$(date +%Y%m%d-%H%M%S)"
  log "Backing up: $dst"
  if [[ -w "$(dirname "$src")" ]]; then
    run_cmd cp -a "$src" "$dst"
  else
    run_sudo cp -a "$src" "$dst"
  fi
}

# validate_output_name NAME: Sunshine's output_name is a display index on the
# KMS/Wayland backends. This value is interpolated into a sed expression.
validate_output_name() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]] \
    || die "Invalid Sunshine output name: '$1'"
}
