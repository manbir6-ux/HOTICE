# HOTICE — UPDATES & DEVELOPMENT PROGRESS

**Last updated:** 26 October 2026 (Australia/Sydney)  
**Canonical repo:** https://github.com/parmtech/HOTICE  
**Purpose:** Durable, factual change log, latest tested build, outstanding product decisions, security requirements and handoff for the next development iteration. **Update this file after each meaningful implementation and CI verification.**

> **Do not confuse requirements, prototypes and production features.** "Implemented" means source code exists; "CI verified" means GitHub Actions passed for a specified commit; "production ready" additionally requires security, deployment and real-device tests. This document is not a claim that video AI, a real 3D face scanner, live payments or an administrator backend are active.

## 26 October 2026 — New Guided Actor Camera v1 (PR #16, draft)

- **Implementation branch:** `feat/real-guided-actor-camera-v1`, stacked on unmerged PR #11. [Review PR #16](https://github.com/parmtech/HOTICE/pull/16). **Not part of stable `main` yet.**
- **Code written:** real Android/iOS front-camera preview after explicit consent; throttled Google ML Kit on-device face detection; one-face/position/size/yaw/roll guidance; four stable green checks with system click/haptic signal; manual front-left-right 3-photo capture with still-image angle recheck; named Actor session profile and thumbnails; cancellation/deletion/next-launch temporary-file cleanup.
- **Platform setup:** idempotent camera permission / Android API 24 / iOS 15.5 script for generated Flutter scaffolds, and `path_provider` app-private temporary storage.
- **Tests:** added unit tests for face-count/framing/yaw safety rules and a widget test for camera consent. [Feature CI run 40260796253](https://github.com/parmtech/HOTICE/actions/runs/40260796253) passed Flutter analysis/widget tests and web validation as checked during development; Android emulator/build completion must be verified separately.
- **Documentation:** [Actor Guided Camera QA](https://github.com/parmtech/HOTICE/blob/feat/real-guided-actor-camera-v1/docs/ACTOR_GUIDED_CAMERA_V1.md). 
- **NOT COMPLETE:** real-device camera QA, mirrored left/right validation, 3D reconstruction/rig, focus/lighting/liveness quality, encrypted persistent Actor vault, provider identity adapters, cloud sync or secure backend. No phone camera hardware was operated in automated widget tests.
- **Privacy limitation:** photos are short-lived application-private **unencrypted temporary files**, and Actor records are session-only; next launch cleans abandoned files. This is not secure permanent biometric storage.
- **Tracking:** [Issue #13](https://github.com/parmtech/HOTICE/issues/13) remains open for real-device validation and production safeguards.

## 26 October 2026 — Actor Identity Engine + Gemini Omni integration foundation

- **New development branch:** `feat/actor-identity-model-adapters-v1`, [PR #17](https://github.com/parmtech/HOTICE/pull/17) (DRAFT, stacked on PR #16 → PR #11). **Not merged into main.**
- Verified from official Google docs: Google Flow's reusable named **Characters** are bundles of references and optional voice, not an externally documented downloadable GLB. Personal Flow Avatar `@me` is internal/private. Gemini **Omni Flash** provides the `gemini-omni-1.1-flash` Interactions developer API for text/image/video workflows; provider keys still must stay behind the future HOTICE backend.
- Implemented a model-aware local Actor reference adapter: chooses a fair number of front/side images depending on image limits and already-selected attachments; for multiple Actors and one remaining image slot, actually creates one on-device JPEG contact sheet. This does **not** guarantee each AI model will identify faces reliably.
- Connected reference planning to demo scene draft saving; added conservative **Gemini Omni Flash integration-preview** model (NO live API/verified cost), plus a validated PHP server-only request builder with no HTTP endpoint or keys.
- Added optional private 3D **OBJ** reconstruction worker wrapper for an independently installed, audited **3DDFA_V2** engine and a Blender OBJ → GLB converter. Neither 3DDFA models/weights nor Blender are installed or run by this branch. **No 3D head has actually been reconstructed/tested**; the optional worker uses a mocked engine in CI.
- Added Flutter actor-reference tests; Python worker consent/staging tests; PHP Omni payload tests. Fixed selfie-camera left/right yaw mapping and changed preview to portrait centre crop without stretching (phone retest needed). Added temporary reference-sheet cleanup.
- 3D licensing research: [3DDFA_V2](https://github.com/cleardusk/3DDFA_V2) code MIT (independently audit weights/dependencies), [Google GNM](https://github.com/google/GNM) Apache-2.0, **DECA noncommercial research only**. Do not ship restricted model weights without a suitable license.
- Exact latest CI results/artifact must be rechecked on [PR #17](https://github.com/parmtech/HOTICE/pull/17) before merging. All generated media stays in the app's **unencrypted temporary storage** until production encryption, consent/deletion and backend protections exist.
- Full plan and implementation map: [Actor Identity Engine](https://github.com/parmtech/HOTICE/blob/feat/actor-identity-model-adapters-v1/docs/ACTOR_IDENTITY_ENGINE.md). Open blockers: actual 3D inference and GLB quality, persistent secure Actor vault, officially verified model limits/prices, central admin/MFA/backend, media uploads and real paid video generation, physical-phone camera QA.

## 26 October 2026 — Guided-only Actor creation and seven-angle scan review

- **PR #17 source changes (NOT merged into `main`):** removed the Quick Actor / unsupervised `Save actor` creation route from Actors Studio. User now enters Actor name and optional notes **before** opening guided camera, and the keyboard is dismissed on navigation.
- **Scan extended:** front, left slight, right slight, left profile, right profile, chin up and chin down (**seven** real face photos). Preview/still validation uses consistent yaw/pitch gates, with on-screen red/green instructions and haptic/click readiness.
- **User review:** after seven captures, a thumbnail gallery offers **Retake** for each angle, followed by explicit `Save Actor with 7 views`. No Actor created automatically on the last shot; cancelled scans discard collected temporary photos. Model adapters now label seven angles correctly.
- **Tests:** added small-phone UI guard that creation is guided-only, plus seven-angle yaw/pitch boundary tests. The updated Flutter run 40281012796 passed **50/50** unit/widget tests (that revision); follow-up actor photo-quality regression added four tests and passed **54/54** in run 40281633718, static analysis exit-success and static web/PHP/Python checks; Android emulator/APK verification is separately pending at this snapshot.
- **Original camera screenshots:** earlier left/right guidance reversal and stretched preview were addressed in branch code, but the exact selfie-yaw sign and portrait crop **require retesting on the reported physical phone**. Changing head pitch/yaw thresholds is not proof they fit every device.
- **New local photo quality advisory:** `ActorPhotoQuality` calculates sampled luminance, contrast and edge detail (small on-device image) after each capture; review shows dark/overexposed/low-detail warnings for optional Retake, without editing the original. **Not** a calibrated blur/face-quality guarantee.
- **Still blocked:** optional beauty/touch-up, actor ZIP import/export, calibrated optical focus/lighting verification, encrypted persistent Actor identity vault, actual installed/licence-audited 3D reconstruction/GLB worker, provider API calls and secure Namecheap control-plane.
- **Tracking:** [PR #17](https://github.com/parmtech/HOTICE/pull/17) · [Camera QA plan](https://github.com/parmtech/HOTICE/blob/feat/actor-identity-model-adapters-v1/docs/ACTOR_GUIDED_CAMERA_V1.md) · [Issue #13](https://github.com/parmtech/HOTICE/issues/13).

## 26 October 2026 — Full code audit pass 2 (PR #19)

- **Code review branch:** `fix/full-code-audit-2026-10-26` and [PR #19](https://github.com/parmtech/HOTICE/pull/19) (DRAFT, stacked on PR #17 → #16 → #11; **NOT in main**).
- **HIGH fixed — project-scoped scene data:** switching projects previously preserved only the prompt, allowing an Actor cast, reference image names, negative prompts, seed, model and other advanced settings from another film to remain selected. The updated editor snapshots all project-specific state, and a new widget test checks isolation and restoration.
- **HIGH fixed — asynchronous scene saves:** duplicate save and navigation during Actor JPEG contact-sheet creation could mix editor state or leave temporary composite images. Added an immutable save snapshot, UI interaction lock, project check before writing, clean-up on aborted saves and user-friendly file failure handling.
- **MEDIUM fixed — browser editor:** changing clip order selected the wrong clip, and stale metadata listeners could affect later clip previews. Added a pure timeline operation with Node tests and cleans up failed metadata probes. Local editor remains a preview; export is intentionally disabled.
- **HIGH hardened — PHP input:** the Gemini Omni request builder previously accepted arbitrary base64 under a JPEG/PNG MIME claim; now checks actual bytes/MIME and image pixel/dimension limits, with negative tests. This remains an **offline builder, not a secured/active provider endpoint**.
- **HIGH hardened — optional 3D worker:** refuses symlinked and oversized mesh/sidecar outputs with worker regression tests. Actual 3D inference is not deployed; code/model-weight licensing, sandbox isolation, secure private storage and model quality still require independent validation.
- **CI improvement:** new per-PR concurrency policy cancels obsolete emulator/APK builds when rapid new commits arrive. An earlier main emulator run failed while downloading Android SDK ZIP; no indication it was an app runtime assertion.
- **Verified automation:** [run 40283778534](https://github.com/parmtech/HOTICE/actions/runs/40283778534) passed **55/55 Flutter tests**, Node web-editor regression, six static approved templates, six Python worker tests, and PHP media validation. Android emulator/APK were still in progress at the last verification; the final status of the latest audit commit must be checked separately. Analyzer still reports **41 nonfatal info/lint issues**.
- **Audit report:** [Full Code Audit Pass 2](https://github.com/parmtech/HOTICE/blob/fix/full-code-audit-2026-10-26/docs/CODE_AUDIT_FULL_PASS2_2026-10-26.md). **Production blockers remain:** server authentication/MFA/provider key vault, real model API, verified billing/capabilities, encrypted Actor vault, real-phone selfie face/pose QA, true installed 3D reconstruction and secure Actor import/export.

## 1. GitHub status verified today

| Track | Status | Evidence |
| --- | --- | --- |
| Stable `main` | Commit `fc2b7352c42b886b72e29c63c2827080ab9995f1` | [main](https://github.com/parmtech/HOTICE/tree/main); previous Flutter/Android code was validated before merge |
| Active feature work | `feat/actors-web-studio-v1` at `1c066024626f50a5012799fab17bb9b4115d91df` | [PR #11](https://github.com/parmtech/HOTICE/pull/11) — **OPEN, NOT MERGED** at this snapshot |
| Latest full feature CI | **PASS**: Flutter analysis + tests, static Namecheap web/catalog validation, Android emulator user-journey test, Android debug APK compilation | [Actions run 40246875147](https://github.com/parmtech/HOTICE/actions/runs/40246875147), tested at exact feature commit above |
| Debug APK | `HOTICE-Android-v0.2.0-run86`, artifact ID `12618734453`, uploaded and not expired at snapshot | Download ZIP under **Artifacts** of run 40246875147. GitHub retention is temporary. This is **not** a production-signed release. |
| Android crash | Source fix for first error `BoxConstraints(w=-50.0)` merged previously; CI regression + emulator passed. **Affected physical phone verification still outstanding** | [Issue #9](https://github.com/parmtech/HOTICE/issues/9) must remain open until device confirmation |
| Production backend | **NOT BUILT** | Installer, admin panel, MFA, provider key vault, real auth/API proxy and generation worker remain planned |

**Important:** PR #11's changes are not on `main` until merged. Refresh GitHub branch, open PRs and Actions before replacing this snapshot; later commits can change these facts.

## 2. Changes written and tested in the development branch

### Android / Flutter foundation
- Project workflow, Normal Video and Music Video Studio preview; offline prompt drafting and editable storyboard ideas.
- Local named Actor/character profiles and description reuse. The brand term in new UI is **Actors**, not **Avatars**.
- Multi-actor scene/cast data model and actor-role concept; model-specific illustrative limits for image/video/audio references and advanced capabilities.
- Scene drafts retained across tabs and separated by selected project (from previously merged work).
- Responsive fixes: first Flutter negative-width launch crash, narrow-width cards, small-screen Avatar library header overflow and dialog lifecycle regression tests.
- Real Android camera **is not yet a complete guided scanning feature**. A pose/framing quality-rule component exists in feature work; full live camera frames, reliable face tracking, liveness, capture review, consent, storage, deletion and reconstruction remain pending.
- Illustrative model profiles are **not** live model-provider contracts. Do not present budget/premium labels as verified current prices.

### HOTICE web and Inspiration Library prototype
- Namecheap/cPanel-compatible **static** HOTICE marketing and browser studio starting point, with responsive styling, creative concept gallery and browser-local editing/inspiration experience.
- Public gallery heading **“What's Possible with HOTICE”**; do not write “Made with HOTICE,” “Generated by HOTICE” or equivalent unverified claims about example videos.
- Searchable Inspiration/Prompt Library prototype in Flutter and web with a **“Use this prompt”** path into an editable scene, compatible demo-model preset and Actor role selection.
- Six HOTICE-written example prompts in a permission/provenance-aware catalog. No third-party video or prompt collection is republished in the verified preview.
- Public-facing showcase should emphasize HOTICE; no unnecessary outbound vendor/source buttons or provider logos. **Exception:** never strip attribution, publisher/player controls or source identification required by licensing or platform embedding terms. When that conflicts with minimal-brand presentation, use separately licensed/self-owned content or omit the media.
- Real server-side ingestion, remote admin, permission-reviewed video embeds, user project synchronization and production media exports are **not implemented**.

### Documentation already in the feature branch
- [HOTICE Inspire roadmap](https://github.com/parmtech/HOTICE/blob/feat/actors-web-studio-v1/docs/HOTICE_INSPIRE_ROADMAP.md).
- [Inspiration Library research and rights](https://github.com/parmtech/HOTICE/blob/feat/actors-web-studio-v1/docs/INSPIRATION_LIBRARY.md).
- [Development progress (feature branch)](https://github.com/parmtech/HOTICE/blob/feat/actors-web-studio-v1/docs/PROGRESS.md).
- [Source audit](CODE_AUDIT_2026-10-26.md).

## 3. User decisions / requirements — preserve these

### A. Actors and guided mobile capture
- Call reusable characters **Actors** throughout the product. A creator can use **multiple Actors in the same scene**, and assign each a unique **name/role specific to that scene**.
- Actor creation should be initiated on the **mobile app** using a genuinely guided camera: live face detection, centering/distance/lighting checks, prompts to turn front/left/right, red/green visual signals and beep/audio cues when pose/frame is acceptable.
- Prefer on-device processing, meaningful camera permissions and informed consent; reject multiple faces and poor-quality captures; include retry/review/deletion. RGB video/photo capture **cannot guarantee a perfect 3D scan, biometric liveness or cross-provider identity locking**.
- Stored identity media and derived biometric data require encrypted access, retention/deletion policies, explicit ownership/consent, and no insecure public URLs. Real cloud sync will require the central backend.

### B. Model-dependent generation and advanced settings
- Show only verified models/capabilities enabled in admin: valid duration + aspect-ratio combinations; allowable input counts/types (one image vs several images/videos/audio); actor/identity reference support; optional controls such as negative prompt, seed, motion/camera, output quality, audio and model version.
- Provide a clear **Advanced** section while retaining **one simple primary free-text prompt**. Model selector, compatible formats and extra options may be inside Advanced; avoid fragmenting prompting into multiple compulsory text boxes.
- Model catalog may span cheaper to premium offerings, but **price claims, model access and “best output” claims must come from verified current provider APIs and audited server-side markup/cost rules**. No fabricated universal ranking or model specs.
- UI may prepare a compatible request locally; actual generation and file uploads must go through an authenticated, rate-limited HOTICE backend. Never embed provider API secrets in apps, website JavaScript or a public config file.

### C. Community / Inspiration Library — automated where authorized
- Searchable licensed examples, published public prompts, editable HOTICE-authored alternatives, model/genre/style filters, rights-aware media previews and optional personal collections.
- **“Use This Prompt”** should populate draft prompt and verified compatible model (or ask permission for a substitute), then allow the creator to replace/add their own named Actors, adjust attachments and open Advanced settings.
- Never assert an unpublished prompt is the original prompt behind a video. Mark authored approximations and adaptations clearly in provenance records.
- Planned controlled ingestion: approved provider feeds/APIs, creator opt-in submissions, rights/terms check, de-duplication, manual moderation where unclear, source verification dates, takedown/unpublish queue, scheduled refresh and audit log. **Do not scrape prohibited websites or copy unlicensed media**. The public page can be HOTICE-focused while keeping legally necessary attribution.
- Do not auto-publish all public examples just because they are accessible online.

### D. Web app, 3D-style landing, browser video editing
- HOTICE website should be premium, immersive, interactive, animated and responsive, with realistic feature descriptions and FAQ. Public heading: **What's Possible with HOTICE**.
- Unified website/app workflows: select Actors, choose model, build scene, use templates, import scenes into a simple browser editor/timeline, preview and eventually export.
- Research browser-native editor libraries and their licenses before integrating. Short local clips can be edited on-device in a preview; heavier exports, transitions and media processing might require an external worker/CDN and are not inherently supported by cheap shared hosting.
- Model demo media can be shown only when rights and embed conditions permit. No false representation that third-party footage was produced on HOTICE.

### E. Central admin, installation, security and app coordination
- **Web backend is the single trusted control plane** for Android, iOS, desktop and web app clients: provider configurations, keys, enabled models and limits, price catalog, API routing, quotas, credits, users, roles, media settings, gallery approval and audit events.
- First-run **installer** should initialize deployment, database and first administrator account securely; installation closes after success. Avoid publicly reusable bootstrap passwords. Sensitive configuration outside public webroot.
- Support strong MFA enrollment for both admin and user; require admin MFA for production privileged actions. Prefer TOTP with recovery codes and/or passkeys as provider/library support is validated. Recovery codes are one-time, hashed and shown only at enrollment.
- No provider API key in APK/desktop binaries/JavaScript. User devices **can still call public HOTICE endpoints**, but the backend must enforce auth, session scope, authorization, model-allowlist, validation, quotas, abuse prevention and replay/idempotency protection.
- Encrypt provider keys at rest using environment-managed secrets; separate admin and user roles, password hashing, CSRF/session hardening, strict CORS, HTTPS, secure headers, audit logs, upload scanning, signed access, webhook verification, rate limits, backup/restore testing and monitoring.
- Namecheap shared hosting can serve a carefully constrained PHP/MySQL control-plane and static frontend, but unlimited worker processes, large media transcoding and frequent scraping are **not guaranteed or suitable** there. Put CPU-intensive jobs in separate approved processing workers/services when required.

## 4. Bug and risk log

| Area | Finding / risk | Current state |
| --- | --- | --- |
| Android startup | `BoxConstraints(w=-50)` followed by `_dependents.isEmpty` | Source fix + automated regression verified; real affected-device confirmation outstanding ([#9](https://github.com/parmtech/HOTICE/issues/9)) |
| Narrow layouts | Avatar header and project card/dialog overflows | Regression tests passed in earlier CI; continue device matrix QA |
| Flutter file picker | Platform/package incompatibility occurred during development | Resolved for branch at CI run 40246875147; monitor plugin upgrades |
| Sensitive credentials | No production server key vault/auth exists | **Blocking** before connecting any paid generation |
| Face capture | Quality rules alone are not live camera capture | Guided camera and secure media handling not completed |
| Web editor | Browser functionality and codec/export portability vary | Test Chrome/Edge/Safari, permissions, memory, long clips and resource cleanup |
| Templates/media | Public availability does not grant prompt/video reuse rights | Review and record per-item rights before publication |
| Persistence | User workspaces currently demo/session-level, not cloud backed up | High-priority milestone |
| Provider pricing | Illustrative model profiles are not current vendor price quotes | Do not charge or promise verified savings until backend model/cost registry exists |

## 5. Ordered next development steps

1. **Keep current branch truthful and green.** Re-fetch PR #11 HEAD, run Flutter analyze/tests, static web checks, Android emulator and APK artifact. Don't merge broken or untested changes.
2. **Actors v1.** Validate scene role uniqueness, multiple actor selection, supported reference counts and a single prompt + Advanced UI. Test invalid models, missing Actor profiles, input limits, project and account isolation.
3. **Guided camera v1 (Android first).** Confirm ML/camera package compatibility; implement consent, real preview/detection, framing and pose checks, color/sound feedback, sample capture, review/retry and deletion. Do not claim 3D biometric accuracy.
4. **Web UX/editor v1.** Complete static Namecheap site asset integrity, browser clip import/playback/trim/reorder with resource cleanup, and honest export capability gating. Add accessibility/performance/small-screen checks.
5. **Inspiration Library v1.** Improve search, filtering, Use This Prompt, Actor mapping and rights-aware review workflow using HOTICE-authored or licensed samples only.
6. **Secure backend foundation.** Build Namecheap-compatible server installer, admin auth/MFA, permissions, encrypted server-side key vault, user sessions, server-only model catalog and API proxy. Security review *before* accepting real credentials.
7. **Automated permitted ingestion.** Implement approved-source registry, authorization/rate checks, dedupe, provenance, moderation and takedowns with legally defensible publishing.
8. **Provider integrations, paid credits and production launch.** Confirm current APIs/capabilities/pricing, worker scaling and webhooks; add end-to-end media/privacy/security/device testing. Keep user-facing features disabled until proven functional.

## 6. Change-control routine (every future update)

- Record date/time, branch, commit SHA, PR/issue URL and changes. Use **implemented**, **verified**, **planned** and **blocked** explicitly.
- Reference the **exact latest** Actions run; don't describe pending builds as successful.
- When a CI job fails, record the exact test/log error and remediation, then rerun.
- Track copyright/rights approval independently from technical embed capability.
- Save progress to `docs/UPDATES.md`; keep `docs/PROGRESS.md`, `docs/CONTINUE_HERE.md` and relevant PR/Issues aligned after each milestone.
- Never expose secrets, user data, biometric files or tokens in GitHub commits, workflow logs, PR discussions or this document.

---

### 26 October 2026 — Update saved
- Confirmed stable `main` commit `fc2b7352` and active unmerged PR #11 head `1c066024`.
- Independently verified all four CI jobs successful on [run 40246875147](https://github.com/parmtech/HOTICE/actions/runs/40246875147), including artifact `HOTICE-Android-v0.2.0-run86`.
- Consolidated all recent user requirements (Actors, advanced models/attachments, guided mobile camera, premium Namecheap web studio, central admin with MFA/API proxy, rights-aware “What's Possible with HOTICE” gallery and automated Inspiration Library).
- Recorded pending security, integration, production and manual Android-device QA honestly.
