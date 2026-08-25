#!/usr/bin/env bash
# Package manager adapter: paru

_paru_pkg_install()      { run_cmd paru -S --noconfirm "$@"; }
_paru_pkg_is_installed() { pacman -Qi "$1" &>/dev/null; }

_paru_pkg_remove()     { run_cmd paru -Rns --noconfirm "$@"; }
