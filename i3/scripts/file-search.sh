#!/bin/bash
# File search using rofi + find
# Opens the selected file with xdg-open

selected=$(find "$HOME" -maxdepth 5 \
    -not -path '*/\.*' \
    -not -path '*/node_modules/*' \
    -not -path '*/vendor/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/snap/*' \
    -type f 2>/dev/null | \
    rofi -dmenu -i -p "Search file" -matching fuzzy)

if [ -n "$selected" ]; then
    xdg-open "$selected" &
fi
