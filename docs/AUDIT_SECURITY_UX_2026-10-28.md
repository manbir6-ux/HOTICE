# HOTICE — Security, reliability and UX audit (28 October 2026)

## Audit scope and evidence
Targeted source review of current stable `main` Flutter demo and Namecheap PHP/MySQL MVP: app model/store, project editing/navigation, song preview lifecycle, billing preview, PHP routing, authentication, cloud entitlements, revisioned document storage, media upload/download, installer, storage directories and CI. Changes in this branch must pass GitHub's PHP syntax, PHP core smoke, ephemeral MySQL HTTP test, Flutter analyzer, widget tests, Android emulator smoke and APK build. This is **not** a claim of exhaustive production penetration testing or physical-device testing.

## Bugs/risks addressed in this PR
1. **High — potential webroot data exposure:** the PHP runtime only checked `backend/public`, not an enclosing `public_html` document root. Private media now uses canonical symlink-aware webroot checks against the runtime document root, the configured cPanel site root and the backend/public path. Installer validates storage isolation **before** database setup. Operators must specify `public_webroot_path` in config.php. Dedicated smoke regressions cover nested, ancestor, unresolved and symlink cases.
2. **High — login attempts across many emails/IPs:** rate limiting based only on email+IP could be bypassed by credential spraying across emails or IPs. Separate keyed email and IP rolling-window counters now reject this; successes cannot clear the IP budget. HTTP integration tests verify email throttling. Real IP/WAF hardening is a future deployment gate.
3. **Medium — future cloud identifier mismatch:** new Flutter film project IDs were timestamp decimals, incompatible with backend's UUIDv4 route contract. New device-created IDs use `Random.secure()` UUIDv4 with stable format; seeded `demo-*` IDs remain local legacy examples and need explicit migration if ever synced.
4. **UX — data loss visibility:** Projects screen now clearly states that in-memory content is lost on restart (device persistence and paid cloud sync are still missing). Also added project-specific scene/storyboard counts and a helpful no-projects empty state.
5. **High — JSON map/list shape corruption:** PHP's associative JSON decoding converted nested `{}` into `[]`. The API now keeps `stdClass` maps from HTTP parsing through MySQL document storage and outbound response, including nested empty settings. A real MySQL/HTTP regression test checks both empty object and empty array types.
6. **Maintenance — Flutter deprecations:** migrated deprecated color opacity and selected form-field initialization calls to supported current Flutter APIs; removed an unnecessary import.

## Known release blockers not fixed by a source audit
- **Critical: device storage not persistent.** Flutter `HotIceStore` and session drafts are still in-memory; implement encrypted/device-private durable snapshots + migrations and restart recovery before positioning it as a local-first app. A warning is not persistence.
- **Critical: billing/auth integration not live.** No app-to-backend secure authentication, token management or explicit sync consent. Server's cloud entitlements are only admin test grants until verified subscription webhooks and ledger exist.
- **Critical: no AI generation/export.** Real provider adapters, async jobs, pricing confirmations, delivery, retries, render/export, audio analysis and actor identity pipeline are absent.
- **Actor Studio draft stack is not stable:** PR #11→#16→#17→#19→#20→#21→#24 is unmerged. PR #22 is competing vault code. Reconcile encrypted formats, memory purges, 7-angle capture, consent and OS key storage before merging.
- **Media size:** shared-host 20 MiB upload cap means full-size videos need object storage/resumable transfer; don't upload multi-GB files through shared-host PHP.
- **Cloud privacy:** per-user auth is established on backend, but production requires email verification, account recovery/MFA, abuse control, privacy deletion, backup/restore drills, malware scanning and role-restricted admin.
- **Test limits:** Android Actions smoke covers navigation; no on-device camera/file-picker playback QA. Flutter analyzer previously had ~36 informational warnings, and GitHub's Android emulator has occasionally failed to start Dart Development Service before running assertions. All future final-SHA runs must be checked.

## Required human deployment checks
1. Keep `backend/config.php`, private-media and DB credentials outside *every* publicly reachable cPanel document root, including parent/addon domains. Verify by requesting attempted URLs and aliases from a separate client.
2. Use a valid HTTPS-only API subdomain; verify TLS, HSTS and disallow proxy forgery of HTTPS state. Keep production registration off pending email verification.
3. Ensure daily DB/file backups can be restored and file permissions block other hosting users. Test quota limits, expired entitlements, concurrent edits, and failed uploads.
4. Test login from multiple IPs and behind actual CDN/proxy without leaking real IPs; consider edge rate limiting.
5. Test device restarts, airplane mode, Android background, corrupt/wrong media, refunds, subscriptions and local-vs-cloud conflicts before paid release.

**Never upload real API keys to GitHub or a mobile build. Do not present this source-only QA as cPanel live deployment.**
