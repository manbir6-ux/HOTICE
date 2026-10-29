# HOTICE

HOTICE is a Flutter application for planning cinematic AI video projects. This repository contains the client, a PHP/MySQL API for account services, and deployment and verification tools. It is an active MVP, not a production video-generation or payment service.

## Current capabilities

- Normal Video and Music Video Studio planning flows, with local project and storyboard editing.
- Encrypted, device-private project metadata snapshots with recovery handling. Generated media bytes are not included in this archive.
- Guest workspaces and optional API-backed sign-in. Signed-in appearance preferences sync through the API.
- Server account export and password-confirmed deletion, with secure token storage in the client.
- PHP/MySQL account API, authentication protections, cloud metadata endpoints, and deployment tooling.
- Music file selection and local audio preview where supported by the device. Song transcription, timed lyrics, AI scene planning, and video rendering are not connected.

## Build and run

Install Flutter and the platform toolchains, then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

To enable server sign-in in a staging build, configure an HTTPS API origin:

```sh
flutter build apk --dart-define=HOTICE_API_BASE_URL=https://api.example.com
```

See [Backend authentication and client setup](docs/BACKEND_AUTH_CLIENT.md) for server provisioning and session details. Keep database credentials and any provider secrets on the server; do not put them in the Flutter app or commit them.

## Important limits

- AI model entries and generation costs are not live provider catalog data. No video generation jobs, transcription pipeline, or export renderer is connected.
- Credits and payment methods are previews. There is no checkout, subscription webhook, or production credit ledger.
- API-backed accounts do not imply that project files or prompts are uploaded. Project data remains in the encrypted device archive; cloud synchronization is not implemented.
- Account export covers server-held account metadata. Device-local projects and media need a separate device backup.
- Before public release, complete verified payments, email verification and recovery, privacy and abuse controls, backup/restore drills, Android/iOS device QA, and production deployment checks.

Read [Development progress](docs/PROGRESS.md), [Security and UX audit](docs/AUDIT_SECURITY_UX_2026-10-28.md), and [Next-model handoff](docs/CONTINUE_HERE.md) before making release claims. A source change is not evidence of a passing build or deployed service; check the latest CI and staging results.
