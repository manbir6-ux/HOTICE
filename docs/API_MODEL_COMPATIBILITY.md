# HOTICE — AI Provider Compatibility Contract
**Research checked:** 2026-10-28, Australia/Sydney  
**Implementation branch:** feat/smart-avatar-reference-engine  
**Current product:** Flutter offline demo + source-backed model research catalog. No production API keys/authentication/rendering/billing.

## Why this exists
Providers do NOT share a standard schema. The term "4 image references" may mean four separate references, first/last keyframes, one starting image, or an invalid request depending on the provider. A native GLB file is NOT automatically supported by a video model merely because HOTICE can build a 3D avatar. Google Gemini API and a third-party gateway hosting a Google model are independent integrations with distinct headers, quotas and availability.

**Fail-closed:** unknown, retired, unverified, or unsupported combinations must be rejected before any billable API call. Pricing is never zero by default.

## Official sources and status (checked 28 Oct 2026)

| Provider route / family | Workload | API & critical constraints | HOTICE status |
|---|---|---|---|
| Google Gemini API Omni Flash 1.1 | Video | Interactions API, 3–10s, 16:9 or 9:16, 360p/720p/1080p/4K (higher resolutions upscaled); text, first/last frames, and advanced references are distinct tasks | Research profiles built; multi-reference joint limit unverified; no live adapter |
| Runway Gen-4.5 T2V | Video | /v1/text_to_video; 2–10s, 1280:720 or 720:1280 | Research profile built, no live adapter |
| Runway Gen-4.5 I2V | Video | /v1/image_to_video; 2–10s, a single prompt image, model-specific exact pixel ratios; X-Runway-Version: 2024-11-06 | Research profile built, no live adapter |
| Kling 4 hosted via Runway | Video | Distinct Runway gateway model; 3–30s, complex resolution/ratio pairs; image/video references have conditional limits | Research only, disabled until detailed pair constraints and provider access verified |
| Luma Ray 2 | Video | Dream Machine /generations/video, model ray-2, generation status/webhooks, keyframes and options | Research only, disabled until duration/resolution combinations verified |
| Google Nano Banana 2 (gemini-3.1-flash-image) | Image | generateContent; image creation/editing, 0.5K/1K/2K/4K; media role limits vary | Research profile, no live adapter |
| OpenAI GPT-6.1 Sol | Script | Responses API, text/image understanding; not a video renderer | Research profile, no live adapter |
| Anthropic Claude Sonnet 5 | Script | Messages API, provider model entitlement/version must be checked | Research only |
| ElevenLabs eleven_multilingual_v2 | Speech | /v1/text-to-speech/{voice_id}, separate voice/model discovery, output format & voice controls | Research profile, no live adapter |
| Replicate | Aggregator | Versioned model schema per model/version; do not invent common image/video settings | Future schema adapter; no arbitrary model automatically eligible |
| OpenAI Sora 2 Videos API | Video | Deprecated/shut down **24 Sep 2026** | **RETIRED — block** |
| Google Gemini Veo 3.1 Preview endpoints | Video | Shut down **22 Oct 2026** in Gemini API (enterprise or third-party hosted variants are separate) | **RETIRED — block** |

Primary official documentation:
- https://ai.google.dev/gemini-api/docs/omni
- https://ai.google.dev/gemini-api/docs/video
- https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image
- https://docs.dev.runwayml.com/api/
- https://docs.dev.runwayml.com/assets/inputs/
- https://docs.lumalabs.ai/reference/creategeneration
- https://developers.openai.com/api/docs/models
- https://developers.openai.com/api/docs/deprecations
- https://docs.anthropic.com/en/docs/about-claude/model-deprecations
- https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- https://replicate.com/docs/topics/models/versions

This list represents known candidate model families, NOT all existing AI models, all account-specific entitlements or an assurance of availability after credentials are provided.

## Versioned backend catalog (authoritative — NOT yet deployed)
A real server-delivered catalog record must include:
- Provider, gateway, exact model code/version, API surface and version header, docs URL, checked date, deprecation and region gates.
- Workload: script, image, video, transcription, speech; and separate source/target input modalities.
- Duration ranges / enumerations and **conditional** duration + aspect + resolution combinations.
- Image roles: first frame, last frame, identity/reference, object/location/style, and conditional combined counts. Include native GLB only on a provider actually accepting it.
- MIME allowlists confirmed by file signature, bytes, pixels, aspect crop, FPS, source video/audio duration, and file-URI expiry rules.
- Provider audio generation flags, text limits, voices/languages, transcription timestamps/speaker support.
- Endpoint type: synchronous vs async, task state/cancellation, polling and webhooks, output retention/expiry, retry categories, per-account concurrent/rate limits.
- Price source and currency, output quality cost, taxes and HOTICE credit rate; signature/expiry/idempotency of a quote.
- Tested status per provider+account+region+model+task (not just working API key).
- Actual detected supported features and last successful low-cost provider probe.

## Security/runtime requirements
1. Android/iOS NEVER stores a vendor API key, never calls a vendor directly. Owner adds keys only to backend configuration/secret store outside public_html. Do not echo/log keys.
2. Backend authenticates real user and owner/account permissions, verifies assets belong to that user and match current consent, malware scans/uploads and keeps encrypted media with signed expiry.
3. Backend owns authoritative catalog; signed/revisioned snapshots can be cached by app. Unknown model IDs or fields fail closed.
4. Backend probes model access without incurring unnecessary generation cost, distinguishes key-valid vs model-entitled vs rendering working.
5. No request goes out until real quoted credits, authenticated reservation, concurrency allowance, budget caps and idempotency key are persisted transactionally.
6. Provider request builder maps HOTICE normalized input roles to **that exact endpoint's** API schema. It never drops a manually locked reference. If over limits, ask for a new reference plan.
7. Save job record before dispatch; poll/webhook with signature verification; store upstream task ID. Retry only when provider confirms no duplicate job (or supports idempotency). Never retry 401/402/403/400/404/422 as if a transient failure.
8. On completion, securely fetch output before provider retention expiry and atomically settle ledger; record exact provider version, credits used and media provenance; release unused reservations on definite failures.
9. Monitor model changelogs/deprecations and periodically re-probe; disable retired versions without a mobile app update.
10. CI contract tests, sandbox accounts and paid low-cost golden renders are release gates. Rate-limit, webhook, concurrent requests, failed upload, expired URI, changed limits and revoked keys must be tested.

## Implementation in this branch
- lib/src/model_registry.dart: researched, provider-scoped model entries, task/role/duration/ratio/resolution checks, retired model guards, error categories and server-readiness gate contract.
- lib/src/model_compatibility_page.dart: searchable source-backed API model inspector accessible from HOTICE Settings / Normal Video.
- test/model_registry_test.dart: documented exclusions, retirement, input roles, duration/ratio and server gates.
- The currently saved Normal Video scene drafts still use **demo model profiles**. Do not advertise a live model selector or submit feature as connected.
- Backend/provider credentials, dynamic manifest, signed quotes, real HTTP adapters and paid E2E integration tests are **NOT implemented**. Credentials alone do not solve entitlements, licensing or provider changes.

## Rollout gates
Phase A: read-only in-app catalog, source-backed typed validation, CI (current implementation).
Phase B: cPanel PHP backend secret store, owner setup and dynamic catalog endpoint, authentication, SQL job queue, encrypted asset storage, signed quote/credit reservation and audit logs.
Phase C: native provider adapters and low-cost sandbox probes with specific API keys; activate **one model+task** only after successful preview and golden render.
Phase D: full multi-reference, 3D where supported, audio/transcription, music video shot pipeline, fallbacks, observability and per-model reliability/cost dashboards.

**No honest implementation can promise 100% permanent compatibility with third-party models**. Stable behavior comes from live capability discovery, tested adapters, strict fail-closed validation and automated change detection.
