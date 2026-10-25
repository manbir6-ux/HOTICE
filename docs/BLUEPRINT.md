# HOTICE — Product Blueprint (Initial Specification)

## 1. Vision
A polished, premium, cross-platform AI filmmaking studio combining projects, scenes, generation workflows, characters/avatars, multiple AI video providers, credit-based payments, and account management. This is the target product, not a claim that every feature is integrated.

## 2. Product principles
- HOTICE-only brand. Professional, visually rich UI: no cheap-looking generic layouts.
- Simple first-run experience; strong desktop, tablet and phone navigation.
- Projects and scenes form the central workflow.
- Isolate providers, authentication and billing behind interfaces, never UI secrets.
- Visible project progress and durable backlog in GitHub Issues.
- UI prototype first; no APK/release requested at this stage.

## 3. Screen and navigation map
1. Welcome: HOTICE brand, cinematic hero, feature overview, Get Started.
2. Login / register: sign-in, create-account and session routing. Current implementation is explicitly a demo UI and not real authentication.
3. Projects: overview cards, create project, open project.
4. Project generation studio: prompt editor, model/workflow selector, duration 4/8/10 seconds, aspect ratios 16:9 / 9:16 / 1:1, avatar selection, generated-scene history and preview stage.
5. Avatar Lab: character identity/preset creation; later photo/reference inputs, consistent facial features, character library, controlled reuse and provider-specific character policies.
6. HOTICE Credits: price packs, method selection, transaction history, wallet ledger and receipts (last three require backend).
7. Accounts: account creation, add/switch account, sign out; later real independently authenticated accounts and cloud isolation.
8. Settings: theme mode and multiple colour presets; later preference persistence, security, notifications, storage and accessibility.

## 4. Credits and checkout
**Currency: USD. 1 HOTICE Credit = USD 0.01 (one US cent).**
- USD 10 minimum: 1,000 Credits.
- USD 20: 2,000 Credits.
- USD 50: 5,000 Credits.
- Purchase choices: Stripe, PayPal and credit/debit card.
- Real checkout requires backend-created sessions, verified webhooks, idempotent issuance, an immutable credit ledger, refunds/disputes handling and currency/tax compliance.
- **Never issue credits based solely on a client callback.** 
- Generation costs are not yet defined. Do not debit mock credits for draft saving.
- Credit price is fixed here; generation usage prices must be decided separately.

## 5. Planned architecture
Flutter presentation -> app state -> repository/services -> authenticated backend:
- Auth module: secure login, OAuth/email options as approved, refresh/revoke and device sessions.
- Project service: metadata, assets, versioned scenes, autosave, restore and collaboration later.
- AI router: configurable provider adapters, feature flags, model capabilities, fallback, rate limits and error mapping.
- Job engine: queued/running/failed/completed statuses, polling/websocket updates, retry, cancellation, result URLs and durable provenance.
- Avatar service: image/reference uploads, consent and likeness controls, reusable IDs and consistent character settings.
- Media storage: secure object storage, signed URLs, metadata and retention.
- Billing: Stripe/PayPal gateway adapters with backend-verified credit ledger and fraud prevention.
- Observability: structured diagnostics, audit trail, crash reporting and developer QA.

## 6. First code milestone — UI prototype
The first commit includes working navigation and local demo forms/screens, *not* live AI or payments. Responsive layouts and reusable theme components are present. No production passwords, keys, tokens or payment credentials are bundled.

## 7. Release gates (not yet passed)
- Flutter analyze and widget tests in GitHub Actions.
- Browser/device visual QA across portrait, tablet and desktop widths.
- Accessible contrast, keyboard focus and overflow fixes.
- Authentication threat model and backend integration tests.
- Webhook replay, duplicate-charge, refund and credit ledger tests.
- Provider billing limits and job queue lifecycle tests.
- Real-device video previews, rendering tests and app-store compliance.
- Android/iOS platform scaffolds and builds after the product workflows are stable.

## 8. Roadmap
**M1 UI foundation:** all requested initial screens, basic navigation and demo interactions.  
**M2 Persistence:** real sessions, secure database-backed projects, avatars and preferences.  
**M3 AI pipeline:** provider adapters, upload, render jobs, consistency, preview and export.  
**M4 Billing:** live Stripe + PayPal + cards, wallet ledger, receipts and disputes.  
**M5 Creator Pro:** timeline/storyboards, shot chaining, audio, effects, collaboration, polishing and release hardening.

## 9. Scope boundaries
Model names currently represent UI workflow presets, not verified integrations with commercial providers. Project, avatar and account changes disappear when the demo restarts. The UI shows sample/demo credits only, not a funded wallet.
