#!/bin/zsh
# cliphist-listen: watch clipboard and store every entry (text + images)
# Requires wl-clipboard + cliphist. Detaches its own fds so it can be
# spawned from autostart without holding the launcher's pipe open.
exec >/dev/null 2>&1 </dev/null

while true; do
    wl-paste --type text --watch cliphist store
done &

while true; do
    wl-paste --type image/png --watch cliphist store
done &

wait