# HOTICE Actor Identity Engine — technical design and implementation status

**Date:** 26 October 2026 · **Branch:** `feat/actor-identity-model-adapters-v1` · **PR:** https://github.com/parmtech/HOTICE/pull/17

## What Google Flow/Omni actually provides

Google Flow has reusable **Characters** (a named bundle of visual/voice references; create from 1–2 images) and a separate mobile-captured **personal Avatar** accessed with `@me`. Official help does not document a way for HOTICE to read, export, or clone the private Google Flow Avatar/Character record. A Flow Character is **not documented as a downloadable GLB/3D mesh**. Do **not** use unofficial scraping or claim Google Flow character interoperability.

- Google Flow character help: https://support.google.com/flow/answer/16935308
- Google Flow personal avatar: https://support.google.com/flow/answer/17102997
- Gemini Omni Flash developer model: https://ai.google.dev/gemini-api/docs/models/gemini-omni-flash
- Gemini Omni API / Interactions: https://ai.google.dev/gemini-api/docs/omni

**Gemini Omni Flash** offers an official `gemini-omni-1.1-flash` API supporting text + images/video/audio in model-specific workflows. HOTICE can prepare media references from its **own** Actor identities, then an authenticated HOTICE server can use the provider API once owner credentials, storage, billing permissions, uploaded media and privacy controls have been configured.

**Do not configure retired preview models** (`veo-3.1-*-preview` retired 22 October 2026) as production defaults; check provider API versioning live at launch: https://ai.google.dev/gemini-api/docs/video.

## What is actually implemented in this feature PR

1. `lib/src/actor_reference_adapter.dart`: deterministic, privacy-local **Actor Reference Planner**. Checks model image/video slot limits, the existing reference budget, named-Actor ownership and fair angle allocation. If 2+ Actors compete for just 1 remaining image slot, chooses an **actual single composite** instead of illegally sending multiple images.
2. `ActorContactSheet.compose`: creates a real JPEG canvas from source portraits (letterboxed, no stretching); `saveToTemporaryFile` writes a local temporary file. All images remain unuploaded on the phone.
3. `lib/src/projects_generation.dart`: displays plan notes and automatically prepares actor media when saving a demo scene draft. The draft records temporary local references along with existing attachments. **No paid AI request is sent**.
4. `lib/src/video_models.dart`: a Gemini Omni Flash **unconnected integration-preview** profile alongside illustrative demo models. Number of sample input slots and cast limits are **HOTICE conservative demo policies**, NOT official provider limits; no verified price exists.
5. `server/src/GeminiOmniPayload.php`: an offline, server-only **request-builder** for Google's documented Interactions API. Rejects invalid ratios/tasks/media/base64 and does not transmit data. It has **no HTTP endpoint**, API key, user auth, ledger or payment logic; don't expose it publicly until a hardened API gateway is implemented.
6. `workers/actor3d/reconstruct_3ddfa.py`: optional **real 3D face geometry** `.obj` reconstruction bridge to a separately installed, pinned, licence-audited 3DDFA_V2 Python engine. Requires explicit consent. Uses a private external worker, randomized staging input filename, fixed output location, no shell, execution timeout and cleanup. It does not install pretrained weights or itself infer geometry without the external engine.
7. `workers/actor3d/obj_to_glb.py`: a Blender 4+ conversion stage for an existing OBJ mesh to `.glb`. It must run in Blender on a trusted private worker; no Blender install is shipped.
8. `lib/src/actor_pose_gate.dart` and `lib/src/guided_actor_camera.dart`: mirrored-selfie yaw normalization and portrait preview crop without face-stretching (user-reported errors). These **still require verification on the actual phone**.
9. Tests: Flutter pose/montage/budget/consent tests; standard Python worker sandbox + consent checks (mock model); PHP input-policy checks; Android emulator smoke and APK compilation in GitHub Actions.

**IMPORTANT:** Python contract tests exercise a stub engine, **NOT actual 3DDFA inference**. Flutter image tests use generated colour sample images, not biometric images. A green test does not prove face likeness, mobile rotation correctness, input licences, or full production security.

## Why 3D head models are not universal video inputs

- 3D mesh `.obj`, `.glb`, `.fbx` files are primarily suitable for 3D editing, rendering and animation software. Gemini Omni Flash's published media interface documents text/image/video/audio, **not direct GLB upload as a video reference**.
- Maintain an optional **3D master asset**, but publish **model-specific derivations**: a single clean portrait/contact sheet for one-image models; multiple head views for multi-image models; a short turntable/pose clip for video-reference models once an actual video renderer is integrated; text identity notes for text-only models.
- Real results depend on model/provider identity support and reference quality. A contact sheet may decrease detail when faces become small; show this trade-off rather than promise guaranteed face consistency.
- **A 3DDFA OBJ is approximate head geometry, not automatically a photorealistic full-body rig or identity-verified scan.** Textures, hair/beard geometry, material, pose rigging and usable GLB still need processing and human QA.

## Open-source due diligence / licensing

- 3DDFA_V2 https://github.com/cleardusk/3DDFA_V2 : MIT repository, includes documented `python demo.py -f <image> -o obj --onnx` and output `examples/results/<basename>_obj.obj`. **Independently audit all dependent pretrained weights, face detectors and texture components** before commercial deployment.
- Google GNM Head https://github.com/google/GNM : Apache-2.0 parametric head geometry released 2026, promising alternative for commercially licensed head models; a working personalized inverse-fit pipeline has NOT been integrated.
- DECA https://github.com/yfeng95/DECA : the published code/model is **non-commercial research only**; DO NOT copy or ship it commercially without a different licence.
- Do not assume an open-source code license covers every model weight or underlying face dataset.
- The worker is intentionally **not** installed/deployed on Namecheap shared hosting. Configure isolated external CPU/GPU workers with image consent, secrets, privacy policy and controlled resource quotas.

## Security and privacy launch blockers

- Present mobile multi-angle photos are temporary, **unencrypted**, local. Production must introduce an encrypted per-user Actor vault with retention/deletion, consent/revocation, media validation, secure export/import, access auditing and secure upload.
- The model-specific image contact sheet is **also temporary and sensitive**. Clear it on logout/delete/next startup and avoid backups until encryption policies exist.
- Protected API routes, signed uploads, admin MFA, authenticated queue/credit reservation and provider API keys **server-side only**. No secret in JavaScript/mobile apps/GitHub.
- Stop users from invoking costly generation without authorization, rate limits, confirmed server-side pricing and explicit user approval.
- Biometric photos and mesh-derived identities should not be used to imitate other persons without informed consent.

## Development phases remaining

1. Stabilize PR #17: all unit/widget tests, web/PHP/Python checks, Android emulator, APK, and physical-phone yaw/preview.
2. Integrate secure, persistent encrypted Actor profile storage; delete reference sheets/photos on request and guard import/export packages.
3. Deploy commercial-license-reviewed 3D reconstruction worker, install audited models, add face alignment, multi-view fusion, texture/material reconstruction and GLB validation. Verify output using *real consented captures*.
4. Implement Blender/3D turntable renderer, select references by verified per-model capability *from central admin*, assess face detail and reference compression quality.
5. Build secure Namecheap first-run installer + admin MFA, dedicated API gateway, upload sanitization, queued worker communication and provider webhooks.
6. Integrate official Gemini Omni Interactions API **only on the backend** after admin config. Confirm supported counts, codec requirements, current costs, quota and identity restrictions against production API.
7. Test identity consistency and video quality with consented actors across each actual video model; no guarantee of exact identity matching across generations.

## Done means

**Source implemented ≠ model installed ≠ cloud integrated ≠ commercial cleared ≠ user-device validated.** Never call a portrait sheet a real 3D head or claim a 3D face scan was generated unless the worker actually ran and the geometry was visually validated.
