#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE='http://127.0.0.1:18884'
php -S 127.0.0.1:18884 -t backend/public backend/public/router.php >/tmp/hotice-php-test.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for i in $(seq 1 40); do if curl -fsS "$BASE/health" >/dev/null; then break; fi; sleep 0.25; done
curl -fsS "$BASE/health" | jq -e '.status == "ok"' >/dev/null
EMAIL='cloud-integration@example.com'
PASS='TemporaryTestPassword123!'
register=$(curl -sS -w '\n%{http_code}' -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/register")
test "${register##*$'\n'}" = '201'
login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login")
token=$(echo "$login" | jq -er '.accessToken')
session_id=$(echo "$login" | jq -er '.sessionId')
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
echo "$uploaded" | jq -e '.mime == "image/png" and .byteSize > 0' >/dev/null
other_file='44444444-4444-4444-8444-444444444444'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "$AUTH" -H 'Content-Type: application/octet-stream' --data-binary @/tmp/hotice-ci-test.png "$BASE/v1/projects/$id/files/$other_file")
test "$status" = '413'
curl -fsS -H "$AUTH" "$BASE/v1/files/$file" -o /tmp/hotice-ci-download.png
cmp /tmp/hotice-ci-test.png /tmp/hotice-ci-download.png

# A *different entitled account* must not access, overwrite, erase or
# enumerate the first account's cloud data; free-vs-paid checks are insufficient.
other_email='cloud-isolation@example.com'
curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$other_email\",\"password\":\"$PASS\"}" "$BASE/v1/auth/register" | jq -e '.registered == true' >/dev/null
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
# Users can inspect their own active sessions and revoke a lost-device session.
second_login=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login")
second_token=$(echo "$second_login" | jq -er '.accessToken')
second_session_id=$(echo "$second_login" | jq -er '.sessionId')
SECOND_AUTH="Authorization: Bearer $second_token"
curl -fsS -H "$SECOND_AUTH" "$BASE/v1/auth/sessions" | jq -e --arg current "$second_session_id" --arg old "$session_id" '.sessions | length == 2 and any(.[]; .id == $current and .current == true) and any(.[]; .id == $old and .current == false)' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "$OTHER_AUTH" "$BASE/v1/auth/sessions/$second_session_id")
test "$status" = '404'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "$SECOND_AUTH" -H 'Content-Type: application/json' \
  -d '{"currentPassword":"WrongCurrentPassword!","newPassword":"NewTemporaryPassword456!"}' "$BASE/v1/auth/password")
test "$status" = '401'
status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "$SECOND_AUTH" -H 'Content-Type: application/json' \
  -d "{\"currentPassword\":\"$PASS\",\"newPassword\":\"$PASS\"}" "$BASE/v1/auth/password")
test "$status" = '422'
curl -fsS -X DELETE -H "$SECOND_AUTH" "$BASE/v1/auth/sessions/$session_id" | jq -e '.revoked == true' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$AUTH" "$BASE/v1/me")
test "$status" = '401'
curl -fsS -H "$SECOND_AUTH" "$BASE/v1/me" | jq -e '.user.email == "cloud-integration@example.com"' >/dev/null
NEW_PASS='ChangedTestPassword456!'
rotated=$(curl -fsS -X POST -H "$SECOND_AUTH" -H 'Content-Type: application/json' \
  -d "{\"currentPassword\":\"$PASS\",\"newPassword\":\"$NEW_PASS\"}" "$BASE/v1/auth/password")
echo "$rotated" | jq -e '.passwordChanged == true and .tokenType == "Bearer"' >/dev/null
rotated_token=$(echo "$rotated" | jq -er '.accessToken')
rotated_session_id=$(echo "$rotated" | jq -er '.sessionId')
test "$rotated_session_id" != "$second_session_id"
ROTATED_AUTH="Authorization: Bearer $rotated_token"
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$SECOND_AUTH" "$BASE/v1/me")
test "$status" = '401'
curl -fsS -H "$ROTATED_AUTH" "$BASE/v1/me" | jq -e '.user.email == "cloud-integration@example.com"' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login")
test "$status" = '401'
updated_login=$(curl -fsS -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$NEW_PASS\"}" "$BASE/v1/auth/login")
updated_token=$(echo "$updated_login" | jq -er '.accessToken')
UPDATED_AUTH="Authorization: Bearer $updated_token"
curl -fsS -X POST -H "$ROTATED_AUTH" "$BASE/v1/auth/logout" | jq -e '.ok == true' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$ROTATED_AUTH" "$BASE/v1/me")
test "$status" = '401'
curl -fsS -H "$UPDATED_AUTH" "$BASE/v1/me" | jq -e '.user.email == "cloud-integration@example.com"' >/dev/null
curl -fsS -X POST -H "$UPDATED_AUTH" "$BASE/v1/auth/logout" | jq -e '.ok == true' >/dev/null
status=$(curl -sS -o /dev/null -w '%{http_code}' -H "$UPDATED_AUTH" "$BASE/v1/me")
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

echo 'HOTICE MySQL + HTTP API integration: passed (auth, password rotation, session inventory/revocation, entitlement, project conflict, media, delete, logout).'
