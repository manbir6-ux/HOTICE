# HOTICE

> **Continue development here:** [HOTICE — Next Model Handoff](docs/CONTINUE_HERE.md). This file records the last verified GitHub state, user decisions, current CI/build limitations, and exact next development steps. Recheck the latest `main` branch and Actions results before continuing.

**Cinematic AI Video Studio — Flutter client and PHP/MySQL cloud API foundation**

HOTICE is a multi-AI video creation workspace under active development. `main` contains a Flutter studio client and a Namecheap cPanel-compatible PHP/MySQL API for authenticated sessions, server-owned cloud entitlements, revisioned project snapshots and private media. The Flutter client is still a demo with largely in-memory state and is not connected to that API. HOTICE does **not** yet offer live AI generation or payments, and there is no production admin panel or deployed service.

**Release decision: NOT READY TO PUBLISH.** Track the actionable release contract in [docs/READY_TO_PUBLISH.md](docs/READY_TO_PUBLISH.md) and [GitHub Issue #33](https://github.com/parmtech/HOTICE/issues/33). Keep API keys on a server; never add them to app code, builds, fixtures or logs.

**Brand / product credit:** HOTICE  
**Repository:** parmtech/HOTICE  
**App name:** HOTICE (no space or hyphen).

## UI improvements — Android test preview (26 Oct 2026)
This development branch adds:
- **One-tap guest demo**, no fake password requirement, plus optional demo email for isolated workspaces.
- **Two generator modes**: Normal Video and a separate offline Music Video Studio with eight visual directions.
- **Editable offline storyboard outlines** (no song analysis, real lyrics, or AI scene planning yet).
- **Avatar Studio** with named character profiles, edit/delete, reusable identity notes, multi-angle face-capture preparation, and text-only identity guidance passed to each demo video model.
- Improved small-screen navigation, typography options and visible demo/payment limitations.
- An Android debug APK build workflow with a generated HOTICE-branded preview launcher icon.

See [Avatar 3D capture and identity design contract](docs/AVATAR_IDENTITY_AND_SCAN.md) for the planned real capture pipeline, model adapter requirements, and privacy gates.

## Screens included
- Welcome / onboarding.
- Sign in and register UI (explicitly demo-only; never enter a real password).
- Projects grid and create-project dialog.
- Project editor / generation composer (prompt, workflow presets, aspect ratio, duration and avatar picker).
- Avatar Lab (local character presets).
- HOTICE Credits purchase preview: Stripe, PayPal and credit/debit card.
- Settings: light, dark, system + five colour themes.
- Accounts: add a demo profile, switch profile and sign out.

## Credit pricing — locked for this phase
**1 HOTICE Credit = USD 0.01 = 1 US cent.**  
**Minimum purchase = USD 10 = 1,000 Credits.**  
USD 20 = 2,000 Credits; USD 50 = 5,000 Credits.  
Amounts are illustrative purchase choices, not an active payment service.

## Run locally
Install the Flutter SDK, then in this repository:

~~~sh
flutter create . --project-name hotice --platforms=android,ios
flutter pub get
flutter run
~~~

The platform scaffolds (Android/iOS) are intentionally not committed at this UI-first phase; the command creates them. The GitHub Actions workflow also prepares them before analysis and tests.

## Architecture
- lib/main.dart — entry point, responsive studio shell and navigation
- lib/src/state.dart — demo state, project and credit rules
- lib/src/design.dart — premium design system and reusable cards
- lib/src/welcome.dart — welcome and demo sign-in/register
- lib/src/projects_generation.dart — projects and generation UI
- lib/src/account_credits.dart — avatars, credits, themes and accounts
- lib/src/video_models.dart — demo-only model capability rules, dynamic duration/aspect controls and attachment/quote validation
- docs/BLUEPRINT.md — product phases and integration contracts
- docs/PROGRESS.md — completion vs pending work
- docs/CONTINUE_HERE.md — durable next-model handoff and verified limitations
- docs/CREDITS.md — branding and attribution

**Important:** Current interactions are session-only. A production release requires server-side authentication, database persistence, payment security, actual provider integrations, and verified builds.

See docs/BLUEPRINT.md and docs/PROGRESS.md.

## Current verification and release limits
- CI definitions cover Flutter analysis/tests, Android emulator navigation and a debug APK, plus PHP syntax/smoke and MySQL HTTP integration. Check the latest run for the exact commit before relying on a result.
- A debug APK is a preview build, not a signed Play Store release. iOS release signing, staging deployment and physical-device acceptance are not demonstrated by these workflows.
- The cPanel API source is an MVP and is not deployed or wired to Flutter. Production account verification/recovery, owner MFA/RBAC admin, payment webhooks/credit ledger, AI job submission, and provider keys/tests remain open.
- Existing web inspiration work and model/Actor work are in open PRs. See [docs/READY_TO_PUBLISH.md](docs/READY_TO_PUBLISH.md) for branch coordination and gates; do not assume unmerged work is part of `main`.
- No true 3D reconstruction, live paid provider call, or payment transaction is claimed.

For technical setup, see [backend/README.md](backend/README.md), [docs/NAMECHEAP_CLOUD_BACKEND.md](docs/NAMECHEAP_CLOUD_BACKEND.md), and [docs/CONTINUE_HERE.md](docs/CONTINUE_HERE.md).

