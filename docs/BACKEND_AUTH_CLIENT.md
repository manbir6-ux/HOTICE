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
