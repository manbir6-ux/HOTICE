# Paid provider dispatch safety gate

**Status: design gate only. Live provider dispatch is not implemented or enabled.** The current `MockJobWorker` registers only `MockProviderAdapter` and must remain the only worker available until every gate below is implemented and verified. Mock adapter idempotency exists only in process memory; it does not prove that a remote provider deduplicates submissions.

The mock worker now persists a `provider_attempts` row in the same transaction as each job claim. It records only provider/model identifiers, request digest, stable per-attempt idempotency key, lease token, normalized state, and (after acceptance) the remote operation ID. If an accepted/dispatching attempt has an expired lease, recovery changes it to `unknown`, leaves the job reserved and non-claimable, and does not retry or refund. This exercises the durable fail-closed path without network access. **There is not yet an owner reconciliation action or live-provider worker**, and the mock adapter's in-memory operation cannot be resumed after process restart.

## Failure that must be safe

A worker can send a generation request, the provider can accept and bill it, and the connection can fail before HOTICE receives or stores the provider operation ID. Retrying the job may create and bill a second operation. A process can also stop after receiving the operation ID but before persisting it. A normal worker lease expiring does not prove the provider did not accept the request.

## Required durable lifecycle

Before any network submission, persist a provider-attempt row in the same database transaction that claims the job. Bind it to the job, provider, model, monotonically increasing attempt number, stable HOTICE operation UUID, request digest, creation time, and status. Never persist plaintext prompts, attachment bytes, credentials, or raw provider response bodies in that row or logs.

Use explicit states with guarded transitions:

| State | Meaning | Automatic action |
| --- | --- | --- |
| `prepared` | Durable intent exists; submission has not begun | A worker may atomically claim it once |
| `dispatching` | Submission may have reached the provider | Never resubmit on lease expiry; reconcile first |
| `accepted` | Provider operation ID is durably recorded | Poll that exact operation |
| `unknown` | Acceptance cannot be confirmed or ruled out | Hold reservation; reconcile or require operator action |
| `succeeded` | Provider reported completion and result is safely ingested | Settle once after output verification |
| `retryable_rejected` | Provider definitively rejected before creating work | Retry only within bounded policy |
| `failed` / `cancelled` | Terminal provider outcome is confirmed | Refund once according to ledger policy |

Use compare-and-swap updates with attempt UUID and lease token. Persist the returned remote ID before any further provider call. Reconciliation must query by a provider-supported stable request/idempotency identifier, or by a persisted remote ID. If the provider offers neither and the submission outcome is ambiguous, retain the reservation and mark `unknown`; do not automatically submit again or refund while a paid remote operation may still be running.

## Required proof before enabling a live adapter

- Verify the provider's current official API contract for idempotency, request lookup, timeout semantics, polling, cancellation, output URL expiry and account/region/model access. Treat undocumented behavior as unsupported.
- Build a durable provider-attempt table and migration that is safe on the supported cPanel MySQL version, plus rollback/backup instructions.
- Separate dispatch, poll and reconciliation workers. Polling a known remote ID must never invoke submit.
- Add fault-injection integration tests for process termination before send, after provider acceptance, after receiving an ID but before commit, duplicate worker claims, delayed responses, rate limits, malformed responses, cancellation races, expiry and concurrent refunds.
- Prove exactly-once local credit reservation/settlement/refund with unique ledger event keys; external charges are only effectively-once when the provider's documented semantics support it.
- Gate each provider/model behind a server-side default-off feature flag and an owner-only staged enablement. User-controlled settings must never select adapter code or supply endpoint URLs.
- Keep credentials server-only, redact authorization and request/response payloads, and copy outputs to private HOTICE storage before issuing short-lived authorized download links.
- Exercise staging with a provider sandbox or explicit non-billable account, then document an owner-reviewed live smoke test. No production paid calls belong in routine CI.

## Release decision

Until these conditions pass for a specific provider and model, the adapter interface and mock dry run are contract scaffolding only. Do not advertise generation as available, mark provider gates passed, or interpret a mock result as media. True 3D reconstruction and physical-device identity validation remain separate release gates.
