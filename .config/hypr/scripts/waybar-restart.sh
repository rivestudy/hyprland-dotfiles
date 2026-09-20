#!/usr/bin/env bash

killall -9 swaync 2>/dev/null || true
killall -9 waybar 2>/dev/null || true

nohup swaync >/dev/null 2>&1 &
nohup waybar >/dev/null 2>&1 &
