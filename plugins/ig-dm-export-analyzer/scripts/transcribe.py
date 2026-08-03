#!/usr/bin/env python3
"""Step 2 — speech-to-text batch runner (provider-agnostic).

Reads <output>/manifest.jsonl, transcribes every audio + video-with-audio row
through the provider named in the config, and writes:

  <output>/stt/<media_id>.json          raw provider payload (provenance)
  <output>/stt/<media_id>.txt           plain transcript text
  <output>/stt/<media_id>.result.json   normalised result (also the cache key)
  <output>/stt/_batch_results.json      all results, consumed by Step 3

Cached by media id: re-runs skip finished files, so an interrupted run resumes
for free. Videos get their audio track extracted with ffmpeg before upload;
silent videos are never uploaded.

Providers: soniox (cloud) | whisper_cpp (local) | none (skip STT entirely).
Adding one means adding a `_run_<name>` function returning the same dict shape.

Usage: python3 transcribe.py <config.yaml|.json>
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from igdm_common import RunLog, load_config, now_iso, out_dir, resolve_credential  # noqa: E402


# --------------------------------------------------------------------------
# Provider: Soniox (async cloud STT) — proven end-to-end on a real corpus
# --------------------------------------------------------------------------

class Soniox:
    name = "soniox"

    def __init__(self, cfg: dict):
        self.c = cfg["stt"]["soniox"]
        self.delete_mode = cfg["stt"]["delete_remote"]
        self.base = self.c["base_url"].rstrip("/")
        # Imported lazily so `provider: none` / whisper_cpp need no dependency.
        try:
            import requests  # type: ignore
        except ImportError:
            raise SystemExit(
                "stt.provider is 'soniox', which needs the `requests` package, but it "
                "is not importable under this interpreter. Either `pip install requests` "
                "or switch stt.provider to `whisper_cpp` (local) or `none` (skip "
                "speech-to-text) — neither needs any third-party package."
            )
        self.requests = requests
        key = resolve_credential(self.c["credentials"], "SONIOX API key")
        self.headers = {"Authorization": f"Bearer {key}"}

    @property
    def model(self) -> str:
        return self.c["model"]

    def _retry(self, method: str, url: str, **kw):
        delay = 1.0
        for attempt in range(self.c["max_retries"]):
            resp = self.requests.request(method, url, headers=self.headers, **kw)
            if resp.status_code == 429 or resp.status_code >= 500:
                if attempt == self.c["max_retries"] - 1:
                    resp.raise_for_status()
                time.sleep(delay)
                delay *= 2
                continue
            return resp
        raise RuntimeError(f"unreachable: {method} {url}")

    def transcribe(self, audio_path: Path, mime: str) -> dict:
        with audio_path.open("rb") as fh:
            up = self._retry("POST", f"{self.base}/v1/files",
                             files={"file": (audio_path.name, fh, mime)}, timeout=120)
        up.raise_for_status()
        file_id = up.json()["id"]

        job = self._retry("POST", f"{self.base}/v1/transcriptions", timeout=60, json={
            "model": self.c["model"],
            "file_id": file_id,
            "language_hints": self.c["language_hints"],
            "enable_language_identification": self.c["enable_language_identification"],
            "enable_speaker_diarization": self.c["enable_speaker_diarization"],
        })
        job.raise_for_status()
        tid = job.json()["id"]

        deadline = time.time() + self.c["poll_timeout_sec"]
        while True:
            status = self._retry("GET", f"{self.base}/v1/transcriptions/{tid}", timeout=30).json()
            if status.get("status") == "completed":
                break
            if status.get("status") == "error":
                raise RuntimeError(f"Soniox error: {status.get('error_message')}")
            if time.time() > deadline:
                raise TimeoutError(f"Soniox job {tid} unfinished after "
                                   f"{self.c['poll_timeout_sec']}s")
            time.sleep(self.c["poll_interval_sec"])

        resp = self._retry("GET", f"{self.base}/v1/transcriptions/{tid}/transcript", timeout=60)
        resp.raise_for_status()
        payload = resp.json()

        tokens = payload.get("tokens") or []
        langs = {}
        for t in tokens:
            if t.get("language"):
                langs[t["language"]] = langs.get(t["language"], 0) + 1

        deleted, note = self._delete(tid, file_id)
        return {
            "raw": payload,
            "text": "".join(t.get("text", "") for t in tokens).strip(),
            "engine": self.name,
            "model": self.c["model"],
            "language_hints": self.c["language_hints"],
            "detected_language": max(langs, key=langs.get) if langs else None,
            "speakers": len({t.get("speaker") for t in tokens if t.get("speaker") is not None}),
            "job_id": tid,
            "file_id": file_id,
            "remote_file_deleted": deleted,
            "delete_note": note,
        }

    def _delete(self, tid: str, file_id: str):
        """Delete provider-side transcription + upload. Never raises."""
        if self.delete_mode == "skip":
            return None, "skipped by config (stt.delete_remote=skip)"
        ok, notes = True, []
        for label, url in (("transcription", f"{self.base}/v1/transcriptions/{tid}"),
                           ("file", f"{self.base}/v1/files/{file_id}")):
            try:
                r = self._retry("DELETE", url, timeout=30)
                if r.status_code not in (200, 204, 404):
                    ok = False
                    notes.append(f"{label} delete -> HTTP {r.status_code}: {r.text[:200]}")
            except Exception as e:
                ok = False
                notes.append(f"{label} delete raised: {e}")
        return ok, "; ".join(notes) if notes else "ok"


# --------------------------------------------------------------------------
# Provider: whisper.cpp (local, nothing leaves the machine)
# --------------------------------------------------------------------------

class WhisperCpp:
    name = "whisper_cpp"

    def __init__(self, cfg: dict):
        self.c = cfg["stt"]["whisper_cpp"]
        if not self.c.get("model_path"):
            raise SystemExit("config: stt.whisper_cpp.model_path is required for "
                             "provider whisper_cpp (e.g. ggml-large-v3-turbo.bin)")
        if not Path(self.c["model_path"]).is_file():
            raise SystemExit(f"whisper model not found: {self.c['model_path']}")

    @property
    def model(self) -> str:
        return Path(self.c["model_path"]).stem

    def transcribe(self, audio_path: Path, mime: str) -> dict:
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "in.wav"
            subprocess.run(["ffmpeg", "-y", "-i", str(audio_path), "-vn",
                            "-ar", "16000", "-ac", "1", str(wav)],
                           capture_output=True, timeout=600, check=True)
            proc = subprocess.run(
                [self.c["binary"], "-m", str(self.c["model_path"]),
                 "-l", self.c["language"], "-f", str(wav), "-nt"],
                capture_output=True, text=True, timeout=1800, check=True)
        text = proc.stdout.strip()
        return {
            "raw": {"stdout": text},
            "text": text,
            "engine": self.name,
            "model": self.model,
            "language_hints": [self.c["language"]],
            "detected_language": None,
            "speakers": None,
            "job_id": None,
            "file_id": None,
            "remote_file_deleted": None,  # nothing ever left the machine
            "delete_note": "n/a — local provider, no upload",
        }


PROVIDERS = {"soniox": Soniox, "whisper_cpp": WhisperCpp}


# --------------------------------------------------------------------------
# Batch runner
# --------------------------------------------------------------------------

def ffprobe_has_audio(path: Path) -> bool:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a",
         "-show_entries", "stream=codec_type", "-of", "json", str(path)],
        capture_output=True, text=True, timeout=60, check=True)
    return bool(json.loads(out.stdout).get("streams"))


def extract_audio(video_path: Path, tmp_dir: Path) -> Path:
    wav = tmp_dir / f"{video_path.stem}.wav"
    subprocess.run(["ffmpeg", "-y", "-i", str(video_path), "-vn",
                    "-ar", "16000", "-ac", "1", str(wav)],
                   capture_output=True, timeout=600, check=True)
    return wav


def process_row(row: dict, provider, stt_dir: Path, log) -> dict:
    media_id = Path(row["uri"]).stem
    result_path = stt_dir / f"{media_id}.result.json"
    if result_path.exists():
        log(f"SKIP (cached) {media_id}")
        return json.loads(result_path.read_text(encoding="utf-8"))

    abs_path = Path(row["abs_path"])
    kind = row["kind"]
    tmp_ctx = None
    try:
        if kind == "video_audio":
            if not ffprobe_has_audio(abs_path):
                raise RuntimeError("ffprobe re-check found no audio track at execution time")
            tmp_ctx = tempfile.TemporaryDirectory()
            out = provider.transcribe(extract_audio(abs_path, Path(tmp_ctx.name)), "audio/wav")
        elif kind == "audio":
            out = provider.transcribe(abs_path, "audio/mp4")
        else:
            raise RuntimeError(f"process_row called on non-STT kind: {kind}")

        (stt_dir / f"{media_id}.json").write_text(
            json.dumps(out.pop("raw"), ensure_ascii=False, indent=2), encoding="utf-8")
        (stt_dir / f"{media_id}.txt").write_text(out["text"] + "\n", encoding="utf-8")

        result = dict(out, media_id=media_id, uri=row["uri"], slug=row["slug"],
                      status="ok", transcribed_at=now_iso())
        log(f"OK {media_id} ({kind}, lang={result['detected_language']}, "
            f"delete={result['delete_note']})")
    except Exception as e:
        result = {"media_id": media_id, "uri": row["uri"], "slug": row["slug"],
                  "status": "failed", "error": str(e), "transcribed_at": now_iso()}
        log(f"FAILED {media_id} ({kind}): {e}")
    finally:
        if tmp_ctx is not None:
            tmp_ctx.cleanup()

    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def main(config_path: str) -> None:
    cfg = load_config(config_path)
    od = out_dir(cfg)
    log = RunLog(od)
    stt_dir = od / "stt"
    stt_dir.mkdir(parents=True, exist_ok=True)

    provider_name = cfg["stt"]["provider"]
    rows = [json.loads(l) for l in
            (od / "manifest.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    stt_rows = [r for r in rows if r["kind"] in ("audio", "video_audio")]

    if provider_name == "none":
        log(f"Step 2 STT: provider=none — skipping all {len(stt_rows)} jobs. "
            f"Voice/video messages will be labeled NOT TRANSCRIBED.")
        (stt_dir / "_batch_results.json").write_text("[]", encoding="utf-8")
        return

    provider = PROVIDERS[provider_name](cfg)
    log(f"Step 2 STT: provider={provider_name} model={provider.model} "
        f"jobs={len(stt_rows)} concurrency={cfg['stt']['concurrency']} "
        f"delete_remote={cfg['stt']['delete_remote']}")

    results, done = [], 0
    with ThreadPoolExecutor(max_workers=cfg["stt"]["concurrency"]) as pool:
        futures = [pool.submit(process_row, r, provider, stt_dir, log) for r in stt_rows]
        for fut in as_completed(futures):
            res = fut.result()
            results.append(res)
            done += 1
            log(f"[{done}/{len(stt_rows)}] {res['media_id']} -> {res['status']}")

    (stt_dir / "_batch_results.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")

    ok = sum(1 for r in results if r["status"] == "ok")
    failed = sum(1 for r in results if r["status"] == "failed")
    deleted = sum(1 for r in results if r.get("remote_file_deleted"))
    log(f"Step 2 done: {ok} ok, {failed} failed, {deleted}/{ok} remote-deleted")

    if cfg["stt"]["delete_remote"] == "required" and ok and deleted < ok:
        log("BLOCKING: stt.delete_remote=required but provider-side deletion did not "
            f"succeed on {ok - deleted}/{ok} files. Investigate before treating this "
            "run as clean (see stt/*.result.json -> delete_note).")
        raise SystemExit(2)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
