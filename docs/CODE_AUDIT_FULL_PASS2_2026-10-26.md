# HOTICE — Full Code & Security Audit (Pass 2)

**Audit date:** 26 October 2026 · **Repository:** `parmtech/HOTICE`  
**Code branch:** `fix/full-code-audit-2026-10-26` · **PR:** [#19](https://github.com/parmtech/HOTICE/pull/19), **stacked on PR #17 (which depends on #16 and #11)**. This report is a source/CI assessment, **not** a production security certification or a complete independent penetration test.

## Audit scope and evidence

Reviewed the GitHub source tree and principal execution flows across:
- Flutter app entry/routing, welcome/responsiveness, account/demo workspaces, scene and music composers, Actor setup/camera capture, face guidance/quality, multi-Actor reference adapters, Inspiration catalogue, dialogs, diagnostics, advanced model metadata.
- Browser marketing, template/actor handling, local video editor, CSP/Apache `.htaccess`, HTML/JS/Python content-rights checks.
- PHP Gemini Omni request-builder, Python external 3D reconstruction and Blender export bridge.
- GitHub Actions unit/widget/static checks, Android emulator, APK build and test inventory.

CI is the authoritative source of compile/test results. Real front-camera hardware, paid AI API calls, licensed 3D model inference, actual GLB conversion, account MFA, provider billing and malicious-client pentesting are **not** executed by the existing CI.

## Confirmed bugs and fixes in PR #19

| Priority | Area | Finding / reproduction condition | Fix / regression coverage |
| --- | --- | --- | --- |
| HIGH | Flutter projects / actor privacy | Switching projects saved only the prompt; live Actor cast, local face reference metadata, negative prompt, seed, model/duration/settings stayed from the previous film. This could attach the wrong Actor to another project. | `_ProjectEditorDraft` snapshots **all** fields per project; new `test/project_editor_isolation_test.dart` verifies cast/media cannot follow a second project and restores correctly. |
| HIGH | Flutter async save | An in-progress montage/file preparation could overlap project switches or repeated Save, pairing stale Actor references with a different scene. File I/O exceptions were not handled; an orphaned composite could remain when navigation disposed the editor. | Guard duplicate save with `_savingDraft`; freeze an immutable editor snapshot and prevent editor interaction during save; verify project ID before committing, and remove unused temporary sheet in `finally`. Handle `FileSystemException` and `FormatException` with user-visible retry messages. |
| MEDIUM | Browser editor | Reordering *another* clip always selected the moved clip rather than preserving the user's previously chosen clip; rapid clip selection could retain stale `loadedmetadata` callbacks. | DOM-free `timeline_core.js` preserves selected object identity; clear stale metadata callback; Node regression tests verify moves, boundaries and invalid inputs. |
| MEDIUM | Browser file-import | Video metadata probe could retain its Blob URL after an error. Very large multi-selection could cause browser overload. | Clear probe source on errors and cap one import batch at 30 clips (local prototype only). |
| HIGH | PHP media trust | Arbitrary base64 could masquerade as a valid JPEG/PNG, then be copied into a future billed model request. | `getimagesizefromstring` checks decoded magic/MIME and sane dimensions/pixel count; tests now use a real tiny PNG and reject fake/spoofed data. **This is not a substitute for a secure signed upload pipeline or malware scanning.** |
| HIGH | Private 3D worker | External inference outputs had no output byte cap, and sidecar file symlinks could copy unrelated private filesystem contents. | Reject symlinked target/mesh/sidecars, cap mesh to 40MB and total output to 64MB, validate before copying and clean staged files. Synthetic subprocess tests added. |
| MEDIUM | GitHub Actions | Rapid commits launched many expensive concurrent Android emulator/SDK builds; main run 40277159085 failed in emulator SDK ZIP download, not in a Flutter assertion. | New CI concurrency group cancels superseded runs per PR/ref; keep latest build and emulator status visible. |
| LOW / DEBT | Dart static analysis | Previous CI had **41 informational warnings** (deprecated `withOpacity`, `DropdownButtonFormField.value`, interpolation/brace style, unnecessary import). No analyzer errors in the last green Flutter validation. | Tracked as technical debt; warnings are **not** all cleaned in this pass and should not be called zero-issue. |

## Known outstanding risks — do not call production ready

### Blocking security / backend
1. There is **no** production Namecheap installer, admin MFA, authenticated user backend, API key vault, production credit reservation, per-user access controls, signed file upload or secure generation job broker. Pure PHP request builder is **not a public endpoint**; never embed provider credentials in Flutter/web apps.
2. Actor face photos/contact sheets are **temporary unencrypted local files**, cleared on startup and deletion where possible. No encrypted long-term vault, cross-device sync, retention policy, verified biometric liveness or secure import/export exists. Do not deploy biometric capture as a production identity system yet.
3. Python 3DDFA/Blender scripts are optional orchestration code; **no pretrained model weights were deployed and no real 3D face inference/GLB visual QA was performed**. Separate commercial weight/data licence review and isolated compute worker needed.
4. Model capabilities/prices are **illustrative preview presets**, not signed server policy nor live provider pricing. Gemini Omni developer request schema still needs live provider contract verification before real requests.

### Mobile device and UX
5. The user's phone reported reversed selfie left/right directions and stretched preview previously. Code normalizes selfie yaw and crops without stretching, but mirror convention, seven pose thresholds, actual high-quality still capture, live camera stream resume, camera denied/revoked lifecycle and lighting need **physical Android/iOS QA**.
6. Some Flutter Actor reference files are **metadata-only** placeholders; without an authenticated storage adapter there is no actual video-model upload. Missing files are handled for local Actor JPEG rendering, not for real provider generation.
7. Actor rename may leave pending scene-name references stale (reference by display name, not stable UUID). Persistent per-Actor IDs and migration are needed for robust import/export and external synchronization.
8. The seven-view scan has local exposure/detail **heuristics**, not calibrated optical sharpness, landmark/eye-state or occlusion assessment; no optional beauty touch-up/reversible variants yet.
9. Browser editor remains local import/preview/trim/reorder. **Export is intentionally disabled**, and browser codec/memory behaviour varies; no server render/upload or timeline persistence.

### Server / external worker hardening still pending
10. Real production worker needs sandbox/container isolation, resource quotas, image/geometry format parsing limits, audit/redaction, encrypted job directories, strict output-root allowlisting, symlink/race-safe file handles, deletion and failure recovery. This pass reduces obvious disclosure risks but does **not** make executing external model code safe by itself.
11. Browser `localStorage` only holds demo Actor **names**, with no server auth. The public site's template catalogue currently includes HOTICE-authored text only; approved licensed embeds and rights enforcement must be built server-side.
12. The debug diagnostic stack trace/report may contain local paths or future sensitive values; gate or sanitize before production release and avoid logging face images, credentials or provider payloads.

## Test gates and how to verify

- `flutter analyze --no-fatal-infos`; `flutter test test/` including `test/project_editor_isolation_test.dart`.
- `node --check web/public/assets/site.js` and `timeline_core.js`; `node web/tests/timeline.test.cjs`.
- `python3 tools/check_web.py` for cPanel/static asset rights constraints; `python3 -m unittest discover -s workers/actor3d/tests -v`.
- `php -l server/src/GeminiOmniPayload.php` and `php server/tests/test_omni_payload.php`.
- `flutter build apk --debug` and Android emulator app-navigation smoke test in GitHub Actions.
- **Required outside CI**: device face-angle calibration, camera image orientation/blur, permission restart/resume, Actor photos and delete, post-montage upload sandbox and real 3D/AI integration staging security review.

### Verification snapshot

- Upstream PR #17 full build [Actions 40282055946](https://github.com/parmtech/HOTICE/actions/runs/40282055946): **all four jobs passed** (Flutter, static web/PHP/Python, Android APK and emulator), before these audit changes.
- Initial audit branch [run 40283044748](https://github.com/parmtech/HOTICE/actions/runs/40283044748): Flutter and static web passed with **55 Flutter tests**; newer commits add PHP strict media checks and private 3D tests.
- The first 3D security test-run revealed a **test fixture bug**: Python subprocess fixture wrote literal `\\n` rather than line breaks; this was corrected in audit commit `490e3703`. Do not claim a full green run from the failing fixture.
- **Check the HEAD run for PR #19** before reporting final test counts and APK availability: https://github.com/parmtech/HOTICE/pull/19/checks. Document its exact run ID/commit once completed; a queued/in-progress job is not a passed job.

## Sign-off and next steps

**Audit status: source scan + targeted regression fixes committed; no production sign-off.** The first priority remains real-phone camera quality and identity safety, followed by stable Actor IDs and encrypted vault, then authenticated Namecheap admin/API control plane, licensed 3D worker deployment, verified provider adapter pricing and browser editor exports. Do not merge stacked PRs until each parent branch has passed its required checks and phone privacy review.

For next handoff, keep [docs/UPDATES.md](https://github.com/parmtech/HOTICE/blob/main/docs/UPDATES.md), [PR #19](https://github.com/parmtech/HOTICE/pull/19), [Issue #13](https://github.com/parmtech/HOTICE/issues/13) and [Issue #18](https://github.com/parmtech/HOTICE/issues/18) synchronized.
