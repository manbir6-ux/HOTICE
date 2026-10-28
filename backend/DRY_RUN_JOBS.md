# Generation job API dry run

This release slice verifies authenticated quote and job contracts, queue ownership, idempotency, retry/recovery and simulated credit accounting without contacting an AI provider. The only accepted model is `hotice.mock.video.v1`; it creates a status message, **not a video**. Do not present mock completion as generated media.

## Enable only on a staging/test server

Set these values in private `backend/config.php`:

```php
'mock_jobs_enabled' => true,
'mock_job_cost_credits' => 5,
'mock_job_quote_ttl_seconds' => 300,
```

The example and production defaults keep `mock_jobs_enabled` false. Mock credits have no cash or subscription value. They are a local test instrument only; no payment processor or real AI provider is wired to these endpoints.

Create a regular staging user, then grant simulated credits with an operator-controlled CLI command:

```sh
php backend/bin/grant-mock-credits.php user@example.com 100 'staging-grant-20261028-001'
```

The idempotency key is retained only as a hash in the append-only ledger. Repeating the same command adds no duplicate credits. Do not use this command to record real payments.

## User contract

1. Authenticate with a bearer session.
2. `POST /v1/jobs/quote` with JSON `{ "request": { "modelId": "hotice.mock.video.v1", "prompt": "...", "simulate": "success" } }`. The quote is HMAC-signed, binds the exact normalized request and user, expires in 5 minutes by default, and is one-use.
3. `POST /v1/jobs` with the same `request`, returned `quoteToken`, and an `Idempotency-Key` header containing 16–128 safe characters. The server reserves the quoted mock credits atomically before queueing. Reusing the same key/request returns the original job; reusing a key with a different request returns 409.
4. Poll `GET /v1/jobs/{uuid}` or `GET /v1/jobs`; `POST /v1/jobs/{uuid}/cancel` cancels only queued work and refunds its reservation exactly once.
5. `GET /v1/me` reports `mockGeneration` explicitly; it is not a balance of money, real AI usage, or an entitlement.

The mock worker is CLI-only and uses a singleton database lock. Run it once per invocation with `php backend/bin/jobs-worker.php --once`; cPanel Cron may invoke it every minute for staging. It supports deterministic local `timeout_once`, `rate_limit_once`, `malformed_once`, `permanent_failure`, and `success` paths. Retries are bounded to three attempts, use a 60-second worker lease, and refund credits exactly once after final failure or lease exhaustion. Provider timeouts, callbacks, remote cancellation, outputs, external queue scaling and real billing settlement are not implemented.

## Verification

`backend/tests/jobs-integration.sh` covers quote binding/tampering, duplicate submissions, idempotency conflicts, per-user isolation, success, simulated permanent failure and refund, timeout/rate-limit/malformed retries, cancellation and balance consistency against MySQL. GitHub Actions uses throwaway users, credentials, database and a local-only five-credit tariff. No real provider keys are configured or used.

## Production gates still open

Real model catalogs and account/region entitlement checks, provider adapters, signed quotes from a maintained pricing catalog, real currency conversion, payment webhooks, charge reservation/settlement/reconciliation, audit and fraud policy, attachment uploads, moderation, capacity/worker operations, output storage, retention, privacy/compliance and live staging review remain required before enabling any real provider call.
