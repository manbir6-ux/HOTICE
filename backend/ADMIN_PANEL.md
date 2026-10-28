# HOTICE owner console (staging MVP)

The owner console is served at `https://api.your-domain.example/admin.php`. It is a first production-oriented slice of the planned admin panel; it does not make the backend or product ready to publish.

## Install and provision

1. Deploy the API with `backend/public/` as the isolated document root, use HTTPS, and configure `backend/config.php` outside that root. Keep the application key backed up securely: encrypted provider keys and TOTP secrets cannot be recovered if it is lost.
2. Rerun `php backend/bin/install.php` after deploying the new code. The schema uses additive `CREATE TABLE IF NOT EXISTS`; existing account/project data remains intact.
3. From cPanel Terminal, run `php backend/bin/create-owner.php owner@example.com`. Enter a unique password at the private prompt. Add the printed one-time `otpauth://` URI (or secret) to a trusted authenticator and store recovery material in the owner's private password manager. The provisioning command is the only public way in this version to create an owner; public registration creates regular app users only.
4. Open `/admin.php` over HTTPS and sign in with password plus the current six-digit TOTP code. The console uses a separate Secure, HttpOnly, SameSite=Strict cookie, rotates the session ID at login, expires it after 30 minutes idle or 12 hours absolute, applies CSRF tokens to POST actions, throttles failed attempts by keyed email/IP fingerprints and records security-relevant changes without recording credentials. The existing cleanup cron also removes old throttle records.
5. Provider keys are AES-256-GCM encrypted before database storage, with a key derived from the private application key and provider-specific associated data. The UI never reads a key back; it only displays configured status, allows replacement or removal, and writes audit events. Provider adapters must retrieve and decrypt a key only in server memory; no client endpoint or logs may expose it. No live provider integrations are enabled by this console.

## Current scope

- Owner password + TOTP sign-in; no public owner enrollment.
- Encrypted server-side provider-key configuration for OpenAI, Google, Runway, and ElevenLabs.
- Read-only counts for users, cloud entitlements, projects, and private media records; recent admin audit events.
- Honest queue status: no asynchronous generation queue exists yet.

## Still required before public release

The console does not yet provide user/role administration, verified subscription or credit controls, uploads/jobs moderation, model capability/cost editing, feature flags, service telemetry, MFA recovery, multiple-owner governance, or independent monitoring. Provider-key rotation and restore drills, cross-account authorization tests, cPanel staging acceptance, backups and key escrow remain required. Do not enter real production provider credentials until staging controls and a security review are complete.

After the CLI prints the authenticator setup URI, treat it as a one-time secret. The TOTP seed and provider secrets are encrypted in MySQL, but backups still require restricted access and retention. Do not paste keys into support tickets, issue comments, or app builds.
