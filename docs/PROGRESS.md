# HOTICE — Development Progress

> **Continuing HOTICE on another model?** First read [CONTINUE_HERE.md](CONTINUE_HERE.md) for the verified repo state, product decisions, blockers, and ordered next steps. Refresh the current branch and Actions status; this checklist may lag behind newer commits.

## Verification snapshot — 2026-10-26
- [x] Source-level fixes committed for demo profile isolation, duplicate avatars, missing projects, draft avatar selection, email validation and compact navigation.
- [x] Demo-only model capability catalog and model-dependent duration/aspect/attachment validation committed (see `lib/src/video_models.dart`).
- [x] Model-specific credits display guards against unconfigured prices (no real provider pricing configured).
- [x] Extended unit/widget test source added (about 12 declared tests; **NOT proven to pass**).
- [ ] Flutter static analysis and widget tests **confirmed green** (latest checked GitHub Actions run 40197914603: `failure`; job steps/logs unavailable via connector).
- [ ] Android debug APK **successfully built and downloadable**. Latest verified tree contained no `android/` scaffold and no Android APK workflow; do not infer an APK from source commits.
- [ ] Normal Video / Music Video Studio mode split with music upload, lyric timing, AI story/shot planning and scene editor. **Requested but not yet implemented**.
- [ ] Actual live provider integrations and verified dynamic credit rates. Current capabilities are deliberately illustrative.
- [ ] Professional HOTICE logo integrated as Android launcher icon. A visual concept was shown in chat but not checked into the repository.

**Updated user direction:** Deliver a genuine testable Android UI build before live AI/payment integrations, with separate Normal Video and Music Video Studio flows. Maintain one simple free-text prompt box (no numerous advanced detail fields). See [the handoff](CONTINUE_HERE.md).

## GitHub task threads
- [M1 — Flutter CI and responsive QA](https://github.com/manbir6-ux/HOTICE/issues/1)
- [M2 — Secure accounts and persistence](https://github.com/manbir6-ux/HOTICE/issues/2)
- [M3 — AI video generation and avatars](https://github.com/manbir6-ux/HOTICE/issues/3)
- [M4 — Stripe/PayPal/cards and credit ledger](https://github.com/manbir6-ux/HOTICE/issues/4)
- [M5 — Professional QA and release](https://github.com/manbir6-ux/HOTICE/issues/5)

**Verification note:** The first GitHub Actions run on the initial Flutter UI commit reported failure without job logs being available through the connector. Code is committed but analysis and widget tests are **not yet verified passing**. Track root cause in M1.

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
- [ ] Flutter analyze passing in GitHub Actions (verify live run).
- [ ] Flutter widget tests passing in GitHub Actions (verify live run).
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
