#!/usr/bin/env bash
L="$1"; W="$2"; D="${3:-0}"
if [ ! -f "$L" ]; then [ "$D" != 0 ] && sleep "$D"; echo $$ > "$L"; echo "$$" >> "$W"; fi
