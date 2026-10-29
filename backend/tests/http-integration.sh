#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source backend/tests/auth-helper.sh
BASE='http://127.0.0.1:18884'
php -S 127.0.0.1:18884 -t backend/public backend/public/router.php >/tmp/hotice-php-test.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for i in $(seq 1 40); do if curl -fsS "$BASE/health" >/dev/null; then break; fi; sleep 0.25; done
curl -fsS "$BASE/health" | jq -e '.status == "ok"' >/dev/null
unknown_reset=$(curl -sS -w '\n%{http_code}' -H 'Content-Type: application/json' \
  -d '{"email":"unknown-reset@example.com"}' "$BASE/v1/auth/password-reset/request")
test "${unknown_reset##*$'\n'}" = '202'
echo "${unknown_reset%$'\n'*}" | jq -e '.accepted == true' >/dev/null
cors_headers=$(mktemp)
curl -sS -D "$cors_headers" -o /dev/null -H 'Origin: https://studio.hotice.test' "$BASE/health"
grep -iq '^Access-Control-Allow-Origin: https://studio.hotice.test' "$cors_headers"
grep -iq '^Vary: Origin' "$cors_headers"
! grep -iq '^Access-Control-Allow-Credentials:' "$cors_headers"
! grep -iq '^Access-Control-Allow-Origin: \*' "$cors_headers"
preflight_status=$(curl -sS -D "$cors_headers" -o /dev/null -w '%{http_code}' -X OPTIONS \
  -H 'Origin: https://studio.hotice.test' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,content-type,idempotency-key' \
  "$BASE/v1/auth/login")
test "$preflight_status" = '204'
grep -iq '^Access-Control-Allow-Headers: Authorization, Content-Type, Idempotency-Key' "$cors_headers"
blocked_origin=$(curl -sS -D "$cors_headers" -o /dev/null -w '%{http_code}' \
  -H 'Origin: https://attacker.example' "$BASE/health")
test "$blocked_origin" = '403'
! grep -iq '^Access-Control-Allow-Origin:' "$cors_headers"
blocked_header=$(curl -sS -o /dev/null -w '%{http_code}' -X OPTIONS \
  -H 'Origin: https://studio.hotice.test' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,x-unapproved' \
  "$BASE/v1/auth/login")
test "$blocked_header" = '403'
rm -f "$cors_headers"
php -r 'require "backend/src/App.php"; try { new Hotice\App(["app_key"=>str_repeat("a",64),"web_allowed_origins"=>["*"],"db"=>["dsn"=>"invalid:dsn","user"=>"","password"=>""]]); exit(1); } catch (RuntimeException $e) { if (!str_contains(strtolower($e->getMessage()),"origin")) exit(1); }'
php -r 'require "backend/src/App.php"; try { new Hotice\App(["app_key"=>str_repeat("a",64),"web_allowed_origins"=>["https://studio.example.com/path"],"db"=>["dsn"=>"invalid:dsn","user"=>"","password"=>""]]); exit(1); } catch (RuntimeException $e) { if (!str_contains(strtolower($e->getMessage()),"origin")) exit(1); }'
EMAIL='cloud-integration@example.com'
PASS='TemporaryTestPassword123!'
register_and_verify "$EMAIL" "$PASS"
login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login")
token=$(echo "$login" | jq -er '.accessToken')
test "${#token}" -eq 64
AUTH="Authorization: Bearer $token"
curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -e '.cloud.active == false' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$AUTH" "$BASE/v1/projects")
test "$status" = '403'
php backend/bin/grant-trial.php "$EMAIL" 32 1
curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -e '.cloud.active == true and .cloud.quotaBytes == 33554432' >/dev/null
id='11111111-1111-4111-8111-111111111111'
file='22222222-2222-4222-8222-222222222222'
payload='{"title":"Saved device project","expectedRevision":0,"document":{"scenes":[{"prompt":"A moonlit street"}],"localFirst":true}}'
new=$(curl -fsS -X PUT -H "$AUTH" -H 'Content-Type: application/json' -d "$payload" "$BASE/v1/projects/$id")
echo "$new" | jq -e '.revision == 1' >/dev/null
other_project='33333333-3333-4333-8333-333333333333'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "$AUTH" -H 'Content-Type: application/json' -d "$payload" "$BASE/v1/projects/$other_project")
test "$status" = '413'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "$AUTH" -H 'Content-Type: application/json' -d "$payload" "$BASE/v1/projects/$id")
test "$status" = '409'
curl -fsS -H "$AUTH" "$BASE/v1/projects/$id" | jq -e '.project.revision == 1 and .project.document.localFirst == true' >/dev/null
curl -fsS -H "$AUTH" "$BASE/v1/projects" | jq -e '.projects | length == 1' >/dev/null
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/9WkAAAAASUVORK5CYII=' | base64 -d >/tmp/hotice-ci-test.png
uploaded=$(curl -fsS -X PUT -H "$AUTH" -H 'Content-Type: application/octet-stream' --data-binary @/tmp/hotice-ci-test.png "$BASE/v1/projects/$id/files/$file")
echo "$uploaded" | jq -e '.mime == "image/png" and .byteSize > 0 and .scanStatus == "pending"' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$AUTH" "$BASE/v1/files/$file")
test "$status" = '423'
php backend/bin/scan-media.php 20 | jq -e '.scannedClean == 1 and .blocked == 0' >/dev/null
curl -fsS -H "$AUTH" "$BASE/v1/projects/$id" | jq -e '.files[0].scan_status == "clean"' >/dev/null
other_file='44444444-4444-4444-8444-444444444444'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "$AUTH" -H 'Content-Type: application/octet-stream' --data-binary @/tmp/hotice-ci-test.png "$BASE/v1/projects/$id/files/$other_file")
test "$status" = '413'
curl -fsS -H "$AUTH" "$BASE/v1/files/$file" -o /tmp/hotice-ci-download.png
cmp /tmp/hotice-ci-test.png /tmp/hotice-ci-download.png

# A *different entitled account* must not access, overwrite, erase or
# enumerate the first account's cloud data; free-vs-paid checks are insufficient.
other_email='cloud-isolation@example.com'
register_and_verify "$other_email" "$PASS"
other_token=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$other_email\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login" | jq -er '.accessToken')
php backend/bin/grant-trial.php "$other_email" 32 1
OTHER_AUTH="Authorization: Bearer $other_token"
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$OTHER_AUTH" "$BASE/v1/projects/$id")
test "$status" = '404'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "$OTHER_AUTH" -H 'Content-Type: application/json' -d '{"title":"Stolen title","expectedRevision":1,"document":{"stolen":true}}' "$BASE/v1/projects/$id")
test "$status" = '404'
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$OTHER_AUTH" "$BASE/v1/files/$file")
test "$status" = '404'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "$OTHER_AUTH" "$BASE/v1/projects/$id")
test "$status" = '404'
curl -fsS -H "$AUTH" "$BASE/v1/projects/$id" | jq -e '.project.revision == 1' >/dev/null
# Round-trip fidelity matters: Flutter maps {} to {}, not [].
json_patch='{"title":"Keep object shapes","expectedRevision":1,"document":{"emptyObject":{},"emptyList":[],"scene":{"settings":{}}}}'
curl -fsS -X PUT -H "$AUTH" -H 'Content-Type: application/json' -d "$json_patch" \
  "$BASE/v1/projects/$id" | jq -e '.revision == 2' >/dev/null
curl -fsS -H "$AUTH" "$BASE/v1/projects/$id" \
  | jq -e '.project.revision == 2 and (.project.document.emptyObject | type) == "object" and (.project.document.emptyList | type) == "array" and (.project.document.scene.settings | type) == "object"' >/dev/null
curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -e '.cloud.usedBytes > 0' >/dev/null
curl -fsS -X DELETE -H "$AUTH" "$BASE/v1/projects/$id" | jq -e '.deleted == true' >/dev/null
curl -fsS -H "$AUTH" "$BASE/v1/me" | jq -e '.cloud.usedBytes == 0' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$AUTH" "$BASE/v1/files/$file")
test "$status" = '404'
NEW_PASS='NewTemporaryPassword456!'
reset_password "$EMAIL" "$NEW_PASS"
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$AUTH" "$BASE/v1/me")
test "$status" = '401'
status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login")
test "$status" = '401'
token=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$NEW_PASS\"}" "$BASE/v1/auth/login" | jq -er '.accessToken')
AUTH="Authorization: Bearer $token"
curl -fsS -X POST -H "$AUTH" "$BASE/v1/auth/logout" | jq -e '.ok == true' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$AUTH" "$BASE/v1/me")
test "$status" = '401'
# Failed-login budgets use both a user-address HMAC and a client-IP HMAC.
# An attacker cannot reset the global IP budget by a valid login.
spray_email='brute-force-target@example.com'
for i in $(seq 1 12); do
  status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"email\":\"$spray_email\",\"password\":\"InvalidPassword$i\"}" "$BASE/v1/auth/login")
  test "$status" = '401'
done
status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d "{\"email\":\"$spray_email\",\"password\":\"InvalidPassword13\"}" "$BASE/v1/auth/login")
test "$status" = '429'

echo 'HOTICE MySQL + HTTP API integration: passed (auth, entitlement, project conflict, media, delete, logout).'


