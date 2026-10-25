# HOTICE Inspiration Library — source, rights and release specification

Updated 26 October 2026. This is a staged feature plan, not a claim of connected vendor models or launched scraping.

## Product experience

**Public name:** Inspiration Library. Website showcase heading: **What's Possible with HOTICE**.

* Browse categories (cinematic, music, fantasy, camera motion, actors, advertising, social) and search original/permission-cleared prompt templates.
* Each template holds title, prompt text, model hint, tags, optional preview with correct rights, reference-asset requirements, up to N actor-role placeholders, suggested camera/mood metadata and compatibility profile version.
* **Use this prompt:** copy the editable prompt and compatible **demo** model into Normal Video composer. User chooses their own named Actors and locally-selected reference assets where model allows them, adjusts Advanced settings, then saves a draft. It **does not** start paid rendering.
* If a prompt was not published with a clip, never label a reconstructed prompt as the “original.” An editorial adaptation must be marked “HOTICE-written adaptation” in rights metadata.
* On public showcases, emphasize HOTICE rather than linking people away. Do **not** say third-party videos were made by HOTICE. Respect attribution and embedded-player branding restrictions; do not remove watermarks/source links embedded by providers. Use self-hosted, permission-cleared video where allowed.

## Research sources to monitor for candidate discovery (not automatic content rights)

1. Google Flow TV — `https://labs.google/flow/tv/faq` and `https://support.google.com/flow/answer/16353333`: curated clips with some publicly viewable prompts.
2. Runway Gen-4 video guide — `https://help.runwayml.com/hc/en-us/articles/39789879462419-Gen-4-Video-Prompting-Guide`, and Gen-4.5 examples `https://help.runwayml.com/hc/en-us/articles/47313504791059-Camera-Terms-Prompts-Examples`.
3. Google DeepMind Veo prompt guide — `https://deepmind.google/models/veo/prompt-guide/`; verify model-specific modes through official API documentation, not marketing pages.
4. User-submitted content with explicit non-exclusive reuse and edit license, plus an accessible withdrawal pathway.
5. Third-party official feeds or partner APIs **only when their ToS grant automation and republication rights**.

**Do not deploy** blind scraping/circumvention, extract videos by bypassing website controls, crop out watermarks, or clone complete public prompt collections. External search discovery and importing approved material are separate steps.

## Admin-only ingestion pipeline (future PHP/MySQL backend)

`source_registry` (source ID, API/feed URL, allowed hosts, terms URL, polling limit, content scope, last checked, status); `ingest_candidate` (source URL, source content hash, claim of authorship, published at, discovery timestamp, media URL, exact prompt? boolean, proposed model, moderation state); `rights_clearance` (asset/prompt license IDs, permission evidence, effective dates, attribution required, revocation status); `templates` (owner, prompt provenance, model profile revision, publish status, tags, actor placeholder definitions, audience scope, immutable version, approved by); `media_assets` (storage key, sha256, MIME, file size, virus scan, license, approved delivery URL); `audit_log` (actor, action, old/new hash, IP redaction, timestamp).

Cron job schedule for shared hosting: every 30–60 minutes **only for allowlisted sources**; respect rate limits and 429/Retry-After; acquire a MySQL lease to avoid duplicate concurrent polls, use cursor/high-water mark and exponential backoff. Normalize records; hash deduplicate by original URL + media hash + normalized prompt hash; reject absent rights; queue for human review; publish only after approval. Disable/revoke immediately on rights withdrawal. Never treat AI-generated prompt guesses as original captions.

Security: server-side secrets encrypted at rest, admin auth + TOTP/WebAuthn/passkeys where supported, recovery codes, secure HttpOnly SameSite cookies, CSRF protections, RBAC, scoped expiring tokens, rate limits, hardened uploads, URL-fetch SSRF allowlist with DNS/IP validation on each redirect, prepared queries, output escaping, CSP and audit trails. Shared Namecheap hosting should serve only static frontend and supported PHP/MySQL services; intensive media render, queues and AI proxy require separate suitable compute as scale grows.

## Model truth / affordability

The live model catalog must come from server-approved provider adapters and versioned metadata. Demo model labels are *illustrative*, not actual costs. Real duration, output formats, reference limits, cost, commercial permissions and face-continuity controls can differ per model and over time. Never claim universal support or “best price” without comparable verified quotes.

## Delivery gates

- Phase 1: locally authored seed templates, gallery search/filter, **Use this prompt** to scene draft with model hint and Actors.
- Phase 2: responsive browser gallery and local video editor; usable Namecheap static files; admin security specification.
- Phase 3: server-admin installer, authenticated model catalog, moderated uploads and manual publish/unpublish, user accounts/2FA.
- Phase 4: permissioned source connectors, scheduled ingestion and moderation notifications.
- Phase 5: paid model adapters, secure AI gateway, reliable generation billing, actor reference controls and editing integration.

Every phase requires test results, security review, and a release note. Never merge incomplete API credentials into Git.
