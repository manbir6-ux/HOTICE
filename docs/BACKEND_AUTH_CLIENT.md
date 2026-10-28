# HOTICE Flutter API sign-in

The Flutter client has a real server sign-in flow for the cPanel API. It remains separate from the guest demo and from device-local project storage.

## Configure a staging build

The API address is public endpoint configuration, not a secret. Supply an HTTPS origin when building a staging app:

```sh
flutter build apk --dart-define=HOTICE_API_BASE_URL=https://api.example.com
```

Local development may use `http://localhost` or `http://127.0.0.1`; Android emulator routing and cleartext policies need separate configuration. Never use HTTP for a real account. If the API address is empty or invalid, server sign-in is disabled and the guest demo remains available.

Create a staging-only account on the server with `php backend/bin/create-user.php address@example.com`; enter its password through the private prompt, never as a command argument. Public registration is disabled by default. This currently has no email verification, password reset, MFA, or self-service enrollment flow, so it is not a complete production account lifecycle.

## Session behavior

- Sign-in posts email and password to `/v1/auth/login` over HTTPS, then verifies the returned bearer token using `/v1/me` before saving it.
- Passwords are not stored. The bearer token is stored through `flutter_secure_storage` and is excluded from encrypted project snapshots.
- Redirects are disabled for login and authenticated requests to prevent credentials or bearer tokens being forwarded to another URL.
- Startup validates a stored token with `/v1/me`. A revoked token is deleted; a network failure preserves it for a later sign-in attempt.
- Sign-out calls `/v1/auth/logout`, removes the local token even when offline, and warns that server revocation could not be confirmed. The session then remains valid until its configured server expiry.
- Authenticated users still work in a device-local workspace. This client does not upload projects, files, avatar references, or prompts to cloud storage; cloud sync remains a separate consent-based integration.

## Verification limits

Automated HTTP tests use mock responses to verify request paths, HTTPS, redirects, token handling, account identity, revocation and failure behavior. They do not prove a deployed cPanel API, real user provisioning, email verification, account recovery, MFA, production rate-limiting, or cloud sync. Validate against a private staging server before enabling sign-in in a public build.


## Authenticated job dry run (staging only)

The Generate workspace has a separate **Server dry run** tab. It requires both a configured API origin and a server-verified sign-in. It posts a mock-only request to `POST /v1/jobs/quote`, then `POST /v1/jobs` with an idempotency key. The user can refresh or cancel a queued job. Polling/status access uses the same short-lived bearer token held in OS secure storage; tokens and prompts are never written to device project archives or diagnostic logs.

The only model accepted is `hotice.mock.video.v1`. The backend must have `mock_jobs_enabled=true`, which is intended only for controlled dry-run environments. This path creates no media, contacts no model provider, does not use real paid credits, and does not send project/avatar files. A disabled server rejects the operation. Do not enable the mock flag on a public production service.

CI tests validate request paths, bearer headers, idempotency header, job parsing, poll and cancel calls with mocked HTTP. The backend MySQL integration separately validates the real API and worker lifecycle. This does not prove cPanel deployment or live provider generation.


## Static web build and cPanel

CI builds the Flutter web bundle as a separate artifact. To build it for a real cPanel API, use the HTTPS API origin at build time:

```sh
flutter build web --release --dart-define=HOTICE_API_BASE_URL=https://api.your-domain.example
```

Upload the contents of `build/web/` to the web app's document root. Configure the API subdomain separately with `backend/public/` as its document root, and keep PHP source, configuration, database dumps, and private media outside all public roots as described in `backend/README.md`. The API origin is public configuration and is not a secret. Never compile provider keys, database passwords, session tokens, or payment credentials into the web bundle. A same-origin or cross-origin deployment must be tested with HTTPS and the intended browser security policy before opening public sign-in.
