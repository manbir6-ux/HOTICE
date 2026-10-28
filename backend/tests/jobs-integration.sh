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
php backend/bin/grant-mock-credits.php "$EMAIL" 100 'initial-test-credit-grant-01' | grep -q 'already applied'
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '100'

request=$(jq -cn --arg p 'A blue sailboat at sunrise' '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:"success"}')
quote_body=$(jq -cn --argjson r "$request" '{request:$r}')
quote_response=$(curl -sS -H "$AUTH" -H 'Content-Type: application/json' -d "$quote_body" "$BASE/v1/jobs/quote")
quote=$(echo "$quote_response" | jq -er '.quoteToken') || { echo "Quote response: $quote_response"; cat /tmp/hotice-job-test.log; exit 1; }
body=$(jq -cn --arg q "$quote" --argjson r "$request" '{quoteToken:$q,request:$r}')
key='mock-job-success-00000001'
first=$(curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $key" -d "$body" "$BASE/v1/jobs")
job=$(echo "$first" | jq -er '.job.id')
test "$(echo "$first" | jq -er '.job.status')" = 'queued'
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT user_id,request_json,request_sha256 FROM generation_jobs WHERE id=?"); $q->execute([$argv[1]]); $row=$q->fetch(); $stored=json_decode((string)$row["request_json"],true); $request=["modelId"=>"hotice.mock.video.v1","prompt"=>"A blue sailboat at sunrise","simulate"=>"success"]; $canonical=json_encode($request,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR); $expected=hash_hmac("sha256","hotice:mock-request:v1\0".$row["user_id"]."\0".$canonical,$c["app_key"]); if (!is_array($stored) || isset($stored["prompt"]) || array_keys($stored)!==["modelId","simulate"] || !hash_equals($expected,$row["request_sha256"])) exit(1);' "$job"
replay=$(curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $key" -d "$body" "$BASE/v1/jobs")
test "$(echo "$replay" | jq -er '.idempotentReplay')" = 'true'
changed=$(jq -cn --arg q "$quote" '{quoteToken:$q,request:{modelId:"hotice.mock.video.v1",prompt:"Different prompt",simulate:"success"}}')
test "$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $key" -d "$changed" "$BASE/v1/jobs")" = '409'
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '95'
php backend/bin/jobs-worker.php --once | jq -e '.status == "succeeded"' >/dev/null
job_state=$(curl -fsS -H "$AUTH" "$BASE/v1/jobs/$job")
test "$(echo "$job_state" | jq -er '.job.status')" = 'succeeded'
test "$(echo "$job_state" | jq -er '.job.chargedCredits')" = '5'
[[ "$(echo "$job_state" | jq -er '.job.result.message')" == *'No video or provider output'* ]]
test "$(echo "$job_state" | jq -r '.job.result | has("requestSha256")')" = 'false'
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT provider_id,model_id,status,request_sha256,remote_operation_id FROM provider_attempts WHERE job_id=? ORDER BY attempt_number"); $q->execute([$argv[1]]); $rows=$q->fetchAll(); if (count($rows)!==1 || $rows[0]["provider_id"]!=="mock" || $rows[0]["model_id"]!=="hotice.mock.video.v1" || $rows[0]["status"]!=="succeeded" || !preg_match("/^[a-f0-9]{64}$/",$rows[0]["request_sha256"]) || !Hotice\Support::isUuid($rows[0]["remote_operation_id"])) exit(1);' "$job"
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
  php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT status FROM provider_attempts WHERE job_id=? ORDER BY attempt_number"); $q->execute([$argv[1]]); if ($q->fetchAll(PDO::FETCH_COLUMN)!==["retryable_rejected","succeeded"]) exit(1);' "$job"
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

request=$(jq -cn --arg p 'Expired worker lease simulation' '{modelId:"hotice.mock.video.v1",prompt:$p,simulate:"success"}')
quote=$(curl -fsS -H "$AUTH" -H 'Content-Type: application/json' -d "$(jq -cn --argjson r "$request" '{request:$r}')" "$BASE/v1/jobs/quote" | jq -er '.quoteToken')
body=$(jq -cn --arg q "$quote" --argjson r "$request" '{quoteToken:$q,request:$r}')
job=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -H 'Idempotency-Key: mock-job-expired-lease-001' -d "$body" "$BASE/v1/jobs" | jq -er '.job.id')
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $db->prepare("UPDATE generation_jobs SET status=\x27processing\x27,attempt_count=max_attempts,lease_token=REPEAT(\x27a\x27,32),lease_until=DATE_SUB(UTC_TIMESTAMP(),INTERVAL 1 SECOND) WHERE id=?")->execute([$argv[1]]);' "$job"
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT request_sha256,model_id FROM generation_jobs WHERE id=?"); $q->execute([$argv[1]]); $row=$q->fetch(); $lease=str_repeat("a",32); $id=Hotice\Support::uuid(); $remote=Hotice\Support::uuid(); $db->prepare("INSERT INTO provider_attempts(id,job_id,attempt_number,provider_id,model_id,operation_key,request_sha256,status,remote_operation_id,lease_token) VALUES(?,?,3,\x27mock\x27,?,?,?,\x27dispatching\x27,?,?)")->execute([$id,$argv[1],$row["model_id"],hash("sha256","ambiguous:".$argv[1]),$row["request_sha256"],$remote,$lease]);' "$job"
php backend/bin/jobs-worker.php --once | jq -e '.status == "idle"' >/dev/null
test "$(curl -fsS -H "$AUTH" "$BASE/v1/jobs/$job" | jq -er '.job.status')" = 'processing'
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT status,error_code FROM generation_jobs WHERE id=?"); $q->execute([$argv[1]]); $j=$q->fetch(); $q=$db->prepare("SELECT status,error_code FROM provider_attempts WHERE job_id=? ORDER BY attempt_number DESC LIMIT 1"); $q->execute([$argv[1]]); $a=$q->fetch(); if ($j["status"]!=="processing" || $j["error_code"]!=="provider_outcome_unknown" || $a["status"]!=="unknown" || $a["error_code"]!=="provider_outcome_unknown") exit(1);' "$job"
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '75'
php backend/bin/jobs-worker.php --once | jq -e '.status == "idle"' >/dev/null
test "$(curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -er '.mockGeneration.credits')" = '75'

echo 'Mock job quote, idempotency, ownership, durable provider-attempt states, ambiguous-outcome hold, retries, cancellation, simulated credits and refund checks passed. No provider call or video output was created.'


