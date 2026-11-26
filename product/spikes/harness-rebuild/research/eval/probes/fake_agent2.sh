#!/usr/bin/env bash
LOG="$1"; : > "$LOG"
echo "READY"
while IFS= read -r line; do printf '%s\n' "${#line}" >> "$LOG"; done
