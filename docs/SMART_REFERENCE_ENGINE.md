# HOTICE Smart Avatar & Reference Engine — implementation status

**Date:** 28 October 2026  
**Feature branch:** `feat/smart-avatar-reference-engine`  
**Status:** Working offline planner/source implementation; NOT a functioning camera scan, native 3D reconstruction, authenticated vault, cloud backup or AI generation adapter.

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

The app's current FilePicker integration returns platform-dependent temporary paths. Source images are **not copied into an encrypted persistent vault**. After app process death, OS cleanup or sign-out, references may no longer exist. Imported photos are **not** quality-assessed, biometric-verified or converted to 3D. There is **no** facial landmark/detection or eye-blink check yet. Do not call the five-angle guide a live scanner.

Four image slots in `ReferenceModelCapability.demo` are a **UI simulation**, not an official provider capability. No model adapter should read the demo limits as true. Neither the backend nor real generation endpoint currently accepts these reference plans. The planner's `canSubmit` is false for unverified profiles. No vendor input is silently inferred from the extension.

A production implementation must separately verify the server's account authorization, consent, byte size, MIME-by-file-signature, media ownership, model capabilities, pricing/entitlement, expiry and model provider API specifics. A front camera image cannot be claimed to provide a high-fidelity 3D head mesh without reconstruction and quality validation.

## Next implementation sequence

1. On-device CameraX/Flutter camera integration, face landmarks/pose/eye/lighting and blur quality gates, guided auto-capture, retry and user consent.
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
