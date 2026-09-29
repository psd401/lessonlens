# Sample lessons for help screenshots

Help page screenshots use fictional lessons only. These files rebuild the sample audio.

- `decomposers.txt`: invented 7th-grade science lesson on decomposers (about 6.5 minutes of audio). Teacher and student names are invented.
- `generate_audio.py`: turns a script into audio with Kokoro text-to-speech, one voice per speaker, with silent pauses for wait time. Usage is in the file header.

The other two sample lessons, food webs and energy pyramids, were generated on 2026-09-25 from scripts that were not saved. Only their audio exists (`lessonlens-sample-food-webs-room.m4a`, `lessonlens-sample-energy-pyramids-room.m4a`, kept outside the repo).

## Capturing without real data

The Growth Dashboard charts every completed lesson in the library, so capture it from a library holding only sample lessons. One way: run a local build with a temporary home folder, e.g. `HOME=/tmp/ll-home CFFIXED_USER_HOME=/tmp/ll-home LessonLens.app/Contents/MacOS/LessonLens`. That build asks for sign-in on each launch and shows keychain prompts; allow them. Link `/tmp/ll-home/Documents/huggingface` to your existing `~/Documents/huggingface` so the transcription model isn't downloaded again.
