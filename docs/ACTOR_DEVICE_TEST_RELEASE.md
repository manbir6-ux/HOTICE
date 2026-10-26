# HOTICE Actor Scanner v0.2.0 — Android Device Test Checklist

**Date:** 26 October 2026 · **Feature branch:** `fix/full-code-audit-2026-10-26` · **PR:** [#19](https://github.com/parmtech/HOTICE/pull/19)

## Implemented in this device-test build

1. **Actors Studio guided-only creation.** Name/style/optional notes and **Auto touch-up** setting are entered before launching the camera. New live Actors cannot be saved through the old Quick Actor bypass.
2. **Real front-camera ML Kit guidance** on Android/iOS. Consent before permission, one-face checks, head alignment, distance and framing hints, four stable frames before the green shutter readiness indicator, vibration/click.
3. **Seven captured angles:** front; left/right 25–35°; left/right 40–60°; chin-up and chin-down. Each still is checked again for a detectable face and expected pose.
4. **Device calibration:** the *Swap left/right directions* toggle changes the mapping for both live preview and saved-still validation. This exists because OEM camera mirroring and yaw signs may vary.
5. **Review / Retake:** every photo is shown in the review gallery with its own Retake button; the named Actor is created only after final confirmation. Basic dark/overexposed/low-detail advisories are non-blocking.
6. **Model-specific Actor references:** if one image slot remains, HOTICE makes a real composite JPEG for multiple Actors; multi-image presets select separate angles. Face consistency with real providers has **not** been demonstrated.
7. **Optional Auto touch-up:** default OFF; when enabled, scene references get separate mild, non-destructive lighting/color corrected JPEG copies. Natural scanned photos remain unchanged. **Not face-only skin retouching or AI beauty reconstruction.**
8. **Actor export / import:** intentional user action exports a versioned `.hoticeactor` ZIP, including metadata, up to 12 original JPGs and touch-up preference; import checks manifest, all paths, duplicates, JPG signatures/dimensions and compressed/expanded size budgets before writing to a temporary private device folder. Duplicate names are suffixed rather than overwritten.
9. **Privacy:** face photos and touched-up references are temporary and cleared on next app start. *Export ZIP is UNENCRYPTED* and shows a warning/confirmation before exporting/importing. No backend upload, cloud backup, third-party telemetry or provider API key is used by these demo operations.

## Required phone acceptance tests

- [ ] Install the **newest full-green PR #19 APK** from the GitHub Actions Artifacts section, and note the short build commit ID shown in the app.
- [ ] Launch on a real front-camera Android phone; ensure camera permission appears only after consent.
- [ ] Check face natural proportions (no squish/stretch), correct preview crop in portrait and landscape rotations, reasonable performance and battery consumption.
- [ ] Front/left/right angles: turn YOUR head left and right. If instructions are reversed, toggle **Swap left/right directions** and verify both green status and the captured still now follow the correct direction. Record which setting was required and phone model.
- [ ] Scan all seven views under normal lighting. For chin up/down, verify green indicator and actual captured still are judged in the same direction. Report any unachievable pose.
- [ ] Test no face, two faces, too dark, overexposure, tilting and out-of-frame. Confirm low-detail warning appears in review, and it does not silently change natural photos.
- [ ] Retake the **third** angle in review, confirm earlier photos remain correct; then Save Actor. Test back/cancel during scanning and no leftover half-finished profile.
- [ ] Create Actor with Auto touch-up OFF, then ON. Save a scene with two Actors and check image-slot planning and local adjusted reference paths. Never describe this as real AI generation.
- [ ] Export Actor to `.hoticeactor`; verify privacy warning, ZIP exists and contains expected photos. Import; verify duplicate Actor name is safely renamed and 7 preview photos display. Test malformed ZIP and unexpected archive entries are rejected without crash.
- [ ] Force-close/reopen app and verify temporary photos have been cleared. Export a copy first if you need to preserve them across test sessions; ZIP must be kept privately.
- [ ] Deny/revoke camera permission, background/resume during scan, and phone low-storage scenarios; report the **FIRST** HOTICE diagnostic exception if the app fails.

## What remains NOT production ready

- A real cryptographically **encrypted and persistent on-device Actor vault**; secured backups/sync and multi-device account ownership.
- Full beauty segmentation/blemish removal and user-controlled reversible variants (only subtle global light/colour correction implemented).
- Certified face quality/liveness, AR/TrueDepth measurement, true 3D geometry reconstruction, fully rigged actor model, working 3DDFA weights, Blender GLB QA and turntable rendering.
- Real Gemini Omni/Veo and other provider generation; server auth, pricing, admin MFA, secure media vault and controlled worker processing.
- iOS camera device QA and Android OEM-specific calibration. Flutter/emulator tests cannot test an actual human face on a physical phone.

### Testing commands / CI

GitHub Actions must pass all: Flutter analysis/tests (including Actor ZIP/touch-up and guided camera unit tests), Python 3D worker contract tests, PHP Gemini payload and static web checks, Android emulator smoke and **versioned debug APK build**. A finished build proves the app compiles; only human physical-device testing establishes real-camera usability.

**Links:** [PR #19](https://github.com/parmtech/HOTICE/pull/19) · [Full code audit](CODE_AUDIT_FULL_PASS2_2026-10-26.md) · [camera hardware tracking issue #13](https://github.com/parmtech/HOTICE/issues/13)
