# HOTICE — Namecheap cPanel Cloud Backend v0.1

**Status 27 Oct 2026:** PHP/MySQL backend MVP implemented, local PHP syntax and core assertions checked, and the exact ZIP source **committed into backend/** with an independent GitHub Actions MySQL integration workflow. **It has not been deployed to Namecheap, connected to Flutter or live production tested.** GitHub CI checks are required before any production deployment. No account credentials/API secrets are committed.

## Hosting and policy
- Target: Namecheap shared cPanel, PHP 8.2+, pdo_mysql/fileinfo, MySQL/MariaDB, HTTPS.
- Subdomain document root points to `backend/public/`; config.php, PHP business logic, database scripts and `private-media/` must be kept outside **all** public document roots.
- Local-first: Flutter projects and media stay on the device. *The current HOTICE demo stores most projects in RAM; local persistence is a separate required Flutter change.* No automatic cloud upload or biometric uploads.
- Cloud optional and gated by server-owned paid entitlement records and quota; free account cannot enable cloud via UI or spoof client JSON.
- **Credits and cloud storage are separate:** fixed 1 HOTICE Credit = USD $0.01, purchase minimum USD $10. Never treat a credit pack as a cloud subscription or subscription as an AI credit grant.
- Media shared-host MVP cap: 20 MiB/file; large generated video results later need signed object storage and resumable upload.
- Inactive/expired plans: deny writes; grace read-only export of 30 days is a *provisional technical policy*, not a contracted offer. Cloud deletion remains available after expiry.
- Provider API keys and DB secrets never shipped inside Flutter. Use private server config and future outbound allowlisted provider proxy with billable-usage controls.

## Backend ZIP contents (also committed in backend/ in this PR)
`backend/public/index.php`, `backend/public/.htaccess`, `backend/src/App.php`, `backend/src/Support.php`, `backend/schema.sql`, `backend/config.example.php`, CLI installer/create-user/grant-trial/cleanup, smoke and MySQL HTTP integration tests, cPanel README, and independent `.github/workflows/backend_ci.yml`.

Endpoints: GET /health; POST /v1/auth/login, /register (disabled by default), /logout; GET /v1/me; GET /v1/projects; GET/PUT/DELETE /v1/projects/{UUID}; PUT /v1/projects/{UUID}/files/{UUID}; GET/DELETE /v1/files/{UUID}.

Implementation principles: password_hash and verification; random bearer tokens stored only as SHA-256 digests; per-IP/email throttled login; prepared PDO queries, owner-scoped authorization; server-side cloud entitlement; transactional quotas; optimistic project revision conflict 409; MIME inspection; 20MiB upload guard; random filenames; private media outside web root; sanitised errors; no permissive CORS.

## Verification truth
- Local PHP 8.4 syntax checks: nine PHP files passed.
- Local standalone smoke test: 206 core assertions passed.
- ZIP checksum SHA-256: `9fefae39e892dfa80c0afc0b492fbd32f29ac791826aae43f8c9c7efd84be768`.
- **MySQL end-to-end HTTP integration test not executed locally:** no pdo_mysql driver/MySQL server in the current local container. The repository now includes a GitHub Actions workflow with an ephemeral MySQL service to test account login, subscription gate, project conflict, media upload/download/deletion and session revocation. CI result for the added code must be checked separately.
- **No Namecheap deployment, public URL or provider/payment key installation has happened.** Do not label this a working live API.
- Current `main` Flutter code is still a UI/demo and has no backend client wiring.

## Release-critical next steps
1. Verify committed PHP source under `backend/` and run/fix the independent MySQL integration GitHub Actions workflow. Resolve security concerns before release.
2. Connect secure Flutter device storage and real auth in separate reviewed PRs, including access tokens in native secure storage, explicit cloud sync opt-in and offline conflict handling.
3. Configure a dedicated, HTTPS-only cPanel subdomain, SQL database, server-only secrets, private media directory, backups and recovery; validate direct URL blocking of config/private files.
4. Integrate **verified** billing webhooks before automatically granting any paid cloud entitlement; add refunds, cancellations and webhook idempotency.
5. Implement allowlisted AI provider adapters, capability/pricing catalog, jobs, retry, charge reconciliation and large object storage using proper asynchronous infrastructure.
6. Complete integration QA on real devices and hosting, security review, email verification, deletion/privacy policy and quotas before release.

This plan reflects the user's requirement: **projects default to the device; cloud only for entitled subscribers; all provider secrets on server.**
