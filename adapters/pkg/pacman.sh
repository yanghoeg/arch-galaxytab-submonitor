#!/usr/bin/env bash
# Package manager adapter: pacman (official repos only — sunshine is AUR)
# If sunshine is not in official repos, install manually or use an AUR helper.

_pacman_pkg_install()      { run_sudo pacman -S --noconfirm "$@"; }
_pacman_pkg_is_installed() { pacman -Qi "$1" &>/dev/null; }

_pacman_pkg_remove()   { run_sudo pacman -Rns --noconfirm "$@"; }
