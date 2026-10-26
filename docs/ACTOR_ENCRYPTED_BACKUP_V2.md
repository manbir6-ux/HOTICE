# HOTICE Actor backup v2 — password encryption and device testing

**Feature branch:** `feat/actor-backup-v2` · [PR #24](https://github.com/parmtech/HOTICE/pull/24) · Parent [camera/vault hardening PR #21](https://github.com/parmtech/HOTICE/pull/21). Do not merge out of order.

## What is implemented

- **New Actor exports** are no longer plaintext ZIPs: the 1–12 approved Actor JPGs, metadata and natural/original photos are first placed in the validated internal HOTICE Actor ZIP; the entire package is then encrypted with **AES-256-GCM**.
- Every archive uses a random **128-bit PBKDF2 salt** and unique **96-bit AES-GCM nonce**. Passwords are stretched with PBKDF2-HMAC-SHA256 using **180,000 iterations**. GCM authenticates the data and denies tampered/wrong-password imports.
- The exported `.hoticeactor` binary is **not directly openable as a ZIP**. The first five bytes are `HACE2`. Users choose and confirm a 12–256 character password for export and need the same password to import. The password is not saved or uploaded.
- **Import migration:** old unencrypted HOTICE ZIPs remain readable only after an explicit separate warning and approval. Password-encrypted imports are authenticated and decoded *before* any face JPEG is written to the local temp folder. Unrecognized formats are rejected.
- Validated imports are still saved to the existing per-device authenticated Actor vault on Android/iOS; no cloud, third-party identity API or official Google Flow Character export is implied.
- Privacy note: temporary decrypted face photos are needed during the session, encrypted backups are only as strong as their password, and a compromised/unlocked phone can still expose preview images. Passwords **cannot be reset/recovered**; store them separately from the backup.
- The existing password-unprotected ZIP remains available only for *importing older data*, not for new export in this feature.

## Tests and device acceptance

- `test/actor_transfer_cipher_test.dart` checks real JPEG data round-trip through ZIP → KDF → AES-GCM → ZIP, unique random salt/nonce, wrong passwords, one-byte tampering, short passwords and truncated records.
- `test/actor_backup_password_dialog_test.dart` checks export password validation/confirmation and import password entry, without camera hardware.
- GitHub CI additionally compiles Android debug APK and runs an emulator navigation/vault test, but the OS file chooser and human-face camera remain **physical device acceptance items**.
- Physical-device checks: export, close app, choose archive from Files, type wrong password (no Actor added), type correct password (photos restored), retake/export/import one 7-photo Actor, test older unencrypted ZIP warning, and confirm exported `.hoticeactor` does not open in a normal ZIP browser.
- Android File Picker provider differences may require device-specific testing. No backup bytes are sent to an external site.

## Production blockers

- This does **not** implement an AR depth map, personalized 3D mesh, full-body motion actor, face recognition/liveness or third-party video-model identity guarantee.
- Demo email accounts have no real server login, MFA or multi-user authentication. Do not share a device and treat separate demo accounts as a verified access-control boundary.
- A production Actor cloud service, licensed 3D inference, actual Gemini Omni video backend and server-side secure billing/admin are still **not configured**.
- No automatic cloud restore or Keychain/Keystore key backup exists; removing/reinstalling the app may make on-device Actor vault files unrecoverable. Use a known-good encrypted Actor export for portable copies.

**Release rule:** A CI-green debug APK is a *device-test preview*, not a proven biometric product. Require physical Android capture/retake + secure chooser tests before merge.
