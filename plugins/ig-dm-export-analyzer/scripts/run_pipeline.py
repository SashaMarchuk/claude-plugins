#!/usr/bin/env python3
"""Orchestrator: runs the whole pipeline against one config.

  Step 1  build_manifest.py   scan export (mojibake-fixed), filter, resolve media
  Step 2  transcribe.py       STT via the configured provider (cached, resumable)
  Step 3  build_chats.py      assemble chats/<slug>.json + index.json
  Step 4  verify.py           self-consistency checklist

Usage:
  python3 run_pipeline.py <config.yaml|.json>              # all steps
  python3 run_pipeline.py <config> --steps 3,4             # only these steps
  python3 run_pipeline.py <config> --from 2                # step 2 onwards
  python3 run_pipeline.py <config> --dry-run               # step 1 only, no STT

Every step is independently re-runnable with the same command; Step 2 is cached
per media file and Steps 3-4 cost nothing to repeat.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
STEPS = {
    1: ("build_manifest.py", "manifest"),
    2: ("transcribe.py", "speech-to-text"),
    3: ("build_chats.py", "assemble chats"),
    4: ("verify.py", "verify"),
}


def main() -> None:
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    config = args[0]
    wanted = sorted(STEPS)

    if "--dry-run" in args:
        wanted = [1]
    if "--steps" in args:
        wanted = sorted(int(x) for x in args[args.index("--steps") + 1].split(","))
    if "--from" in args:
        first = int(args[args.index("--from") + 1])
        wanted = [s for s in sorted(STEPS) if s >= first]

    for step in wanted:
        script, label = STEPS[step]
        print(f"\n=== Step {step}: {label} ===", flush=True)
        rc = subprocess.call([sys.executable, str(HERE / script), config])
        if rc != 0:
            print(f"\nStep {step} ({label}) exited with code {rc}. Stopping.", file=sys.stderr)
            raise SystemExit(rc)

    print("\nPipeline complete.")


if __name__ == "__main__":
    main()
