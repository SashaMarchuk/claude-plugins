#!/usr/bin/env python3
"""Optional: materialise a mojibake-repaired copy of the export's messages tree.

The pipeline repairs the encoding in memory on every read (export.fix_mojibake),
so this script is NOT required. Run it only when you want a repaired tree on
disk to grep or hand-inspect — it never touches the original export.

  python3 fix_mojibake.py <config.yaml|.json> [dest_dir]

Default dest is a sibling of the messages dir named `<name>_fixed`
(e.g. .../your_instagram_activity/messages_fixed).

The fix: Meta's DYI export writes UTF-8 bytes that were decoded as Latin-1 and
re-escaped. `s.encode("latin-1").decode("utf-8")` reverses it; anything that is
not double-encoded raises and is returned untouched, so the transform is a safe
no-op on clean data and idempotent on repaired data.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from igdm_common import load_config, walk  # noqa: E402


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    cfg = load_config(sys.argv[1])
    src = Path(cfg["export"]["text_root"])
    dest = Path(sys.argv[2]).expanduser() if len(sys.argv) == 3 \
        else src.parent / f"{src.name}_fixed"

    if dest.exists():
        raise SystemExit(f"Destination already exists, refusing to overwrite: {dest}")
    if dest.resolve() == src.resolve() or str(dest.resolve()).startswith(str(src.resolve()) + "/"):
        raise SystemExit("Destination must be outside the source tree (never edit the export).")

    n_json = n_copied = 0
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        target = dest / rel
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix.lower() == ".json":
            data = walk(json.loads(path.read_text(encoding="utf-8")))
            target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            n_json += 1
        else:
            shutil.copy2(path, target)
            n_copied += 1

    print(f"Wrote {n_json} repaired JSON files and copied {n_copied} other files to {dest}")
    print("The original export was not modified. Point export.text_root at the new "
          "tree and set export.fix_mojibake=false if you want to use it (the in-memory "
          "fix is idempotent, so leaving it true is also harmless).")


if __name__ == "__main__":
    main()
