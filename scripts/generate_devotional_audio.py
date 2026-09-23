#!/usr/bin/env python3
"""Synthesize tiny original WAV chimes for the app (no third-party audio).

The files are original PCM generated here — not a recitation, not a commercial
sample, and not copied from any recording. They exist so launch / śloka cues
have a rights-clear sound. Keep them short and quiet; the app defaults launch
autoplay to OFF.

    python3 scripts/generate_devotional_audio.py
"""
from __future__ import annotations

import math
import pathlib
import struct
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "assets" / "audio"
SR = 22050


def _tone(freqs: list[float], duration: float, volume: float = 0.55) -> bytes:
    n = int(SR * duration)
    frames = bytearray()
    for i in range(n):
        t = i / SR
        # Fast attack, exponential decay — a small bell, not a sustained note.
        env = (1.0 - math.exp(-45.0 * t)) * math.exp(-2.8 * t)
        sig = sum(math.sin(2.0 * math.pi * f * t) for f in freqs) / len(freqs)
        # Weak 2nd partial so it reads as a bell rather than a pure beep.
        sig += 0.18 * math.sin(2.0 * math.pi * freqs[0] * 2.0 * t) * env
        val = max(-1.0, min(1.0, sig * env * volume))
        frames += struct.pack("<h", int(val * 32767))
    return bytes(frames)


def write_wav(path: pathlib.Path, freqs: list[float], duration: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = _tone(freqs, duration)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes, {duration:.2f}s)")


def main() -> None:
    # 528 / 792 Hz — a fifth; short temple-like bell for app launch.
    write_wav(OUT / "launch_chime.wav", [528.0, 792.0], 1.15)
    # Slightly lower pair for the editorial śloka cue (distinct from launch).
    write_wav(OUT / "sloka_chime.wav", [396.0, 594.0], 0.95)


if __name__ == "__main__":
    main()
