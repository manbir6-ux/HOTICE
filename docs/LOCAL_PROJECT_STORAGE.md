# HOTICE device-local project storage

The Flutter app stores small project snapshots in the operating system's
application-support directory. The snapshot is encrypted with AES-256-GCM;
the 256-bit key is stored separately through `flutter_secure_storage` using the
platform keystore/keychain. The archive uses a versioned JSON envelope and
keeps the previous authenticated snapshot as a recovery copy. Writes are
serialized so rapid edits cannot reorder the saved snapshots.

The snapshot contains project titles and dates, actor names and identity notes,
scene prompts and settings, reference-file metadata, storyboard text, and local
appearance settings. It does not contain API credentials, server session
tokens, subscriptions, credits, or raw image/audio/video bytes. Media-file
storage and restoration are separate work and are not implemented by this
archive. The archive is limited to 2 MiB of clear project metadata.

If the key is missing or neither the primary archive nor its recovery copy can
be authenticated, HOTICE stops before opening the studio and leaves both files
untouched. It does not create a replacement key or silently initialize an
empty workspace over unreadable data. This protects against accidental data
loss, but it does not provide cross-device backup or key recovery. Device
backup/restore behavior must be validated on each supported OS before release.

This local archive is independent of cloud sync. Cloud upload remains an
explicit, revocable operation and requires server authorization. A local
snapshot is not a server account, cloud entitlement, or backup guarantee.

## Validation

Run the archive-focused suite with:

```sh
flutter test test/local_store_test.dart
```

The tests cover encrypted restart restore, all persisted scene draft settings,
per-workspace isolation, recovery from a damaged primary file, and fail-closed
behavior when the device key is wrong. Physical-device keystore backup and
restore acceptance remains a release gate.
