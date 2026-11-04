#!/usr/bin/env bash
# Fake Claude CLI: replays a scripted behaviour from $FAKE_SCRIPT, records argv.
echo "$*" >> "${FAKE_ARGV_LOG:-/dev/null}"
case "${FAKE_SCRIPT:-ok}" in
  ok)            echo "READY"; exec /bin/sh -c 'while :; do sleep 1; done' ;;
  rate_limited)  echo "Claude usage limit reached. Your limit will reset at 3pm."; exit 0 ;;
  crash)         echo "boom" >&2; exit 1 ;;
  hang_silent)   exec /bin/sh -c 'while :; do sleep 1; done' ;;
esac
