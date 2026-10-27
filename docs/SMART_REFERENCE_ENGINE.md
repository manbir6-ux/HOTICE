# HOTICE Smart Avatar & Reference Engine — implementation status

**Date:** 28 October 2026  
**Feature branch:** `feat/smart-avatar-reference-engine`  
**Status:** Offline planner + Android/iOS live guided 2D camera capture implemented in source; NOT a 3D reconstruction, liveness/biometric identity verification, encrypted vault, cloud backup, or connected AI generation adapter. Live camera behaviour awaits real-device field testing.

## Live camera capture added 28 October 2026

- `lib/src/live_face_capture.dart`: on-device Camera2/NV21 on Android or BGRA on iOS, ML Kit face detection, yaw/pitch/roll guidance, face count/framing, front-view eye-open checks, sampled exposure/detail heuristics and three good frames required before automatic still capture.
- After each shutter, reruns ML Kit on the actual captured still and rejects missing/multiple faces or front-view closed eyes.
- Capture requires explicit consent; five photos (front, two 45-degree, two profiles) are saved only to a temporary app cache, then added to the chosen Actor identity reference pack on confirmation. Cancelling and removal clean up app-owned temporary images where possible.
- Camera lifecycle pause/resume handling, streaming throttling, capture reentrancy guard, retries and user-controlled yaw mirror reversal. No selfie audio.
- Prominent Live face capture tab in Avatar Studio, with a character selector, separate from the original nonfunctional 3D scan guide.
- `tools/configure_face_capture.py`: idempotent Android permission and iOS 15.5 camera/privacy configuration after ephemeral Flutter scaffold generation.
- Unit tests cover eye-open and pose gates, poor framing, lighting and three-frame stability. CI and device results must be checked per commit.

**Do not call this full 3D scanning.** ML Kit face detection estimates pose and face features, not an accurate textured 3D reconstruction or identity guarantee. Image sharpness/exposure heuristics are not calibrated across device cameras, and selfie yaw may need inversion.

## Implemented in this branch

- `lib/src/smart_references.dart`: typed `AvatarReference`, `AvatarAssetPack`, `ReferenceModelCapability`, `SmartReferencePlanner`, and immutable selection output.
- Explicit face-reference image import (JPG/PNG/WebP under 15 MB) from Avatar Studio, manually tagged front, 45°, profile, up and down.
- Session-only, per-demo-account avatar reference metadata and project-scoped scene image metadata. Avatar rename migrates reference ownership; deleting an avatar or project removes the metadata in that workspace.
- Normal Video composer: select Actor, import location/prop/style photos, auto-plan from camera direction in one free-text prompt, manual selection, pin/clear references and inspect preview/warnings.
- The planner prefers scene-compatible angle, normally at most two automatic avatar images, then leaves room for location/objects.
- Models can be described with verified formats and numeric attachment/mesh limits. **Current demo models provide ONLY explicitly unverified simulated limits**; no generation API is called.
- Native GLB asset selection **inside the planner only** if a verified model capability enables it and a real GLB record is supplied. **No GLB generation, face scan or upload is implemented.**
- Invalid locks, missing/duplicate IDs, wrong avatar owner and unconsented identity references are errors, not silent substitutions.
- Draft stores an immutable ID snapshot; it does NOT upload photos or perform identity recognition.

## Important limitations

The app's current FilePicker integration returns platform-dependent temporary paths. Source images are **not copied into an encrypted persistent vault**. After app process death, OS cleanup or sign-out, references may no longer exist. Manually imported photos are **not** quality-assessed or converted to 3D. The separate new live scanner uses ML Kit face detection and open-eye checks, but this is neither biometric identity validation nor anti-spoof liveness detection. Do not label either capture method a 3D mesh scan.

Four image slots in `ReferenceModelCapability.demo` are a **UI simulation**, not an official provider capability. No model adapter should read the demo limits as true. Neither the backend nor real generation endpoint currently accepts these reference plans. The planner's `canSubmit` is false for unverified profiles. No vendor input is silently inferred from the extension.

A production implementation must separately verify the server's account authorization, consent, byte size, MIME-by-file-signature, media ownership, model capabilities, pricing/entitlement, expiry and model provider API specifics. A front camera image cannot be claimed to provide a high-fidelity 3D head mesh without reconstruction and quality validation.

## Next implementation sequence

1. Validate the implemented guided camera capture on physical Android/iOS devices (native orientation, ML Kit yaw, eye confidence, lighting, autofocus, repeated sessions, permission rejection, foreground/background, temporary-file deletion); calibrate pose/blur heuristics. Camera2 is preferred on Android for NV21 compatibility.
2. Encrypted device-local media vault with private storage (not picker cache paths), per-account keys, deletion, local backup/recovery controls, and retention options.
3. Multi-view reconstruction pipeline with transparent confidence and RGB-photo fallback; actual GLB/GLTF export and photorealistic side render derivation.
4. Signed, least-privilege optional paid-cloud sync through Namecheap cPanel PHP/MySQL backend; secrets always server-side, opt-in for facial data.
5. Verified/versioned per-provider catalog served by backend with reference type/size/count semantics, server-side attachment packer and safe transforms. No fake 3D handling.
6. Real-generation API tests: identity stability across angles, skin details, clothing/scene/style limits, multi-character cases, unsupported formats and cancellation.
7. Flutter CI, Android APK and real-device testing including file permission/cancel/reopen and temporary file lifecycle.

## Data and privacy contract

- Model response/prompt includes *no local file path*, biometrics, or raw face embedding.
- User manually locked attachments are never swapped without an explicit error.
- All identity media requires explicit user action/consent; real biometric capture needs a stronger capture-specific consent and deletion workflow.
- Do not persist a profile's references to another demo account.
- Model price remains unavailable, not free, until verified and configured. One HOTICE Credit remains USD 0.01.
- HOTICE is the product brand; keep the single prompt field and the existing Normal Video / Music Video Studio workflows.
