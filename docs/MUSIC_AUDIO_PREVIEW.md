# HOTICE — Local song preview and manual storyboard timeline

Status: feature-branch source; production AI rendering and music analysis remain absent.

## What works
- Music Video Studio has an actual native file chooser (via `file_picker 11.0.3`) for MP3, WAV, M4A, AAC, FLAC and OGG. Imported files must be nonempty and at most 150 MiB. The player uses `just_audio`.
- A selected song can play, pause and seek on devices supported by the player. The selected song's display name and size are shown.
- Song path/name/player exist only in the current editor widget session. A project change builds a new keyed player panel, disposing the previous one, so audio cannot be mistaken for another project's soundtrack. No path or bytes are written to the demo workspace or cloud. OS/plugin caches are outside this in-memory scope and may persist temporarily.
- Users can manually change each storyboard shot duration between 4 and 10 seconds and see contiguous start/end timestamps plus total runtime.
- Prior project-specific style and Actor fix from PR #25 is preserved.

## Important limits
- The player does **not** transcribe lyrics, detect tempo/beats, align word timings, trim clips, export videos, upload files, encode audio, mix tracks or render AI video.
- 4–10 seconds is a **demo storyboard editing interval**, not a verified limit for AI providers.
- Audio is session-only: changing project, signing out or closing the editor loses the audio selection. The user must select the file again; no persistent file-copy or permissions are promised.
- Audio platform support, device codecs and filesystem permissions must be tested physically. The package's Windows/Linux audio backend may require additional plugin setup.
- Do not treat a locally playable song as permission to reproduce or distribute copyrighted content.
- Secrets, billing and account authentication are not touched.

## Verification gates
1. Flutter pub get/analyze and widget tests must pass on this **exact** branch commit.
2. Android emulator smoke must pass.
3. GitHub Actions must compile and upload an Android preview APK. Install/test on a physical phone to verify picker, file sources, long tracks, seeks, rotation, background/foreground and playback teardown.
4. Keep PR #24's Actor Vault changes independent; it is a stacked draft, not merged into stable main.

Dependencies were checked against the official package documentation as of 27 October 2026.