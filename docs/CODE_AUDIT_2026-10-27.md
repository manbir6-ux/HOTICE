# HOTICE — Code audit and Android acceptance, 27 October 2026

## Scope and truth in release claims
The app currently remains an Android-capable Flutter **UI/demo with local song preview and manual storyboard planning**. A successful Android debug build does not mean production AI rendering, song transcription, secure login, billing, or 3D actor identity reconstruction exist. The latest verified **audio preview** build is [run #223](https://github.com/parmtech/HOTICE/actions/runs/40436615353): Flutter validation, emulator navigation and APK build passed at commit `1579f61e`. A later code-audit patch has its own independent CI gate.

## Bugs fixed in this code-audit PR
1. Normal Video's scene prompt was remembered by project, while model choice, duration, aspect ratio and selected Actor leaked between projects. Now all controls are stored and restored per-project; invalid saved model/duration/aspect choices fall back to a supported demo combination. Project-unique Flutter dropdown keys prevent stale displayed values.
2. Music Video Studio's Actor dropdown likewise needed a project-specific key after the existing per-project Actor selection logic was introduced.
3. An ordinary generation draft could reference an Actor missing from the active demo workspace; now such a draft is rejected in the store, in addition to UI checks. These checks protect **demo data integrity**, not real cross-user security.
4. A `MusicVideoPlan` accepted a mutable caller-owned shot list and stored it without copying. A caller could empty/change that list later and corrupt an already-saved storyboard. The store now makes an immutable detached snapshot, trims story text and checks shot duration and nonempty description.
5. Generation draft attachment lists were likewise accepted by reference after validation; the store now captures a detached unmodifiable list and derives the displayed project title from the selected workspace project ID.
6. Added unit/widget regressions covering a foreign Actor reference, mutated music-plan lists, mutable attachment lists, invalid shot duration, and normal-video project settings changes.

## Automated checks
- The branch must pass `flutter analyze --no-fatal-infos`, `flutter test test/`, the Android emulator navigation integration test and debug APK upload for **its final SHA**.
- Analysis may still report informational/deprecation issues; passing with `--no-fatal-infos` is not zero lint warnings.
- The current Android smoke test covers navigation but **does not interact with a physical media picker, real camera, audio codecs or the full OS restore pipeline**.

## Manual release dry-run on physical Android device
- Fresh-install the APK for the exact tested SHA and confirm HOTICE version/build ID.
- Enter guest demo, open both modes, create two film projects, switch films repeatedly, confirm prompt/model/duration/aspect/Actor settings stay separate.
- Choose local MP3 and M4A/WAV songs; test file chooser cancel, invalid/corrupt file, a large file, play, pause, seek, 30-minute playback, background/foreground, app termination and changing projects while audio plays. Confirm no playback remains active after removing a song or leaving the editor.
- Save music plans, edit shot descriptions and 4–10-second manual timings, reopen saved snapshot; confirm old versions do not change.
- Switch between two demo emails; verify each profile only displays its own projects/Actors. This is not authentication; never treat demo emails as a privacy/security boundary.
- Navigate welcome/projects/video/music/Actor/Credits/Settings/Accounts in portrait, landscape, small-screen, large-font and screen-reader modes. Capture the **first** Flutter exception if any.
- For the separate Actor Vault draft PR #24, obtain explicit face-scan consent; test 7 physical camera angles, retake, bad lighting, native permissions, locked/unavailable Keystore, export password, wrong password, account change, sign-out purge, restart and restore. Never merge competing PR #22 encrypted-vault implementation into the same chain without explicit data-migration review.

## Production blockers (not available in stable HOTICE)
- Signed server-side authentication, verified authorization and persistent server/project storage.
- Genuine AI script planning, transcription/word timestamps, beat detection, lip-sync and synchronized media export.
- Verified real-model capability catalog, provider credentials/quoting, queued render jobs, cancellation and costly-operation safeguards.
- Backend Stripe/PayPal checkout, signed webhook verification, immutable credits ledger, refunds and auditability.
- Device-tested/consent-reviewed Actor capture and encrypted vault, licensed actual 3D head/full-body reconstruction.
- Distribution readiness: properly signed release build, secure backups, performance, accessibility, crash reporting, privacy/legal review.

**Do not describe the product as complete or bug-free until these gates are met.**
