#!/usr/bin/env python3
"""Read raw S16LE mono PCM on stdin and print a smoothed 0..1 level per line.

Consumed by the Voxtype HUD to draw a real input-level waveform. The HUD pipes
`parec` into this script and reads one line per ~40 ms.

Mapping: RMS -> dBFS -> 0..1 over a -60..0 dB window, with a fast attack and a
slow release, so the bars jump on speech and fall back gracefully.
"""
import array
import math
import sys

WINDOW_MS = 40
RATE = 16000
SAMPLES = int(RATE * WINDOW_MS / 1000)
BYTES = SAMPLES * 2

DB_FLOOR = -60.0
ATTACK = 0.60
RELEASE = 0.14
IDLE_FLOOR = 0.03
# Lifts mid-level speech so the bars have visible dynamic range; 1.0 = linear.
GAMMA = 0.8


def main():
    level = 0.0
    while True:
        chunk = sys.stdin.buffer.read(BYTES)
        if not chunk:
            break
        try:
            samples = array.array("h")
            samples.frombytes(chunk[: (len(chunk) // 2) * 2])
        except Exception:
            continue
        if not samples:
            continue
        acc = 0.0
        for s in samples:
            acc += (s / 32768.0) ** 2
        rms = math.sqrt(acc / len(samples))
        db = 20.0 * math.log10(rms) if rms > 1e-7 else DB_FLOOR
        target = (db - DB_FLOOR) / -DB_FLOOR
        if target < 0.0:
            target = 0.0
        elif target > 1.0:
            target = 1.0
        target = target ** GAMMA
        k = ATTACK if target > level else RELEASE
        level += (target - level) * k
        print("%.3f" % max(level, IDLE_FLOOR), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
