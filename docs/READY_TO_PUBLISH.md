# HOTICE — Ready to Publish release contract

**Decision record:** [GitHub Issue #33](https://github.com/parmtech/HOTICE/issues/33)  
**State:** NOT READY TO PUBLISH. This document defines evidence required to change that state.  
**Last reviewed:** 28 October 2026.

“Ready to publish” means the release candidate has passed every applicable gate below. A mock provider, green unit test, debug APK, or source-only review is not evidence of a live production service.

## Current verified architecture and limits

| Area | Current repository evidence | Release status |
| --- | --- | --- |
| Flutter client | Responsive studio and local UX; much project state remains in memory. | Blocked: durable local project/media storage, production onboarding and device QA. |
| cPanel API | PHP 8.2+/MySQL account/session API, server-owned cloud entitlements, project snapshots, private uploads and quota checks under `backend/`. | Blocked: not deployed or connected to clients; public registration lacks email verification/recovery and admin MFA/RBAC. |
| Web client | Inspiration/web studio implementation is proposed in open PR #11, not in `main`. | Blocked: review, integration, authenticated workflows and browser QA. |
| Admin | CLI account and test-entitlement tools exist. | Blocked: no owner-only web administration panel. |
| AI providers | PR #32 contains source-backed compatibility profiles and guarded request-envelope builders on its feature branch. | Blocked: no submission worker, real key, verified entitlement, live generation or cost settlement. |
| Billing | Credit price choices and server-managed test cloud entitlements are documented. | Blocked: no verified payment webhook, immutable credit ledger or refund/reconciliation workflow. |
| Identity | Local camera/reference work exists in stacked open PRs; PR #32 describes 2D guided capture. | Blocked: no production 3D reconstruction or validated provider identity pipeline. |
| Release evidence | CI workflows cover Flutter checks, Android debug APK/emulator smoke, PHP tests and MySQL HTTP integration. | Blocked: latest release-candidate SHA, iOS/release signing, staging, device and operational drills not verified here. |

## Release gates

The authoritative checkbox list lives in Issue #33. The following evidence must be attached to the release record before launch:

1. **User workflows:** responsive web and mobile flows for onboarding, project persistence, licensed inspiration/prompts, media upload, generation job lifecycle, result review/export, account recovery and clear failure states. No nonfunctional controls.
2. **Shared client API:** versioned and documented contracts; web, Android and iOS use the same authenticated service. Future desktop compatibility is demonstrated by the public contract. Local-first storage works offline; cloud sync requires informed opt-in, can be revoked and handles conflicts without silent overwrite.
3. **Hosting:** deploy to an isolated HTTPS cPanel staging subdomain. Verify supported PHP/MySQL/extensions, private configuration and media roots, cron/worker behavior, SQL least privilege, TLS, backups, restore and rollback. Move long-running work to a separately secured worker if shared hosting cannot safely support it.
4. **Identity and authorization:** verified registration/recovery, expiring and revocable sessions, owner MFA, server-enforced RBAC, CSRF protections for browser sessions, throttling, audit events and cross-account isolation tests.
5. **Secrets and media:** provider secrets remain server-side, encrypted/secret-managed, redacted from responses/logs/traces and absent from client builds. Rotation/deletion are verified. Uploads are private, ownership checked, short-lived when shared, content inspected, quota limited and deletable under documented retention/scanning policy.
6. **Admin and operations:** owner-only panel, with server authorization for provider keys/config/model capability and costs, service health, users/roles, subscription/credit status, uploads/jobs, feature flags and audit history. Health/error messages reveal no secrets. Monitoring, incident, backup/restore and rollback runbooks are exercised.
7. **Jobs and money safety:** provider adapters and async job state support idempotent submission, bounded retry, cancel semantics, timeouts, cost limits and safe errors. Signed/authenticated expiring quotes bind user, normalized request and model. Atomic credit reservation, settlement, refund and payment-webhook processing are ledgered and replay-safe.
8. **Compatibility:** every enabled model capability cites current official documentation and is checked against account/region entitlement. Validate input format, role, size, duration, output, lifecycle, rate limits, prices and errors. Unsupported attachments fail before submission. Keep each real provider disabled until controlled staging tests verify submission, polling/callbacks, output, actual usage and reconciliation.
9. **Dry runs:** mock and dry-run providers exercise success, timeout, malformed response, rejection, rate limit, partial failure, duplicate submission, retry, cancellation and refund without paid calls. These do not satisfy live-provider gates.
10. **3D identity:** independently verify commercial licenses for weights/dependencies, consent and retention, real inference, geometry/texture quality, export, and device/provider compatibility. A 2D photo-reference scanner must not be represented as 3D reconstruction.
11. **Build and publication:** clean-checkout automated unit, integration, contract, security regression and end-to-end checks pass; CI protects the release branch and emits traceable artifacts/SBOM. Reproducible signed Android/iOS/web builds contain no provider secrets. Real supported-device/browser acceptance and privacy, consent, terms, retention, subprocessors, accessibility, support and store material reviews are complete.

## Reproducible checks

From a clean checkout:

```sh
flutter create . --project-name hotice --platforms=android,ios
flutter pub get
flutter analyze --no-fatal-infos
flutter test test/
flutter test integration_test/android_smoke_test.dart -d <configured-emulator>
find backend -type f -name '*.php' -print0 | xargs -0 -n1 php -l
php backend/tests/smoke.php
bash backend/tests/http-integration.sh # Requires CI-style MySQL and local test configuration
```

CI's Android artifact is a debug preview, not a signed store build. Record the exact commit SHA and all job results. Run the cPanel deployment and restore rehearsal separately; never put real provider keys in test fixtures or CI logs.

## Branch and PR coordination

- **#32** `feat/smart-avatar-reference-engine` → `main`: model compatibility/reference work; still draft and not a live provider integration.
- **#11** `feat/actors-web-studio-v1` → `main`: inspiration and web foundation; open, non-draft. Review and integrate deliberately rather than duplicating its files.
- **#16 → #17 → #19 → #20 → #21 → #24** are a stacked Actor/vault chain with multiple unmerged dependencies.
- **#22** is a competing vault implementation based on #19, not an additional dependency. Do not combine vault layouts blindly.
- Review open PRs #11, #16, #17, #19–#24 and #32 against Issue #33; preserve branch history, choose one vault design, document migrations, and merge only after each branch's declared evidence is current.

## Release decision rule

For every gate record **PASS**, **BLOCKED** (with owner and evidence needed), or **NOT APPLICABLE** (with rationale) in Issue #33. Missing keys, hosting access, device acceptance, licensing, or legal review are explicit blockers. Do not mark the release ready while any required gate is open. No live paid calls are part of the current dry-run work.

