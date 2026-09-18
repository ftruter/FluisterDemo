#!/usr/bin/env python3
"""Pick a speaker-diverse subset of andreoosthuizen/afrikaans-30s train clips.

Writes a JSON manifest of clip ids and transcripts. Audio stays out of git;
tests download wavs into the user cache at runtime.
"""
from __future__ import annotations

import json
import random
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

DATASET = "andreoosthuizen/afrikaans-30s"
CONFIG = "default"
SPLIT = "train"
PAGE = 100
SEED = 20260913
TARGET = 500
# Listened-and-dropped: hymns/singing and/or unusable microphone noise.
# (audio_id, chunk_index) as published on the dataset.
# vUMDANFSHp4_003 chunks 2–18 are the same sung service; 0–1 are spoken Psalm 1.
EXCLUDED = {
    ("7nTZk7-XQFo-067", 10),
    ("PZiQ2TRLiuU", 126),
    ("WylbZD0lBys", 63),
    ("vUMDANFSHp4_004", 23),
} | {("vUMDANFSHp4_003", chunk) for chunk in range(2, 19)}
ROWS_URL = (
    "https://datasets-server.huggingface.co/rows"
    f"?dataset={DATASET}&config={CONFIG}&split={SPLIT}"
)


def curl_json(url: str) -> object:
    proc = subprocess.run(
        ["curl", "-fsSL", "--retry", "5", "--retry-delay", "2", url],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(f"curl failed ({proc.returncode}) for {url}\n{proc.stderr}")
    return json.loads(proc.stdout)


def fetch_catalog() -> tuple[str | None, list[dict]]:
    first = curl_json(f"{ROWS_URL}&offset=0&length={PAGE}")
    total = int(first["num_rows_total"])
    revision = None
    rows: list[dict] = []

    def absorb(payload: dict) -> None:
        nonlocal revision
        for item in payload["rows"]:
            row = item["row"]
            idx = int(item["row_idx"])
            if revision is None:
                src = row["audio"][0]["src"]
                # .../--/<revision>/--/default/train/<n>/audio/audio.wav
                marker = "/--/"
                if marker in src:
                    revision = src.split(marker, 1)[1].split(marker, 1)[0]
            rows.append(
                {
                    "row": idx,
                    "audio_id": row["audio_id"],
                    "chunk_index": int(row["chunk_index"]),
                    "transcript": row["transcript"],
                }
            )

    absorb(first)
    offset = PAGE
    while offset < total:
        print(f"fetching offset {offset}/{total}", file=sys.stderr, flush=True)
        absorb(curl_json(f"{ROWS_URL}&offset={offset}&length={PAGE}"))
        offset += PAGE
    if len(rows) != total:
        raise SystemExit(f"expected {total} rows, got {len(rows)}")
    return revision, rows


def select(rows: list[dict], count: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        groups[row["audio_id"]].append(row)
    speakers = list(groups)
    rng.shuffle(speakers)
    for speaker in speakers:
        rng.shuffle(groups[speaker])

    chosen: list[dict] = []
    seen: set[tuple[str, int]] = set()
    # Round-robin so every sermon/speaker appears before any speaker is reused.
    # Skip excluded clips in-place so a replacement comes from the same speaker.
    while len(chosen) < count:
        progressed = False
        for speaker in speakers:
            bucket = groups[speaker]
            while bucket:
                clip = bucket.pop()
                key = (clip["audio_id"], clip["chunk_index"])
                if key in seen or key in EXCLUDED:
                    continue
                seen.add(key)
                chosen.append(clip)
                progressed = True
                break
            if len(chosen) == count:
                break
        if not progressed:
            break
    chosen.sort(key=lambda c: (c["audio_id"], c["chunk_index"]))
    return chosen


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out = root / "FluisterDemoTests" / "Fixtures" / "afrikaans-30s-train-500.json"
    revision, rows = fetch_catalog()
    clips = select(rows, TARGET, SEED)
    speakers = sorted({c["audio_id"] for c in clips})
    catalog_speakers = sorted({r["audio_id"] for r in rows})
    manifest = {
        "dataset": DATASET,
        "config": CONFIG,
        "split": SPLIT,
        "revision": revision,
        "seed": SEED,
        "selection": "round-robin-by-audio-id",
        "catalog_size": len(rows),
        "catalog_speakers": len(catalog_speakers),
        "excluded": [
            {"audio_id": audio_id, "chunk_index": chunk, "reason": "microphone noise and/or singing"}
            for audio_id, chunk in sorted(EXCLUDED)
        ],
        "clips": clips,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(
        f"wrote {out} ({len(clips)} clips, {len(speakers)}/{len(catalog_speakers)} speakers)",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
