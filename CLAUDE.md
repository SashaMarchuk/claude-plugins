# claude-plugins

This repository is in production — all four plugins (`clickup`, `gevent`, `ultra`, `ultra-analyzer`) are live for real users with a 170-test regression harness (`bash tests/run-all.sh`); every change must be made carefully, tested locally before commit, shipped via PR (no direct pushes to `main`), and accompanied by a migration note when registry-visible names or descriptions change so users can update via `/plugin update` rather than reinstall.
