#!/usr/bin/env bash
now() { if [ -n "${FAKE_NOW:-}" ]; then echo "$FAKE_NOW"; else date +%s; fi; }
# the logic under test: "is this heartbeat stale?"  stall_minutes=20
last=$1; stall=$((20*60))
age=$(( $(now) - last ))
[ "$age" -gt "$stall" ] && echo "STALE age=${age}s" || echo "FRESH age=${age}s"
