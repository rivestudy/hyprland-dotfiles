#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Hyprlock script

if pidof hyprlock >/dev/null; then
    exit 0
fi

hyprlock
