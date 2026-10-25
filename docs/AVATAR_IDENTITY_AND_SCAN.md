# HOTICE Avatar Identity & 3D Capture — implementation contract

**Current status (26 Oct 2026):** the app includes a local **Avatar Studio** with editable reusable identity notes, a five-angle **capture preparation guide**, and prompt composition with every **demo** video-model profile. This is **not** an operating camera, real 3D scan, biometric match, or a guarantee of character likeness across vendor models. No face photo or raw biometric is collected. Nothing is uploaded. All demo data disappears when the app process is restarted.

## One-character, many-model workflow

The user's intent is a **single character identity** reused through Normal Video and Music Video Studio. This must not silently change facial features between scenes merely because a provider changes. The current prototype serializes an identity card into a saved scene draft with `AvatarPromptComposer`; it does not make providers obey it.

In production, treat this as a **versioned identity package**, **not only an injected English prompt**. Suggested contract:

- `identity_id`, `owner_id`, `version`, `consent_version`, `created_at`
- Canonical name, user-authored appearance notes, stable hair/outfit/wardrobe variants, visual-style hint
- Validated front/left/right reference images; optional expression and body references
- Optional actual 3D geometry, UV/texture, neutral rig and expression landmarks **only where feasible**
- Encrypted asset references, per-asset permissions, expiry/deletion status, and source provenance
- Compatibility metadata for each output model/version: accepted attachment types, max input sizes, identity-reference mode, tested consistency level, and required transformations
- No raw face embeddings or likeness derivatives included in analytics, logs, URLs, or client-facing prompt strings

**Critical rule:** a model name or a text instruction is never evidence of consistent face recreation. Real support requires a measured, tested reference-image/identity-asset workflow for that specific model and version. Where the provider lacks such support, show **Text guidance only / consistency not guaranteed**, not a misleading "face locked" badge.

## Future guided multi-angle capture (not active)

1. Explicit consent and plain-language data retention statement before camera access. Provide a manual character route and a clear **Not now** choice.
2. Local device capture guide with front, left 45°, right 45°, neutral/smile and optional full-body reference; responsive framing grid and lighting instructions.
3. On-device quality checks: exactly one face, blur, glare, occlusion, insufficient exposure, angle coverage, landmark confidence and repeat prompts. Only save a step after an actual verified capture, not by clicking Next.
4. Where the hardware permits, estimate depth/mesh. Standard RGB phone cameras do **not** yield an accurate 3D face automatically. Label confidence and provide a 2D multi-view fallback. Do not invent dimensions or claim "perfect 3D".
5. Show a consented human-editable identity review: features, mesh/reference preview (if available), scene-compatible styles, optional hair/wardrobe variations, and redo controls.
6. Encrypt uploads and processing artefacts. Store versioned identity references with access controls and explicit delete/revoke. Avoid indefinite retention of biometric data.
7. For scene creation, the UI presents **one main free-text scene prompt** and a small character selection. A backend adapter converts the identity package into provider-supported reference inputs and generation parameters, preserving seed and scene history when genuinely supported.
8. Test multi-shot face fidelity, expression integrity, lip-sync compatibility, body continuity, lighting variation, occlusion, photoreal vs animation transitions, and similarity under different camera angles. Never claim universal/perfect match.

## Model adapter contract (future)

An adapter must publish actual verified versioned capabilities, not demo profiles:

- `model_id`, `provider`, `version`, `formats_by_seconds`, `supported_reference_types`
- `identity_modes`: text-guidance, still-reference, multi-image, clip-reference, explicit-character-ID, or none
- `max_assets`, `upload_size_limit`, region, content policy, and identity-consent requirements
- `generation_cost_credits` for a specific supported output; missing price means **unavailable**
- Validated request -> reservation/quote -> asynchronous render job -> output quality report
- No API key, payment secret or privileged identity assets in Flutter source
- Each adapter independently validates output duration/aspect and uploaded references server-side

## UX and privacy acceptance gates

- A novice can explore HOTICE without providing a real password.
- A character can be created, edited, reused in multiple demo models, and deleted from the local library.
- Renaming characters must not accidentally overwrite other characters. Existing saved draft snapshots remain intelligible.
- Screens disclose whether something is a demo, real device function, or a paid/provider-dependent function.
- No dummy progress bars that suggest camera scans/AI jobs are running.
- Denied camera permission and unsupported depth sensors must have accessible manual fallback paths.
- Children, other people's likenesses, consent withdrawal, and sensitive biometric handling need specific production safety design and legal review before implementation.
- Portrait widths, large text settings, keyboard navigation, screen readers and low-motion preferences must be assessed on real devices.
- Real character fidelity is not accepted until visually compared across representative scenes and supported providers with permission from the subject.

## Current code pointers

- `lib/src/avatar_studio.dart` — guided capture **preview**, character editor/library
- `lib/src/avatar_identity.dart` — local reusable identity card / scene prompt builder
- `lib/src/state.dart` — account-scoped demo avatar records
- `lib/src/projects_generation.dart` — appends identity guidance when saving Normal Video drafts
- `lib/src/music_studio.dart` — selectable story character for local storyboard drafts

## Phase gates

**Phase A (this branch):** UI prototype, tests, Android debug APK.

**Phase B:** camera permission and real image capture with informed consent, quality gates, encrypted storage, reproducible deletion.

**Phase C:** reconstruct/select identity references, run real validation against individual provider APIs, measure face similarity.

**Phase D:** synchronized songs, word-level transcription, continuity-aware multi-shot pipeline, user-controlled final exports.

Do not enable Phase B–D toggles until their corresponding integrations, safety gates and device tests exist.
