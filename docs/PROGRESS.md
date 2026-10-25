# HOTICE — Development Progress

> **Continuing HOTICE on another model?** First read [CONTINUE_HERE.md](CONTINUE_HERE.md) for the verified repo state, product decisions, blockers, and ordered next steps. Refresh the current branch and Actions status; this checklist may lag behind newer commits.

## Current verified snapshot — 26 October 2026
- [x] **Flutter static analysis and widget tests passed** on the preview code branch: [Actions run 40201075329](https://github.com/parmtech/HOTICE/actions/runs/40201075329).
- [x] A real Android **debug** APK was compiled and uploaded as artifact `HOTICE-Android-Preview-APK` in the same run. This does **not** mean a production-signed APK or device QA pass.
- [x] Clear Normal Video / Music Video Studio mode switch with one freeform scene/story prompt in each mode.
- [x] Music Video Studio text-only local storyboard with selectable styles and edit/reorder/save controls. **No song upload, lyric timing, beats, live AI planning or rendering.**
- [x] One-tap demo entry without a fake password. All accounts/workspaces remain in-memory demos.
- [x] Avatar Studio editing/deleting, identity descriptions reused in demo model prompts, and guided 3D capture **preparation** UI. **No real scan or likeness lock.**
- [x] Additional font choices and corrected mobile More navigation.
- [ ] Final Android APK artifact of every later edit confirmed successful (check the newest [Actions runs](https://github.com/parmtech/HOTICE/actions)).
- [ ] Manual Android portrait/landscape screen-reader and device UX QA.
- [ ] Real camera capture / depth scan with informed consent, secure biometric deletion and provider-specific identity-reference testing.
- [ ] Server-side auth, cloud persistence, secure uploads, real AI rendering and verified real provider costs.
- [ ] Accurate song transcription/timings, media timeline, lip-sync, output editor and export.
- [ ] Verified Stripe/PayPal/payment webhooks and credit ledger.

**Definition of complete:** Implemented UI means only that demo interactions exist. It does not mean a verified AI/media pipeline or perfectly consistent 3D avatars. [Avatar identity architecture](AVATAR_IDENTITY_AND_SCAN.md).

## GitHub task threads
- [M1 — Flutter CI and responsive QA](https://github.com/parmtech/HOTICE/issues/1)
- [M2 — Secure accounts and persistence](https://github.com/parmtech/HOTICE/issues/2)
- [M3 — AI video generation and avatars](https://github.com/parmtech/HOTICE/issues/3)
- [M4 — Stripe/PayPal/cards and credit ledger](https://github.com/parmtech/HOTICE/issues/4)
- [M5 — Professional QA and release](https://github.com/parmtech/HOTICE/issues/5)

**Verification note:** The early failing Actions run has been superseded. On 26 October 2026 Flutter static analysis/tests and the Android debug build passed on run 40201075329. Later editing commits need the latest Actions run checked separately.

This checklist tracks source-level implementation separately from integration and release verification. A checked box means the specified source/UI task was written, **not** that it is production-ready.

## M1 — UI foundation
- [x] Flutter dependency manifest and app entry.
- [x] HOTICE branding, premium reusable design system and responsive shell.
- [x] Welcome screen.
- [x] Sign in / create-account demo screen.
- [x] Project grid, new-project flow and navigate-to-editor.
- [x] Video generation prompt, duration, ratio, workflow picker and local draft queue.
- [x] Avatar Lab create/list demo presets.
- [x] HOTICE Credits pricing: 1 cent per Credit; USD 10 minimum; USD 10/20/50 choices.
- [x] Stripe, PayPal and card selection UI (no live checkout).
- [x] Demo account add/switch/sign-out.
- [x] Dark/light/system and five accent presets.
- [x] GitHub Actions workflow + basic Flutter tests (execution status must be checked in Actions).
- [x] Flutter analyze passing in GitHub Actions (run 40201075329).
- [x] Flutter widget tests passing in GitHub Actions (run 40201075329).
- [ ] On-device UI / responsive visual QA.

## M2 — Backend and identity
- [ ] Real login/register, validation, reset and refresh token policies.
- [ ] Secure account switching, session isolation and cloud persistence.
- [ ] Project and avatar storage, backup and recovery.
- [ ] Persisted per-account theme and preferences.

## M3 — Real video and avatar generation
- [ ] AI provider adapter interfaces and model discovery.
- [ ] Video render job queue and status tracking.
- [ ] Image/reference upload and likeness consistency.
- [ ] Saved video previews, exports, retries, cancellation, errors.
- [ ] Audio/video timeline and advanced editor.

## M4 — Real credits and payments
- [ ] Authenticated server-side wallet and immutable transaction ledger.
- [ ] Stripe Checkout, server-side verified webhooks and payment cards.
- [ ] PayPal order capture, verified webhook and reconciliation.
- [ ] Receipts, refund/chargeback adjustments, tax handling.
- [ ] Model-specific per-generation credits pricing.

## M5 — Quality and release
- [ ] UI polish, accessibility and tablet/desktop overflow checks.
- [ ] Integration tests with CI green.
- [ ] Android/iOS native project scaffolds committed and maintained.
- [ ] Device build and manual QA.
- [ ] Release signing and app-store distribution (not yet requested).

## Issue-based progress
Use GitHub Issues as separate task threads for each next phase; link commits/PRs to the issue, and close only once tested. Do not calculate a whole-project percentage from this checklist: the scope and weights are not fixed.
