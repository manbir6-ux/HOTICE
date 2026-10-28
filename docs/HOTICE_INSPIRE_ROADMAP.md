# HOTICE Inspire — research and implementation plan
Status: proposed, not yet connected to external providers. Date: 2026-10-26.

## Product flow
Discover -> Preview -> Use This Prompt -> select compatible model -> assign named saved Actors -> adapt reference inputs -> edit -> request generation via authenticated HOTICE backend -> add completed scene to timeline.

## Sources and provenance
Create an admin-managed ingestion registry for official model galleries, provider documentation, opt-in creator submissions, and licensed partner collections. For every item store original URL, provider, creator, media license, embedding permission, attribution obligations, prompt source, prompt publication rights, prompt completeness, model/version, date last verified, and removal request status. Never claim to know an unpublished prompt or scrape login-gated/private material. Do not hide mandatory attribution, circumvent player controls, or republish videos without rights.

## Suggested starting research targets
Runway showcases and Gen-4 prompting guides; Google DeepMind Veo/Flow examples and prompting documentation; Kling official inspiration and model docs; Luma Dream Machine showcases; Pika examples; Adobe Firefly inspiration and public galleries. Verify each provider's current APIs, embed terms, and commercial reuse permissions before enabling an integration.

## Templates
Fields: id, title, category, description, source metadata (admin-only where allowed), licensed preview media, original prompt if publicly shared with reuse rights, otherwise clearly marked HOTICE-authored inspired prompt, negative prompt, duration, aspect ratio, provider model ID/version, typed attachment limits, cast slots, camera/style tags, moderation status, publish state, last verified timestamp. Never conflate original prompts with reconstructed prompts.

## Use This Prompt
1. Open a draft, preserving previous unsaved work and offering undo.
2. Populate prompt and exact model only if the provider capability registry confirms it is available.
3. When unavailable, ask user to accept an alternative and show changed inputs, price and limitations.
4. Offer actor-role mapping using the user's own named Actor profiles. A multi-actor template may need multiple compatible references. Validate file types/counts and rights before upload.
5. Show estimated credits only from server-side verified pricing; require explicit confirmation for paid generation.
6. Send an authenticated generation request to HOTICE backend; never expose provider keys to browser or apps.
7. After completion, offer Add to Timeline. Demo mode only simulates steps and must be labeled.

## Automation pipeline
Scheduled ingestion -> legal/permission check -> dedupe via canonical URL and media fingerprint -> source metadata + prompt extraction when authorized -> quality/moderation checks -> human approval for uncertain rights -> publish -> periodically revalidate licenses, prices, model support and source availability -> takedown workflow. Respect robots.txt, rate limits and provider terms. No blind public scraping or auto-publishing unlicensed media.

## UI
Search; filters by genre, model, price band, reference type, aspect ratio, duration, actors; Save, Remix, Use This Prompt; Recently Added; My Collections. Marketing heading: "What's Possible with HOTICE". Do not label third-party media as created with HOTICE. Public attribution is displayed whenever legally required; otherwise internal provenance remains accessible to admins. The gallery must not suggest actual AI rendering is enabled in the current demo.

## Security
Central installer-created admin; optional user MFA and mandatory admin MFA before enabling production integrations; server-side key vault (never in webroot or mobile apps), role-based access, rate limits, CSRF protection, audit trails, per-user quotas, encrypted credentials, media scanning, signed uploads, and webhook signature verification. Namecheap shared hosting can serve PHP/MySQL and static UI; heavy rendering and frequent background ingestion need external workers or scheduled jobs. Verify real host capabilities.

## Milestones and tests
M1 schema + licensed manually curated sample templates, no external media copying.
M2 app/web Inspire listing and prompt-to-editor navigation; automated tests for mapping, undo, model compatibility, actor roles and account isolation.
M3 secure PHP admin CMS with provenance and approval workflow, install wizard and MFA.
M4 permission-aware scheduled ingestion, dedupe, monitoring and takedowns.
M5 verified provider adapters and backend generation queues.
M6 full editor integration and end-to-end device testing.
Do not merge unfinished mobile/web changes into main until CI and security review pass.
