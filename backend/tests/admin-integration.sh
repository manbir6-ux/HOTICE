#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE='http://127.0.0.1:18885'
TMP_DIR=$(mktemp -d)
SERVER_PID=''
trap 'if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi; rm -rf "$TMP_DIR"' EXIT

# Mark HTTPS inside this loopback-only test router; never copy it to a deployed server.
cat >"$TMP_DIR/https-router.php" <<'PHP'
<?php
$_SERVER['HTTPS'] = 'on';
$routeResult = require getenv('HOTICE_TEST_ROOT') . '/backend/public/router.php';
if ($routeResult === false) return false;
PHP
HOTICE_TEST_ROOT="$PWD" php -S 127.0.0.1:18885 -t backend/public "$TMP_DIR/https-router.php" >"$TMP_DIR/server.log" 2>&1 &
SERVER_PID=$!
page=''
for _ in $(seq 1 40); do
  page=$(curl -sS -c "$TMP_DIR/cookies" "$BASE/admin.php" || true)
  if [[ "$page" == *'Owner sign in'* ]]; then break; fi
  sleep 0.25
done
if [[ "$page" != *'Owner sign in'* ]]; then printf 'Unexpected admin response: %s\n' "${page:0:200}"; cat "$TMP_DIR/server.log"; exit 1; fi
grep -qi 'set-cookie: HOTICE_OWNER=.*secure.*httponly' <(curl -sS -D - -o /dev/null "$BASE/admin.php")

owner_email='owner-integration@example.com'
owner_password='TemporaryOwnerPassword123!'
owner_output=$(printf '%s\n' "$owner_password" | php backend/bin/create-owner.php "$owner_email" 2>"$TMP_DIR/create-owner.err") || {
  echo 'Owner provisioning command failed.'; cat "$TMP_DIR/create-owner.err"; exit 1;
}
totp_secret=$(printf '%s\n' "$owner_output" | sed -n 's/^Secret: //p')
if [[ ${#totp_secret} -lt 20 ]]; then echo 'Owner provisioning did not return its TOTP setup secret.'; cat "$TMP_DIR/create-owner.err"; exit 1; fi
code=$(php -r 'require "backend/src/AdminSecurity.php"; echo \Hotice\AdminSecurity::totp($argv[1], time());' "$totp_secret")

headers="$TMP_DIR/headers"
login_cookie=$(curl -sS -D "$headers" -o "$TMP_DIR/login" -b "$TMP_DIR/cookies" -c "$TMP_DIR/cookies" -w '%{http_code}' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)" \
  --data-urlencode 'action=login' --data-urlencode "email=$owner_email" \
  --data-urlencode "password=$owner_password" --data-urlencode "totp=$code" "$BASE/admin.php")
if [[ "$login_cookie" != '303' ]]; then echo "Owner login returned HTTP $login_cookie."; cat "$TMP_DIR/login"; exit 1; fi
session=$(sed -n 's/^[Ss]et-[Cc]ookie: HOTICE_OWNER=\([^;]*\).*/\1/p' "$headers" | tail -1)
test -n "$session"
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
[[ "$page" == *'Operations overview'* ]]
[[ "$page" == *'Recent provider attempts'* && "$page" == *'unknown outcome keeps its credit reservation'* ]]
csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)
test -n "$csrf"

managed_email='managed-user@example.com'
managed_password='TemporaryManagedPassword123!'
curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$managed_email\",\"password\":\"$managed_password\"}" "$BASE/v1/auth/register" >/dev/null
user_id=$(php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new \Hotice\App($c))->database(); $q=$db->prepare("SELECT id FROM users WHERE email=?"); $q->execute([$argv[1]]); echo $q->fetchColumn();' "$managed_email")
test -n "$user_id"
user_login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$managed_email\",\"password\":\"$managed_password\"}" "$BASE/v1/auth/login")
user_token=$(echo "$user_login" | jq -er '.accessToken')
php backend/bin/grant-mock-credits.php "$managed_email" 5 'owner-attempt-view-credit-001' >/dev/null
attempt_request=$(jq -cn '{modelId:"hotice.mock.video.v1",prompt:"Owner console attempt view smoke",simulate:"success"}')
attempt_quote=$(curl -fsS -H "Authorization: Bearer $user_token" -H 'Content-Type: application/json' \
  -d "$(jq -cn --argjson r "$attempt_request" '{request:$r}')" "$BASE/v1/jobs/quote" | jq -er '.quoteToken')
attempt_body=$(jq -cn --arg q "$attempt_quote" --argjson r "$attempt_request" '{quoteToken:$q,request:$r}')
attempt_job=$(curl -fsS -X POST -H "Authorization: Bearer $user_token" -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: owner-view-attempt-00000001' -d "$attempt_body" "$BASE/v1/jobs" | jq -er '.job.id')
php backend/bin/jobs-worker.php --once | jq -e '.status == "succeeded"' >/dev/null
attempt_operation=$(php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new \Hotice\App($c))->database(); $q=$db->prepare("SELECT remote_operation_id FROM provider_attempts WHERE job_id=?"); $q->execute([$argv[1]]); echo $q->fetchColumn();' "$attempt_job")
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
[[ "$page" == *"$attempt_job"* && "$page" == *"$attempt_operation"* && "$page" == *"$managed_email"* ]]
csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^\"]*\)".*/\1/p' | head -1)
status=$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' -H "Cookie: HOTICE_OWNER=$session" \
  -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "csrf=$csrf" \
  --data-urlencode 'action=disable_user' --data-urlencode "user_id=$user_id" "$BASE/admin.php")
test "$status" = '303'
test "$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $user_token" "$BASE/v1/me")" = '401'
test "$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "{\"email\":\"$managed_email\",\"password\":\"$managed_password\"}" "$BASE/v1/auth/login")" = '401'
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
[[ "$page" == *'Disabled'* ]]
csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^\"]*\)".*/\1/p' | head -1)
status=$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' -H "Cookie: HOTICE_OWNER=$session" \
  -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "csrf=$csrf" \
  --data-urlencode 'action=enable_user' --data-urlencode "user_id=$user_id" "$BASE/admin.php")
test "$status" = '303'
test "$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $user_token" "$BASE/v1/me")" = '401'
fresh_login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$managed_email\",\"password\":\"$managed_password\"}" "$BASE/v1/auth/login")
fresh_token=$(echo "$fresh_login" | jq -er '.accessToken')
trial_auth="Authorization: Bearer $fresh_token"
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^\"]*\)".*/\1/p' | head -1)
status=$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' -H "Cookie: HOTICE_OWNER=$session" \
  -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "csrf=$csrf" \
  --data-urlencode 'action=grant_cloud_trial' --data-urlencode "user_id=$user_id" \
  --data-urlencode 'quota_mib=32' --data-urlencode 'days=7' "$BASE/admin.php")
test "$status" = '303'
curl -fsS -H "$trial_auth" "$BASE/v1/me" | jq -e '.cloud.active == true and .cloud.plan == "trial" and .cloud.quotaBytes == 33554432' >/dev/null
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^\"]*\)".*/\1/p' | head -1)
status=$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' -H "Cookie: HOTICE_OWNER=$session" \
  -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "csrf=$csrf" \
  --data-urlencode 'action=revoke_cloud_trial' --data-urlencode "user_id=$user_id" "$BASE/admin.php")
test "$status" = '303'
curl -fsS -H "$trial_auth" "$BASE/v1/me" | jq -e '.cloud.active == false and .cloud.readable == true' >/dev/null

# An owner trial action cannot replace an entitlement managed by verified billing.
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new \Hotice\App($c))->database(); $q=$db->prepare("UPDATE cloud_entitlements SET source=?,plan_code=?,quota_bytes=67108864,expires_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 7 DAY) WHERE user_id=?"); $q->execute(["verified_billing","pro",$argv[1]]);' "$user_id"
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^\"]*\)".*/\1/p' | head -1)
status=$(curl -sS -o "$TMP_DIR/trial-denied" -w '%{http_code}' -H "Cookie: HOTICE_OWNER=$session" \
  -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "csrf=$csrf" \
  --data-urlencode 'action=grant_cloud_trial' --data-urlencode "user_id=$user_id" \
  --data-urlencode 'quota_mib=1' --data-urlencode 'days=1' "$BASE/admin.php")
test "$status" = '200'
grep -q 'Paid cloud access is controlled by verified billing' "$TMP_DIR/trial-denied"
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new \Hotice\App($c))->database(); $q=$db->prepare("SELECT source,plan_code,quota_bytes FROM cloud_entitlements WHERE user_id=?"); $q->execute([$argv[1]]); $e=$q->fetch(); if (!$e || $e["source"]!=="verified_billing" || $e["plan_code"]!=="pro" || (int)$e["quota_bytes"]!==67108864) exit(1);' "$user_id"

test_key='ci-only-provider-secret-never-a-real-key'
status=$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' \
  -H "Cookie: HOTICE_OWNER=$session" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "csrf=$csrf" --data-urlencode 'action=save_provider' \
  --data-urlencode 'provider=openai' --data-urlencode "secret=$test_key" "$BASE/admin.php")
test "$status" = '303'
page=$(curl -fsS -H "Cookie: HOTICE_OWNER=$session" "$BASE/admin.php")
[[ "$page" == *'OpenAI'* && "$page" == *'Configured'* ]]
[[ "$page" != *"$test_key"* ]]

TEST_PROVIDER_SECRET="$test_key" php -r '
require "backend/src/App.php";
require "backend/src/AdminSecurity.php";
$c=require "backend/config.php";
$db=(new \Hotice\App($c))->database();
$r=$db->query("SELECT provider,ciphertext,nonce,tag FROM provider_secrets WHERE provider=\"openai\"")->fetch();
if (!$r || $r["ciphertext"] === getenv("TEST_PROVIDER_SECRET")) exit(1);
if (\Hotice\AdminSecurity::decryptProviderKey($r["provider"],$r["ciphertext"],$r["nonce"],$r["tag"],$c["app_key"]) !== getenv("TEST_PROVIDER_SECRET")) exit(1);
'

csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)
status=$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' \
  -H "Cookie: HOTICE_OWNER=$session" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "csrf=$csrf" --data-urlencode 'action=delete_provider' \
  --data-urlencode 'provider=openai' "$BASE/admin.php")
test "$status" = '303'
php -r 'require "backend/src/App.php"; $c=require "backend/config.php"; $db=(new \Hotice\App($c))->database(); if ($db->query("SELECT COUNT(*) FROM provider_secrets WHERE provider=\"openai\"")->fetchColumn()!=0) exit(1);'

csrf=$(printf '%s' "$page" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "Cookie: HOTICE_OWNER=$session" \
  -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "csrf=wrong" \
  --data-urlencode 'action=save_provider' --data-urlencode 'provider=google' \
  --data-urlencode 'secret=blocked' "$BASE/admin.php")
test "$status" = '400'
echo 'Owner MFA/session, user access, trial entitlement and billing-protection, encrypted key, no-echo, deletion and CSRF checks passed.'

