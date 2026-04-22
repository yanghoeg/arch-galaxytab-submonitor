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
