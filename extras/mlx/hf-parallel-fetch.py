#!/usr/bin/env python3
"""Parallel range-download of one HF file into a preallocated destination.

Usage: python3 hf-parallel-fetch.py <hf-url> <dest-path> [chunks]
Stdlib only. Bounded retries with backoff. Verifies final size.
"""
import os
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

URL = sys.argv[1]
DEST = sys.argv[2]
CHUNKS = int(sys.argv[3]) if len(sys.argv) > 3 else 8
MAX_RETRY = 100
BACKOFF_CAP = 5
LOCK = threading.Lock()
PROGRESS = {}


def get_total_size():
    req = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as r:
        if r.status != 200:
            raise RuntimeError(f"HEAD returned {r.status}")
        return int(r.headers["Content-Length"])


def worker(idx, start, end):
    pos = start
    written = 0
    attempts = 0
    while pos <= end:
        attempts += 1
        if attempts > MAX_RETRY:
            with LOCK:
                PROGRESS[idx] = (-1, start + written)
            return False
        try:
            req = urllib.request.Request(URL, headers={"Range": f"bytes={pos}-{end}"})
            with urllib.request.urlopen(req, timeout=45) as r:
                if r.status != 206:
                    raise RuntimeError(f"range request returned {r.status}, no range support")
                with open(DEST, "r+b") as f:
                    f.seek(pos)
                    while True:
                        buf = r.read(1 << 20)
                        if not buf:
                            break
                        f.write(buf)
                        pos += len(buf)
                        written += len(buf)
                        with LOCK:
                            PROGRESS[idx] = (1, start + written)
        except Exception as e:
            print(f"chunk {idx} attempt {attempts} failed at offset {pos}: "
                  f"{type(e).__name__}: {e}", flush=True)
            time.sleep(min(2 ** attempts, BACKOFF_CAP))
    with LOCK:
        PROGRESS[idx] = (1, start + written)
    return True


def main():
    total = get_total_size()
    print(f"total: {total} bytes ({total / 1e9:.2f} GB), {CHUNKS} parallel chunks", flush=True)
    if not os.path.exists(DEST) or os.path.getsize(DEST) != total:
        with open(DEST, "wb") as f:
            f.truncate(total)
    step = total // CHUNKS
    ranges = []
    for i in range(CHUNKS):
        s = i * step
        e = (total - 1) if i == CHUNKS - 1 else (s + step - 1)
        ranges.append((i, s, e))
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=CHUNKS) as ex:
        futs = [ex.submit(worker, i, s, e) for i, s, e in ranges]
        while True:
            time.sleep(30)
            with LOCK:
                vals = list(PROGRESS.values())
            if not vals:
                continue
            done = sum(p for st, p in vals if st == 1)
            failed = [p for st, p in vals if st == -1]
            elapsed = time.time() - t0
            print(f"progress: {done / 1e9:.2f}/{total / 1e9:.2f} GB "
                  f"({done / max(elapsed, 1) / 1e6:.2f} MB/s avg)", flush=True)
            if failed or all(st == 1 for st, _ in vals):
                break
        ok_all = all(fut.result() for fut in futs)
    if not ok_all:
        sys.exit("FAILED: one or more chunks exhausted retries")
    size = os.path.getsize(DEST)
    if size != total:
        sys.exit(f"FAILED: size {size} != expected {total}")
    dt = time.time() - t0
    print(f"DONE: {size} bytes in {dt:.0f}s ({total / dt / 1e6:.2f} MB/s)", flush=True)


if __name__ == "__main__":
    main()
