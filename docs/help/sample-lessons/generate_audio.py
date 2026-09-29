"""Turn a sample lesson script into classroom-style audio for help screenshots.

Script format, one line each:
    T|Teacher line.        (speaker code, then the text)
    S1|Student line.       (S1-S5 are students)
    PAUSE|6                (silence in seconds, for wait time)

Usage (Apple Silicon, from this folder):
    uv run --with mlx-audio --with pydub --with "misaki[en]" python generate_audio.py decomposers.txt
    ffmpeg -i decomposers-dry.wav -af "aecho=0.8:0.6:40|70:0.25|0.15,highpass=f=90,lowpass=f=7000,volume=0.9" \
        -ar 48000 -c:a aac -b:a 96k lessonlens-sample-decomposers-room.m4a
"""
import glob
import os
import sys
import tempfile

from mlx_audio.tts.generate import generate_audio
from pydub import AudioSegment

VOICES = {"T": "af_nova", "S1": "af_sarah", "S2": "am_liam", "S3": "af_bella", "S4": "am_echo", "S5": "am_michael"}
RATE = 24000

script = sys.argv[1]
out = AudioSegment.silent(800, frame_rate=RATE)
with tempfile.TemporaryDirectory() as tmp:
    for i, line in enumerate(open(script).read().strip().splitlines()):
        who, text = line.split("|", 1)
        if who == "PAUSE":
            out += AudioSegment.silent(int(float(text) * 1000), frame_rate=RATE)
            continue
        prefix = os.path.join(tmp, f"l{i:03d}")
        generate_audio(model="mlx-community/Kokoro-82M-bf16", text=text, voice=VOICES[who],
                       lang_code="a", file_prefix=prefix, verbose=False)
        for f in sorted(glob.glob(prefix + "_*.wav")):
            out += AudioSegment.from_wav(f)
        out += AudioSegment.silent(700, frame_rate=RATE)

dest = os.path.splitext(script)[0] + "-dry.wav"
out.export(dest, format="wav")
print(f"{dest}: {len(out) / 1000:.1f}s")
