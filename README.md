# HOTICE

> **Continue development here:** [HOTICE — Next Model Handoff](docs/CONTINUE_HERE.md). This file records the last verified GitHub state, user decisions, current CI/build limitations, and exact next development steps. Recheck the latest `main` branch and Actions results before continuing.

**Cinematic AI Video Studio — Flutter UI foundation**

HOTICE is a premium multi-AI video creation workspace. This repository contains the **first-stage, functional UI prototype**: navigation, forms, local project drafts, account profile switching, avatar presets, pricing selections and theme controls. The app does **not** yet generate video, accept payments, or authenticate users with a server.

**Brand / product credit:** HOTICE  
**Repository:** manbir6-ux/HOTICE  
**App name:** HOTICE (no space or hyphen).

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

## Current verification
The project is still a source-code UI prototype, not a verified Android APK. GitHub Actions runs observed through 2026-10-26 were failing; successful Flutter analysis/tests and APK build have not been confirmed. The next requested milestone is a **testable Android UI build** with HOTICE branding. See [the handoff](docs/CONTINUE_HERE.md) and [Actions](https://github.com/manbir6-ux/HOTICE/actions).
