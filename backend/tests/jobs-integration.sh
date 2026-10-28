#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE='http://127.0.0.1:18886'
php -S 127.0.0.1:18886 -t backend/public backend/public/router.php >/tmp/hotice-job-test.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do if curl -fsS "$BASE/health" >/dev/null; then break; fi; sleep 0.25; done

EMAIL='mock-jobs@example.com'
PASS='TemporaryMockPassword123!'
OTHER='mock-outsider@example.com'
OTHER_PASS='TemporaryOtherPassword123!'
curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/register" >/dev/null
curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$OTHER\",\"password\":\"$OTHER_PASS\"}" "$BASE/v1/auth/register" >/dev/null
login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login")
token=$(echo "$login" | jq -er '.accessToken')
other_login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$OTHER\",\"password\":\"$OTHER_PASS\"}" "$BASE/v1/auth/login")
other_token=$(echo "$other_login" | jq -er '.accessToken')
AUTH="Authorization: Bearer $token"
OTHER_AUTH="Authorization: Bearer $other_token"

php backend/bin/grant-mock-credits.php "$EMAIL" 100 'initial-test-credit-grant-01'
echo 'checkpoint: initial credits granted'
php backend/bin/grant-mock-credits.php "$EMAIL" 100 'initial-test-credit-grant-01' | grep -q 'already applied'
echo 'checkpoint: credit grant replay is idempotent'
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '100'
echo 'checkpoint: account reports simulated credits'

request=$(jq -cn --arg p 'A blue sailboat at sunrise' '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:"success"}')
quote_body=$(jq -cn --argjson r "$request" '{request:$r}')
quote_response=$(curl -sS -H "$AUTH" -H 'Content-Type: application/json' -d "$quote_body" "$BASE/v1/jobs/quote")
quote=$(echo "$quote_response" | jq -er '.quoteToken') || { echo "Quote response: $quote_response"; cat /tmp/hotice-job-test.log; exit 1; }
body=$(jq -cn --arg q "$quote" --argjson r "$request" '{quoteToken:$q,request:$r}')
key='mock-job-success-00000001'
first=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $key" -d "$body" "$BASE/v1/jobs")
job=$(echo "$first" | jq -er '.job.id')
test "$(echo "$first" | jq -er '.job.status')" = 'queued'
test "$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $key" -d "$body" "$BASE/v1/jobs" | jq -er '.job.idempotentReplay')" = 'true'
changed=$(jq -cn --arg q "$quote" '{quoteToken:$q,request:{modelId:"hotice.mock.video.v1",prompt:"Different prompt",simulate:"success"}}')
test "$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $key" -d "$changed" "$BASE/v1/jobs")" = '409'
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '95'
php backend/bin/jobs-worker.php --once | jq -e '.status == "succeeded"' >/dev/null
job_state=$(curl -fsS -H "$AUTH" "$BASE/v1/jobs/$job")
test "$(echo "$job_state" | jq -er '.job.status')" = 'succeeded'
test "$(echo "$job_state" | jq -er '.job.chargedCredits')" = '5'
[[ "$(echo "$job_state" | jq -er '.job.result.message')" == *'No video or provider output'* ]]
test "$(curl -sS -o /dev/null -w '%{http_code}' -H "$OTHER_AUTH" "$BASE/v1/jobs/$job")" = '404'

request=$(jq -cn --arg p 'Permanent provider rejection simulation' '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:"permanent_failure"}')
quote=$(curl -fsS -H "$AUTH" -H 'Content-Type: application/json' -d "$(jq -cn --argjson r "$request" '{request:$r}')" "$BASE/v1/jobs/quote" | jq -er '.quoteToken')
body=$(jq -cn --arg q "$quote" --argjson r "$request" '{quoteToken:$q,request:$r}')
job=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H 'Idempotency-Key: mock-job-failure-00000001' -d "$body" "$BASE/v1/jobs" | jq -er '.job.id')
php backend/bin/jobs-worker.php --once | jq -e '.status == "failed"' >/dev/null
test "$(curl -fsS -H "$AUTH" "$BASE/v1/jobs/$job" | jq -er '.job.status')" = 'failed'
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '95'

for scenario in timeout_once rate_limit_once malformed_once; do
  request=$(jq -cn --arg p "Retry simulation $scenario" --arg s "$scenario" '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:$s}')
  quote=$(curl -fsS -H "$AUTH" -H 'Content-Type: application/json' -d "$(jq -cn --argjson r "$request" '{request:$r}')" "$BASE/v1/jobs/quote" | jq -er '.quoteToken')
  body=$(jq -cn --arg q "$quote" --argjson r "$request" '{quoteToken:$q,request:$r}')
  job=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: mock-retry-$scenario-0001" -d "$body" "$BASE/v1/jobs" | jq -er '.job.id')
  php backend/bin/jobs-worker.php --once | jq -e '.status == "queued"' >/dev/null
  sleep 2
  php backend/bin/jobs-worker.php --once | jq -e '.status == "succeeded"' >/dev/null
  test "$(curl -fsS -H "$AUTH" "$BASE/v1/jobs/$job" | jq -er '.job.attempts')" = '2'
done
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '80'

request=$(jq -cn --arg p 'Cancel queued dry run' '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:"success"}')
quote=$(curl -fsS -H "$AUTH" -H 'Content-Type: application/json' -d "$(jq -cn --argjson r "$request" '{request:$r}')" "$BASE/v1/jobs/quote" | jq -er '.quoteToken')
body=$(jq -cn --arg q "$quote" --argjson r "$request" '{quoteToken:$q,request:$r}')
job=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H 'Idempotency-Key: mock-job-cancel-000000001' -d "$body" "$BASE/v1/jobs" | jq -er '.job.id')
curl -fsS -X POST -H "$AUTH" "$BASE/v1/jobs/$job/cancel" | jq -e '.job.status == "cancelled"' >/dev/null
curl -fsS -X POST -H "$AUTH" "$BASE/v1/jobs/$job/cancel" | jq -e '.alreadyCancelled == true' >/dev/null
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '80'

request=$(jq -cn --arg p 'Tampered quote must fail closed' '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:"success"}')
quote=$(curl -fsS -H "$AUTH" -H 'Content-Type: application/json' -d "$(jq -cn --argjson r "$request" '{request:$r}')" "$BASE/v1/jobs/quote" | jq -er '.quoteToken')
tampered="${quote%?}x"
body=$(jq -cn --arg q "$tampered" --argjson r "$request" '{quoteToken:$q,request:$r}')
test "$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "$AUTH" -H 'Content-Type: application/json' -H 'Idempotency-Key: mock-job-tamper-00000001' -d "$body" "$BASE/v1/jobs")" = '422'

echo 'Mock job quote, idempotency, ownership, retries, cancellation, simulated credits and refund checks passed. No provider call or video output was created.'

