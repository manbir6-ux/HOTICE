# HOTICE Cloud API — Namecheap cPanel MVP v0.1

This is a **working PHP 8.2+ and MySQL/MariaDB service implementation**, intended for cPanel shared hosting, **NOT an already deployed service or a paid production release**. It provides independent accounts/sessions, server-gated cloud entitlements, optimistic-revision project snapshots, and private media uploads/downloads with quota enforcement. **The Flutter app is not yet wired to these endpoints.** Real AI providers, payments and production registration are intentionally disabled; secrets belong on the server.

## Local first, cloud only with a verified entitlement

- Default: free users keep their projects/media **on device** once the Flutter local-persistence implementation is connected; the current Flutter UI demo still stores most project data **in memory**. This backend never uploads a user's device files automatically.
- Paid subscribers: the server decides if cloud access is active based on `cloud_entitlements` in its database. Free user cannot turn on cloud from the client. A trial can be granted **manually by a server administrator** for testing; it is not a paid subscription, a credit balance, or a webhook.
- Credits (1 credit = $0.01) are **separate** from subscription storage quotas. This code does not charge, issue or count HOTICE credits.
- Media files are max 20 MiB **per request** in this shared-host MVP. Server-side default caps also limit each entitled account to 100 cloud projects and each cloud project to 200 files (configurable by operator); the test environment checks that small-file/account quotas cannot be bypassed. Large AI video results must use future direct-to-object-storage transfers, not giant PHP uploads. Actual hosting disk and quota limits are additional constraints.
- Storage metadata and bytes stay private: both require Bearer authentication, ownership lookup and an active entitlement; a subscriber has 30 days of read-only restoration after expiration. Deletion remains available after expiration. This 30-day grace period is an MVP design assumption, **not a commercial retention promise**. No automatic media purge is implemented.
- Optimistic project revisions reject stale writes (409); client should keep its local version, offer user conflict resolution and never overwrite silently.

## cPanel deployment (no server APIs exposed to mobile apps)

1. Create an SSL-enabled subdomain such as `api.your-hotice-domain.example` through **cPanel > Domains** and ensure HTTPS. Do **not** deploy to an HTTP-only domain.
2. Set the **document root specifically to** the uploaded `backend/public/` directory. Keep `backend/config.php`, `backend/src`, `backend/bin`, `backend/private-media` **outside any publicly reachable directory**. **Never upload the entire `backend/` directory into `public_html/` and leave it web-browsable.** If cPanel does not permit an isolated document root, use a secure symlink/alternate hosting arrangement or stop deployment until isolation is verified.
3. In cPanel **Select PHP Version**, choose **PHP 8.2+** and enable `pdo_mysql`, `fileinfo`, `openssl` (if available). `json`, `filter`, and `hash` are standard PHP functionality. Set the subdomain version independently if applicable.
4. In cPanel **MySQL Databases**, create a database and a **dedicated least-privilege SQL user**, grant it needed privileges; don't put DB passwords in Git.
5. Set `public_webroot_path` in your private `backend/config.php` to the **real cPanel document root** (normally `/home/ACCOUNT/public_html`) in addition to the API's own `backend/public`. Install and HTTP runtime now reject storage directories inside **or enclosing** either public directory (including symlinks). If the configured root cannot be verified, installation fails safely. Copy `backend/config.example.php` to `backend/config.php`, fill DB settings and generate a **different cryptographically random app key** via `php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"`. File permission 0600 if possible. Leave `allow_registration=false`, `require_https=true`. Provider API keys (when needed) go **only in this private config / server-only environment**, not the Android APK or responses.
6. With cPanel Terminal/SSH, run `php backend/bin/install.php` from your app parent directory (set paths appropriately). Or import `backend/schema.sql` through **phpMyAdmin**, then separately create a private storage directory **outside public/** with permissions for PHP. All scripts under `backend/bin/` are CLI-only.
7. For a first testing account, from Terminal run `php backend/bin/create-user.php you@example.com`; the password is prompted via stdin, **never entered in a shell argument**. Use `php backend/bin/grant-trial.php you@example.com 100 7` to grant a **100 MiB, seven-day ADMIN TEST TRIAL**, not purchased storage. Real paid entitlements must later be granted only from verified billing webhooks.
8. Check `https://api.your-hotice-domain.example/health`; it should return JSON service/status without secret values. Test login with `POST /v1/auth/login` only over HTTPS. Check wrong/expired tokens and inactive cloud entitlement respond with 401/403. Check that direct requests for `config.php`, `schema.sql`, private media and secret keys are **not publicly accessible**, including via URL encoding and alternate hostnames.
9. Optionally run `php backend/bin/cleanup.php` via cPanel Cron no more often than **once per 5 minutes** (daily is sufficient for expired session cleanup). Background AI job rendering **must not run long GPU workloads on shared hosting**; use external async provider jobs and periodic polling with budget limits in later phases.
10. Set cPanel/database backups and recovery plan before allowing real user uploads, plus TLS renewal, monitoring, user deletion/export policies, email verification, privacy notices and quota/cost controls. This is an MVP, not a certified GDPR or payment deployment.

### Endpoint contract

| Method/path | Function |
| --- | --- |
| `GET /health` | Service check (no secrets) |
| `POST /v1/auth/register` | Disabled in production defaults; prereq email verification + anti-abuse |
| `POST /v1/auth/login` | Password -> random short-lived bearer token, SHA-256 stored server-side |
| `POST /v1/auth/logout` | Revoke active session |
| `GET /v1/auth/sessions` | List up to 100 active sessions belonging to the authenticated user; identifies the current session |
| `DELETE /v1/auth/sessions/{uuid}` | Revoke one of the authenticated user's active sessions; other users' and expired sessions return 404 |
| `GET /v1/me` | User identity and **server-calculated** cloud status/quota |
| `GET /v1/models` | Authenticated server-authoritative availability manifest; currently dry-run only |
| `GET /v1/projects` | Cloud project metadata list (active or 30-day read-only grace) |
| `GET /v1/projects/{uuid}` | Snapshot and file metadata |
| `PUT /v1/projects/{uuid}` | JSON `{ "title": "Film", "expectedRevision": 0, "document": { ... } }` -> revision 1, returns 409 if stale |
| `DELETE /v1/projects/{uuid}` | Remove own cloud snapshot and linked media, decrement quota |
| `PUT /v1/projects/{uuid}/files/{uuid}` | Raw binary bytes; private upload with quota and MIME validation (max 20MiB) |
| `GET /v1/files/{uuid}` | Authenticated private download |
| `DELETE /v1/files/{uuid}` | Remove own media and reclaim quota |

**Security rules:** HTTPS required by default, JSON body size limits, `password_hash`, per-email+IP login attempt throttle, sessions store token hashes only, session inventory and revocation are scoped to the authenticated account, constant-type errors avoid sensitive SQL leakage, PDO prepared statements, real owner ID in every query, UUIDv4 IDs, revision conflict checks, per-user transactional cloud quotas, media type inspection using `finfo`, random file names, files outside web root, no permissive CORS and no hardcoded provider keys. The app must store access tokens using OS secure storage when integration starts.

The `/v1/models` response is authenticated and server-authoritative. The current release only advertises `hotice.mock.video.v1` when the private server setting allows mock jobs and the owner-controlled feature flag is enabled. It reports no output media and always states that live provider generation is disabled. Stored API keys and research catalogs never enable a model by themselves. The owner override cannot bypass the server master gate; pausing blocks quotes, submissions and the CLI worker while preserving authenticated job inspection and cancellation/refunds for queued dry runs.

### Test locally / in CI

```sh
find backend -name '*.php' -print0 | xargs -0 -n1 php -l
php backend/tests/smoke.php
```

GitHub Actions `HOTICE PHP Backend Security & API` also spins up an ephemeral MySQL database, a localhost test server with **HTTP permitted only in CI**, and exercises auth, cloud gate, project revision conflicts, private file upload/download/deletion, logout.

### Known unfinished requirements

- Flutter integration for local SQLite/secure storage plus optional cloud login/sync; user consent and explicit backup selection.
- Registration email verification, password reset, abuse protection/CAPTCHA, real account lifecycle, token refresh/rotation, multi-device session management.
- Payment provider webhook signature verification, idempotent credit ledger, subscription renewal/cancel/refund and server-controlled plan catalog.
- AI model proxy/provider adapters, secure file signing, async job queue/callback verification, token/cost reservation and reconciliation.
- Large media uploads with chunking/object storage; cloud-client encryption if required; retention, antivirus/file scanning, abuse review, legal/compliance, disaster recovery, capacity scaling, physical-device testing.

## Security hardening audit — 28 October 2026

- Login and registration failure throttling now tracks **separate HMAC-hashed email and REMOTE_ADDR budgets** (12/email, 50/IP per rolling 15 minutes). Successful login clears its own email failure counter only, **not** the IP counter. Use scheduled `bin/cleanup.php` to expire records. For distributed abuse, add a trusted edge/WAF; this in-database throttle is only one layer and may treat multiple clients sharing NAT as one IP.
- Media storage is validated using canonical `realpath` and checked against the actual PHP `DOCUMENT_ROOT`, configured cPanel `public_webroot_path`, and the app's `backend/public` directory. Both nested webroots and parent directories are rejected. **Never choose `public_html`, a subdirectory of it, or its parent as media storage.** Installer checks before running SQL migrations.
- Application keys and personal media still require protected cPanel backups, file permissions, proper SSL, and a real deployment security review. Existing paid cloud entitlement is not real subscription billing.


