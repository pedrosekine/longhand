#!/usr/bin/env python3
"""Make plugin-page/tick.wav, the sound of a tick (2026-10-17).

Synthesised rather than downloaded, so it is ours to tune and carries no
licence: a short, soft, wooden "tock" — a low body and a brighter top, both
dying away in a few tens of milliseconds, with a gentle onset so it never
clicks harshly. Quiet on purpose (about -12 dBFS at its peak): it answers a
tick, it does not announce one.

Run: python3 tools/make_tick.py   (writes plugin-page/tick.wav)
"""
import math
import pathlib
import struct
import wave

RATE = 44100
LENGTH = 0.09          # seconds
PEAK = 0.25            # of full scale: about -12 dBFS
PARTIALS = [           # (Hz, weight, decay in seconds)
    (740, 0.55, 0.020),
    (1480, 0.30, 0.012),
    (2960, 0.15, 0.006),
]
ATTACK = 0.0015        # seconds of onset, so the first sample is not a click

# Beside the page, so it is installed with it.
OUT = pathlib.Path(__file__).resolve().parent.parent / "plugin-page" / "tick.wav"


def samples() -> list[float]:
    n = int(RATE * LENGTH)
    out = []
    for i in range(n):
        t = i / RATE
        onset = 1 - math.exp(-t / ATTACK)
        v = sum(w * math.exp(-t / d) * math.sin(2 * math.pi * f * t) for f, w, d in PARTIALS)
        out.append(onset * v)
    # The last millisecond fades to nothing, so it ends without a click too.
    tail = int(RATE * 0.001)
    for k in range(tail):
        out[n - 1 - k] *= k / tail
    top = max(abs(x) for x in out)
    return [x / top * PEAK for x in out]


def main() -> None:
    data = b"".join(struct.pack("<h", int(round(x * 32767))) for x in samples())
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"wrote {OUT.relative_to(OUT.parent.parent)} ({len(data) // 2} samples, {LENGTH * 1000:.0f} ms)")


if __name__ == "__main__":
    main()
