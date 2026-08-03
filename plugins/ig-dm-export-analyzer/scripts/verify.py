#!/usr/bin/env python3
"""Step 4 — automated verification checklist.

Every check here is *self-consistent*: the expected numbers come from
threads.json / manifest.jsonl (derived independently
from the raw export in Step 1), never from constants, so the same checklist works
on any export. Known-good counts can additionally be asserted by putting them
under `verify.expect` in the config.

Writes <output>/verification_results.json. Exits non-zero if any check fails.

Usage: python3 verify.py <config.yaml|.json>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from igdm_common import MOJIBAKE_SMELLS, RunLog, load_config, out_dir  # noqa: E402

results = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, bool(ok), detail))
    print(f"{'PASS' if ok else 'FAIL'} - {name}" + (f" ({detail})" if detail else ""))


def main(config_path: str) -> None:
    cfg = load_config(config_path)
    od = out_dir(cfg)
    log = RunLog(od)
    provider = cfg["stt"]["provider"]
    delete_mode = cfg["stt"]["delete_remote"]

    threads = json.loads((od / "threads.json").read_text(encoding="utf-8"))
    index_doc = json.loads((od / "index.json").read_text(encoding="utf-8"))
    index = index_doc["threads"]
    manifest = [json.loads(l) for l in
                (od / "manifest.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]

    chat_files = sorted((od / "chats").glob("*.json"))
    chats = {}
    unparseable = []
    for f in chat_files:
        try:
            chats[f.stem] = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:
            unparseable.append(f"{f.name}: {e}")
    check("every chat file re-parses as UTF-8 JSON", not unparseable, f"{unparseable[:3]}")

    # --- 1. structure: counts agree with the independently-derived manifest ---
    exp_kept = sum(1 for t in threads if t["status"] == "kept")
    check("chats/ file count == kept thread count from threads.json",
          len(chat_files) == exp_kept, f"{len(chat_files)} vs {exp_kept}")
    check("index.json covers every thread in the export",
          len(index) == len(threads), f"{len(index)} vs {len(threads)}")

    by_reason = {}
    for r in index:
        by_reason[r["reason"]] = by_reason.get(r["reason"], 0) + 1
    check("every excluded thread carries a machine-readable reason",
          all(r["reason"] for r in index if r["status"] != "kept"),
          f"reasons: {by_reason}")

    # --- 2. reconciliation: nothing silently lost ---
    written = sum(len(c["messages"]) for c in chats.values())
    exp_written = sum(t["in_scope_message_count"] for t in threads if t["status"] == "kept")
    excluded_msgs = sum(t["total_message_count"] for t in threads if t["status"] != "kept")
    dropped_tail = sum(t["out_of_range_message_count"] for t in threads if t["status"] == "kept")
    total_scanned = sum(t["total_message_count"] for t in threads)
    check("messages written == in-scope count from threads.json",
          written == exp_written, f"{written} vs {exp_written}")
    check("reconciliation: written + excluded + out-of-range tail == total scanned",
          written + excluded_msgs + dropped_tail == total_scanned,
          f"{written} + {excluded_msgs} + {dropped_tail} = "
          f"{written + excluded_msgs + dropped_tail} vs {total_scanned}")

    idx_by_slug = {r["slug"]: r for r in index}
    mismatch = [s for s, c in chats.items()
                if len(c["messages"]) != idx_by_slug.get(s, {}).get("in_scope_message_count")]
    check("per-thread written count == index.json in_scope_message_count",
          not mismatch, f"{mismatch[:5]}")

    excluded_slugs = {t["slug"] for t in threads if t["status"] != "kept"}
    check("no excluded thread produced a chat file",
          not (excluded_slugs & set(chats)), f"{sorted(excluded_slugs & set(chats))[:5]}")
    manual = set(cfg["filter"]["exclude_thread_slugs"])
    check("configured manual exclusions are excluded and traceable in index.json",
          all(idx_by_slug.get(s, {}).get("reason") == "excluded_manual_thread" for s in manual),
          f"{sorted(manual)}")

    # --- 3. ordering + date scope ---
    non_ascending, out_of_range = [], []
    start_ms, end_ms = cfg["filter"]["start_ms"], cfg["filter"]["end_ms"]
    for slug, c in chats.items():
        ts = [m["ts_ms"] for m in c["messages"]]
        if any(ts[i] > ts[i + 1] for i in range(len(ts) - 1)):
            non_ascending.append(slug)
        for t_ms in ts:
            if (start_ms is not None and t_ms < start_ms) or (end_ms is not None and t_ms >= end_ms):
                out_of_range.append(slug)
                break
    check("messages ordered ascending by ts_ms in every file",
          not non_ascending, f"{non_ascending[:5]}")
    check("every written message falls inside the configured date range",
          not out_of_range, f"{out_of_range[:5]}")

    # --- 4. labeling contract ---
    empty, bad_marker, photo_bad, bad_status = [], [], [], []
    trans_counts = {"ok": 0, "failed": 0, "skipped": 0}
    silent_parts, silent_bad, not_deleted = 0, [], []
    type_counts, dir_counts = {}, {"in": 0, "out": 0}
    owner_voice = owner_video = 0

    for slug, c in chats.items():
        for m in c["messages"]:
            if not m.get("header") or not m.get("text"):
                empty.append((slug, m["i"]))
            has_marker = "⟦" in m["text"]
            if m["generated"] != has_marker:
                bad_marker.append((slug, m["i"], m["generated"], has_marker))
            type_counts[m["type"]] = type_counts.get(m["type"], 0) + 1
            dir_counts[m["dir"]] += 1
            if m["dir"] == "out" and m["type"] == "voice":
                owner_voice += 1
            if m["dir"] == "out" and m["type"] == "video_audio":
                owner_video += 1

            if m["type"] == "photo":
                if m["generated"] is not False:
                    photo_bad.append((slug, m["i"], "generated"))
                for media in m.get("media", []):
                    if media.get("caption", {}).get("status") != "not_analyzed":
                        photo_bad.append((slug, m["i"], "caption_status"))

            for media in m.get("media", []) or []:
                if media["kind"] == "video" and media.get("has_audio_track") is False:
                    silent_parts += 1
                    if media.get("transcription") is not None:
                        silent_bad.append((slug, m["i"]))
                    continue
                tr = media.get("transcription")
                if media["kind"] in ("audio", "video") and tr is not None:
                    st = tr.get("status")
                    if st not in trans_counts:
                        bad_status.append((slug, m["i"], st))
                    else:
                        trans_counts[st] += 1
                    if st == "ok" and delete_mode != "skip" and provider == "soniox" \
                            and not tr.get("remote_file_deleted"):
                        not_deleted.append((slug, m["i"]))

    check("every message has a non-empty header and non-empty text", not empty, f"{empty[:5]}")
    check("generated == true  <=>  ⟦ marker present in text (both directions)",
          not bad_marker, f"{bad_marker[:5]}")
    check("every photo is marked not_analyzed with generated=false",
          not photo_bad, f"{photo_bad[:5]}")
    check("every transcription.status is one of ok/failed/skipped",
          not bad_status, f"{bad_status[:5]}")
    check("every legend block is present and complete",
          all(set(c.get("_legend", {})) >= {"marker", "generated", "reliability", "language"}
              for c in chats.values()))

    # --- 5. STT coverage matches the manifest ---
    exp_stt = sum(1 for r in manifest if r["kind"] in ("audio", "video_audio"))
    exp_silent = sum(1 for r in manifest if r["kind"] == "video_silent")
    got_stt = sum(trans_counts.values())
    check("every audio / audio-bearing video from the manifest has a transcription entry",
          got_stt == exp_stt, f"{got_stt} vs {exp_stt} (manifest)")
    check("no STT failures", trans_counts["failed"] == 0,
          f"ok={trans_counts['ok']} failed={trans_counts['failed']} "
          f"skipped={trans_counts['skipped']}")
    check("silent video parts match the manifest and were never transcribed",
          silent_parts == exp_silent and not silent_bad,
          f"{silent_parts} vs {exp_silent} (manifest); bad={silent_bad[:3]}")
    if provider == "none":
        check("STT disabled: every audio entry is explicitly marked skipped",
              trans_counts["skipped"] == exp_stt, f"{trans_counts['skipped']} vs {exp_stt}")
    if delete_mode != "skip" and provider == "soniox":
        check("provider-side uploads deleted for every successful transcription",
              not not_deleted, f"{not_deleted[:5]}")

    # --- 6. encoding health ---
    escaped, mojibake = [], []
    for f in chat_files:
        raw = f.read_text(encoding="utf-8")
        if "\\u04" in raw or "\\u041" in raw:
            escaped.append(f.name)
        if any(s in raw for s in MOJIBAKE_SMELLS):
            mojibake.append(f.name)
    check("no \\uXXXX escaping of non-ASCII content", not escaped, f"{escaped[:5]}")
    check("no mojibake residue (UTF-8-as-Latin-1 artifacts) in output",
          not mojibake, f"{mojibake[:5]}")

    # --- 7. optional hard asserts from config.verify.expect ---
    actual = {
        "kept_threads": len(chat_files),
        "total_threads": len(index),
        "messages_written": written,
        "stt_ok": trans_counts["ok"],
        "stt_jobs": exp_stt,
        "owner_voice": owner_voice,
        "owner_video_audio": owner_video,
        "silent_videos": silent_parts,
    }
    for key, want in (cfg["verify"]["expect"] or {}).items():
        if key not in actual:
            check(f"expect.{key} (unknown key)", False,
                  f"valid keys: {', '.join(sorted(actual))}")
        else:
            check(f"expect.{key} == {want}", actual[key] == want, f"got {actual[key]}")

    # --- summary ---
    passed = sum(1 for _n, ok, _d in results if ok)
    print("\n=== SUMMARY ===")
    print(f"{passed}/{len(results)} checks passed")
    print(f"types: {type_counts}")
    print(f"direction: {dir_counts}")
    print(f"owner-sent transcribed media: {owner_voice} voice, {owner_video} video-with-audio")
    for name, ok, detail in results:
        if not ok:
            print(f"  FAILED: {name} ({detail})")

    (od / "verification_results.json").write_text(json.dumps({
        "passed": passed, "total": len(results),
        "stats": dict(actual, types=type_counts, direction=dir_counts,
                      transcription_status=trans_counts),
        "checks": [{"check": n, "passed": ok, "detail": d} for n, ok, d in results],
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    log(f"Step 4 verification: {passed}/{len(results)} checks passed")
    if passed != len(results):
        raise SystemExit(1)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
