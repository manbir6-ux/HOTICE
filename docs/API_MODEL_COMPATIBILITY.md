# HOTICE — AI Provider Compatibility Contract
**Research checked:** 2026-10-29, Australia/Sydney  
**Implementation branch:** feat/smart-avatar-reference-engine  
**Current product:** Flutter offline demo + source-backed model research catalog. No production API keys/authentication/rendering/billing.

## Why this exists
Providers do NOT share a standard schema. The term "4 image references" may mean four separate references, first/last keyframes, one starting image, or an invalid request depending on the provider. A native GLB file is NOT automatically supported by a video model merely because HOTICE can build a 3D avatar. Google Gemini API and a third-party gateway hosting a Google model are independent integrations with distinct headers, quotas and availability.

**Fail-closed:** unknown, retired, unverified, or unsupported combinations must be rejected before any billable API call. Pricing is never zero by default.

## Official sources and status (refreshed 29 Oct 2026)

| Provider route / family | Workload | API & critical constraints | HOTICE status |
|---|---|---|---|
| Google Gemini API Omni Flash 1.1 (`gemini-omni-1.1-flash`) | Video | Interactions API, 3–10s, 16:9 or 9:16, 360p/720p/1080p/4K; text, image, and video inputs have task-specific shapes | Research profiles built; multi-reference joint limit unverified; no live adapter |
| Runway Gen-4.5 T2V | Video | Async `POST /v1/text_to_video`, `GET /v1/tasks/{id}`; 2–10s, 1280:720 or 720:1280; 12 provider credits/sec | Research profile built; cost is $0.12/sec before tax at $0.01/provider credit; no live adapter |
| Runway Gen-4.5 I2V | Video | Async `POST /v1/image_to_video`, `GET /v1/tasks/{id}`; 2–10s, first-frame image input, exact ratio follows documented dimensions; X-Runway-Version: 2024-11-06; 12 provider credits/sec | Research profile built; cost is $0.12/sec before tax at $0.01/provider credit; no live adapter |
| Kling 4 hosted via Runway (`kling_4`) | Video | Distinct Runway Dev route; 720p/1080p, 3–30s, text/frames/image/video references and source-video editing; conditional input and cost rules | Research only, disabled until exact input semantics and account access are verified |
| Gemini Omni Flash 1.1 hosted via Runway (`gemini_omni_flash_1.1`) | Video | Distinct Runway Dev gateway route; 360p/720p/1080p/4K with reference-image and source-video surcharges | Research only; do not reuse Google Gemini API payloads, credentials, rates, or entitlement checks |
| Luma Ray 2 | Video | Dream Machine /generations/video, model ray-2, generation status/webhooks, keyframes and options | Research only, disabled until duration/resolution combinations verified |
| Google Nano Banana 2 (gemini-3.1-flash-image) | Image | generateContent; image creation/editing, 0.5K/1K/2K/4K; media role limits vary | Research profile, no live adapter |
| OpenAI GPT-6.1 Sol | Script | Responses API, text/image understanding; not a video renderer | Research profile, no live adapter |
| Anthropic Claude Sonnet 5 | Script | Messages API, provider model entitlement/version must be checked | Research only |
| ElevenLabs eleven_multilingual_v2 | Speech | /v1/text-to-speech/{voice_id}, separate voice/model discovery, output format & voice controls | Research profile, no live adapter |
| OpenAI GPT Transcribe | Transcription | /v1/audio/transcriptions, max 25 MB file, original-language text; do not assume diarization/word-level alignment | Research profile, no live adapter |
| Google Gemini 3.5 Transcribe | Transcription | Interactions API; file up to 1h, only up to 30m with word timestamps or diarization; custom vocabulary incompatible with word timing/diarization | Research profile, no live adapter |
| OpenAI GPT-4o Transcribe Diarize | Transcription | Deprecated, scheduled shutdown 26 Feb 2027 | Research only; avoid new integration |
| Replicate | Aggregator | Versioned model schema per model/version; do not invent common image/video settings | Future schema adapter; no arbitrary model automatically eligible |
| OpenAI Sora 2 Videos API | Video | Deprecated/shut down **24 Sep 2026** | **RETIRED — block** |
| Google Gemini Veo 3.1 Preview endpoints | Video | Shut down **22 Oct 2026** in Gemini API (enterprise or third-party hosted variants are separate) | **RETIRED — block** |

Primary official documentation:
- https://ai.google.dev/gemini-api/docs/omni
- https://ai.google.dev/gemini-api/docs/video
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image
- https://docs.dev.runwayml.com/api/
- https://docs.dev.runwayml.com/guides/using-the-api/
- https://docs.dev.runwayml.com/guides/models/
- https://docs.dev.runwayml.com/guides/pricing/
- https://docs.dev.runwayml.com/assets/outputs/
- https://docs.dev.runwayml.com/assets/inputs/
- https://docs.lumalabs.ai/reference/creategeneration
- https://developers.openai.com/api/docs/models
- https://developers.openai.com/api/docs/deprecations
- https://docs.anthropic.com/en/docs/about-claude/model-deprecations
- https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- https://replicate.com/docs/topics/models/versions
- https://developers.openai.com/api/docs/guides/speech-to-text
- https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe

This list represents known candidate model families, NOT all existing AI models, all account-specific entitlements or an assurance of availability after credentials are provided.

## Runway Gen-4.5 price and task lifecycle (checked 29 October 2026)

Runway's published Gen-4.5 rate is 12 Runway provider credits per generated second; its pricing guide values a provider credit at US$0.01. That makes a 5-second task US$0.60 and a 10-second task US$1.20 in provider cost before tax. This is **supplier cost**, not a HOTICE customer price, and must be rechecked before quotes or model activation.

Gen-4.5 text-to-video and image-to-video are asynchronous tasks. Runway requires API version header `2024-11-06`; task state is retrieved at `GET /v1/tasks/{id}`, and docs recommend polling no more frequently than every five seconds. Successful task output URLs expire after access (typically 24–48 hours); HOTICE must securely retrieve the result into private storage and must not expose the vendor URL directly. Do not enable this profile until a durable worker, idempotent cost reservation, secure output storage, account/region entitlement checks, and staging evidence exist.

## Current Omni and Kling routes (checked 29 October 2026)

The native Google Gemini API and Runway Dev are separate billing and integration routes even when they expose the same underlying model family. Never share API payload builders, provider credentials, entitlement status, cost tables, or provider operation IDs across those routes.

- **Google Gemini API Omni Flash 1.1** uses `gemini-omni-1.1-flash` through the Interactions API. Google's paid Standard table lists input at US$1.50 per million tokens and video output at US$17.50 per million tokens. Google estimates 5,792 output tokens per second for 720p, or about US$0.10 per second at that resolution. This is supplier cost only; pricing for other resolutions and any account-specific terms must be verified before quoting.
- **Runway Dev Gemini Omni Flash 1.1** uses the gateway model code `gemini_omni_flash_1.1`, not Google's model code. The current Runway table lists 3.4, 10, 15, and 30 Runway credits per output second for 360p, 720p, 1080p, and 4K; it additionally charges one credit per reference image and one credit per second of source video. Runway values a credit at US$0.01. Recheck the rate and exact task input limits before any quote.
- **Runway Dev Kling 4.0** uses `kling_4` and is separate from any native Kling provider API. Its model guide describes 720p or 1080p generation, 3–30 seconds, and text, frames, image/video references, or source-video editing. The pricing guide currently shows a time-limited 20% discount through 30 November 2026 UTC. 720p is 12.56 credits/second without input video, or 7.52 credits/second of output plus 7.52 credits/second for the greater of source-video duration or output duration; list rates are 15.7 and 9.4. At 1080p the discounted rates are 18.8 and 11.28, with list rates 23.5 and 14.1. The guide says charges round up to a whole credit and list rates apply from 1 December 2026 UTC. This expiry makes the discounted price unsuitable as a persisted long-term catalog rate.

All figures above were observed in public official documentation; they do not prove HOTICE account entitlement, regional access, commercial suitability, negotiated price, request correctness, successful renders, or invoice reconciliation. Keep the models disabled until those facts are tested on the exact account, route and region. Refresh price evidence immediately before launch and after scheduled pricing changes.

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
- lib/src/api_model_preview_panel.dart: separate non-billable Normal Video panel that reacts to selected provider profile, adapting aspect/resolution/duration UI without modifying the user's one main prompt. A model without a documented exact duration field displays automatic duration rather than pretending that the API accepts seconds.
- test/api_model_preview_test.dart: widget-level model switching and dynamic settings checks.
- lib/src/server_model_manifest.dart: strict versioned expiring trusted-server JSON catalog parser with exact duration/aspect/resolution tuple validation and reference count gates.
- backend/php/ProviderEnvelope.php: server-only, text-only Google Omni/Runway envelope builders; secret headers from env and fixed allowlisted hosts; **not an HTTP worker** and never runs without trusted server approval gates.
- backend/tests/provider_envelope_test.php: mandatory quote/auth/entitlement gates, payload schemas, secret isolation, rejection cases.
- integration_test/android_smoke_test.dart: real Android emulator navigation check to the model browser.
- test/model_registry_test.dart: documented exclusions, retirement, input roles, duration/ratio and server gates.
- The currently saved Normal Video scene drafts still use **demo model profiles**. Do not advertise a live model selector or submit feature as connected.
- Backend credentials, live catalog endpoint, actual HTTP dispatch, signed billing quotes, image/video provider adapters, persisted jobs and paid E2E integration tests are **NOT implemented**. Server-manifest parser and dry-run request envelopes are in source only. Credentials alone do not solve entitlements, licensing or provider changes.

## Rollout gates
Phase A: read-only in-app catalog, source-backed typed validation, CI (current implementation).
Phase B: cPanel PHP backend secret store, owner setup and dynamic catalog endpoint, authentication, SQL job queue, encrypted asset storage, signed quote/credit reservation and audit logs.
Phase C: native provider adapters and low-cost sandbox probes with specific API keys; activate **one model+task** only after successful preview and golden render.
Phase D: full multi-reference, 3D where supported, audio/transcription, music video shot pipeline, fallbacks, observability and per-model reliability/cost dashboards.

**No honest implementation can promise 100% permanent compatibility with third-party models**. Stable behavior comes from live capability discovery, tested adapters, strict fail-closed validation and automated change detection.
