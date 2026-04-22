#!/usr/bin/env bash
# Package manager adapter: yay

_yay_pkg_install()      { run_cmd yay -S --noconfirm "$@"; }
_yay_pkg_is_installed() { pacman -Qi "$1" &>/dev/null; }
