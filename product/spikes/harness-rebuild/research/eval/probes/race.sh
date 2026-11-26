#!/usr/bin/env bash
LOCK="$1"; MODE="$2"; WINLOG="$3"
case "$MODE" in
  mkdir)   mkdir "$LOCK" 2>/dev/null && echo "$$" >> "$WINLOG" ;;
  pidfile) # the NAIVE check-then-write that most orchestrators ship
           if [ ! -f "$LOCK" ]; then sleep 0.01; echo $$ > "$LOCK"; echo "$$" >> "$WINLOG"; fi ;;
  noclobber) ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null && echo "$$" >> "$WINLOG" ;;
esac
