"""Generates Cadence's two sound effects, synthesised so they are ours to ship.

The files are generated wholesale: edit this script, not Cadence/Resources/Sounds.

    python3 scripts/generate_sounds.py

set-logged.caf is a soft wooden tick for a logged set: short, dry and low in level, so it
confirms the tap under whatever the athlete is listening to. rest-over.caf is two bell notes
rising a fourth, warm rather than shrill, and doubles as the rest-over notification's sound.
Each note is a sum of decaying partials with a few milliseconds of attack, so nothing clicks.

Written as 16-bit WAV with the standard library, then converted to CAF with afconvert (macOS).
"""

import math
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOUNDS = REPO / "Cadence/Resources/Sounds"
RATE = 44100


def note(frequency, partials, attack, length):
    """A struck note: partials are (ratio, amplitude, decay seconds), summed under a cosine attack."""
    samples = []
    for i in range(int(length * RATE)):
        t = i / RATE
        value = sum(amp * math.exp(-t / decay) * math.sin(2 * math.pi * frequency * ratio * t)
                    for ratio, amp, decay in partials)
        if t < attack:
            value *= 0.5 - 0.5 * math.cos(math.pi * t / attack)
        samples.append(value)
    return samples


def mix(length, *voices):
    """Lays (start seconds, samples) voices on one track."""
    track = [0.0] * int(length * RATE)
    for start, samples in voices:
        offset = int(start * RATE)
        for i, value in enumerate(samples[:len(track) - offset]):
            track[offset + i] += value
    return track


def finish(samples, peak, fade=0.03):
    """Scales to a peak level and fades the tail to silence."""
    scale = peak / max(abs(s) for s in samples)
    fade_samples = int(fade * RATE)
    out = []
    for i, value in enumerate(samples):
        remaining = len(samples) - i
        if remaining < fade_samples:
            value *= remaining / fade_samples
        out.append(value * scale)
    return out


def write(name, samples):
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav), "wb") as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(RATE)
            file.writeframes(b"".join(struct.pack("<h", round(s * 32767)) for s in samples))
        SOUNDS.mkdir(parents=True, exist_ok=True)
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", str(wav), str(SOUNDS / f"{name}.caf")], check=True)


# A wood block: an inharmonic second partial, and everything gone in a tenth of a second.
TICK = [(1.0, 1.0, 0.045), (2.76, 0.3, 0.016), (5.4, 0.08, 0.006)]

# A small bell: harmonic partials, the upper ones dying first.
BELL = [(1.0, 1.0, 0.42), (2.0, 0.28, 0.22), (3.0, 0.1, 0.11), (4.2, 0.04, 0.05)]


def set_logged():
    return finish(note(740, TICK, attack=0.002, length=0.2), peak=0.28)


def rest_over():
    first = note(659.25, BELL, attack=0.004, length=1.1)   # E5
    second = note(880.0, BELL, attack=0.004, length=1.1)   # A5
    return finish(mix(1.3, (0, first), (0.14, second)), peak=0.4, fade=0.2)


if __name__ == "__main__":
    write("set-logged", set_logged())
    write("rest-over", rest_over())
    print(f"Wrote {SOUNDS.relative_to(REPO)}/set-logged.caf and rest-over.caf")
