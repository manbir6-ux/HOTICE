#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE='http://127.0.0.1:18889'
EMAIL='account-delete@example.test'
PASS='AccountDeletePass123!'
OTHER='account-delete-outsider@example.test'
OTHER_PASS='DifferentAccountPass123!'
php -S 127.0.0.1:18889 -t backend/public backend/public/router.php >/tmp/hotice-account-delete-test.log 2>&1 &
server_pid=$!
trap 'status=$?; if [[ $status -ne 0 ]]; then tail -n 80 /tmp/hotice-account-delete-test.log; fi; kill "$server_pid" 2>/dev/null || true; exit "$status"' EXIT
for _ in $(seq 1 40); do if curl -fsS "$BASE/health" >/dev/null; then break; fi; sleep 0.25; done
printf '%s\n' "$PASS" | php backend/bin/create-user.php "$EMAIL" >/dev/null
printf '%s\n' "$OTHER_PASS" | php backend/bin/create-user.php "$OTHER" >/dev/null
echo '[account-lifecycle-test] accounts created'
php backend/bin/grant-trial.php "$EMAIL" 100 7 >/dev/null
php backend/bin/grant-trial.php "$OTHER" 100 7 >/dev/null
echo '[account-lifecycle-test] isolated cloud trial granted'
token=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/v1/auth/login" | jq -er '.accessToken')
other_token=$(curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$OTHER\",\"password\":\"$OTHER_PASS\"}" "$BASE/v1/auth/login" | jq -er '.accessToken')
echo '[account-lifecycle-test] isolated sign-ins passed'
AUTH="Authorization: Bearer $token"
project=$(php -r 'require "backend/src/Support.php"; echo Hotice\Support::uuid();')
file=$(php -r 'require "backend/src/Support.php"; echo Hotice\Support::uuid();')
curl -fsS -X PUT -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"title":"Private deletion fixture","expectedRevision":0,"document":{"scene":"sunrise","localOnly":false}}' \
  "$BASE/v1/projects/$project" >/dev/null
echo '[account-lifecycle-test] cloud project created'
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p4sAAAAASUVORK5CYII=' | base64 -d > /tmp/hotice-account-fixture.png
curl -fsS -X PUT -H "$AUTH" -H 'Content-Type: image/png' --data-binary @/tmp/hotice-account-fixture.png \
  "$BASE/v1/projects/$project/files/$file" >/dev/null
echo '[account-lifecycle-test] private media uploaded'
user_id=$(php -r 'require_once "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT id FROM users WHERE email=?"); $q->execute([$argv[1]]); echo $q->fetchColumn();' "$EMAIL")
php -r '
require_once "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database();
$user=$argv[1]; $quote=Hotice\Support::uuid(); $job=Hotice\Support::uuid();
$db->prepare("INSERT INTO job_quotes(id,user_id,request_sha256,credits,expires_at) VALUES(?,?,?,5,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 HOUR))")->execute([$quote,$user,str_repeat("b",64)]);
$db->prepare("INSERT INTO generation_jobs(id,user_id,quote_id,idempotency_hash,request_sha256,model_id,request_json,reserved_credits) VALUES(?,?,?,?,?,?,?,5)")->execute([$job,$user,$quote,str_repeat("c",64),str_repeat("b",64),"hotice.mock.video.v1",json_encode(["simulate"=>"success"])]);
$db->prepare("INSERT INTO credit_accounts(user_id,balance) VALUES(?,10)")->execute([$user]);
$db->prepare("INSERT INTO credit_ledger(user_id,job_id,event_key,event_type,delta,balance_after) VALUES(?,?,?, ?,10,10)")->execute([$user,$job,str_repeat("d",64),"grant"]);
$db->prepare("INSERT INTO email_outbox(id,recipient,subject,available_at,expires_at) VALUES(?,?,?,UTC_TIMESTAMP(),DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 DAY))")
  ->execute([Hotice\Support::uuid(),$argv[2],"Account deletion fixture"]);
' "$user_id" "$EMAIL"
storage_name=$(php -r 'require_once "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $q=$db->prepare("SELECT storage_name FROM cloud_files WHERE id=?"); $q->execute([$argv[1]]); echo $q->fetchColumn();' "$file")
test -n "$storage_name"
export_json=$(curl -fsS -H "$AUTH" "$BASE/v1/me/export")
echo "$export_json" | jq -e '.format == "hotice-account-export-v1" and .account.email == "account-delete@example.test" and .cloudProjects[0].title == "Private deletion fixture" and .generationJobs[0].request.simulate == "success" and .simulatedCreditLedger[0].delta == 10 and .includedMediaBytes == false' >/dev/null
! echo "$export_json" | jq -e 'has("password_hash") or has("passwordHash") or (.cloudMediaMetadata[]? | has("storage_name"))' >/dev/null
outsider_export=$(curl -fsS -H "Authorization: Bearer $other_token" "$BASE/v1/me/export")
echo "$outsider_export" | jq -e '(.cloudProjects | length) == 0 and (.generationJobs | length) == 0' >/dev/null
echo '[account-lifecycle-test] bounded export and account isolation passed'
test "$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "$AUTH" -H 'Content-Type: application/json' -d '{"confirmation":"DELETE","password":"WrongPassword123!"}' "$BASE/v1/me")" = '403'
test "$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "$AUTH" -H 'Content-Type: application/json' -d '{"confirmation":"delete","password":"AccountDeletePass123!"}' "$BASE/v1/me")" = '422'

# Keep a non-empty directory at the random storage name to simulate a failed
# unlink. Account removal must commit and leave a durable retry record.
storage_path=$(php -r '$c=require "backend/config.php"; echo $c["storage_path"];')
rm "$storage_path/$storage_name"
mkdir "$storage_path/$storage_name"
printf 'keep' > "$storage_path/$storage_name/blocked"
delete_json=$(curl -fsS -X DELETE -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"confirmation":"DELETE","password":"AccountDeletePass123!"}' "$BASE/v1/me")
echo "$delete_json" | jq -e '.deleted == true and .queuedMediaFiles == 1 and .accountDataRemoved == true' >/dev/null
echo '[account-lifecycle-test] account deletion and queued-media response passed'
revoked_status=$(curl -sS -o /tmp/hotice-revoked-session-response.json -w '%{http_code}' -H "$AUTH" "$BASE/v1/me")
foreign_status=$(curl -sS -o /tmp/hotice-foreign-project-response.json -w '%{http_code}' -H "Authorization: Bearer $other_token" "$BASE/v1/projects/$project")
echo "[account-lifecycle-test] revoked session HTTP $revoked_status; foreign project HTTP $foreign_status"
test "$revoked_status" = '401'
test "$foreign_status" = '404'
echo '[account-lifecycle-test] token revocation and ownership isolation passed'
php -r '
require_once "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); $user=$argv[1];
foreach (["sessions","cloud_projects","cloud_files","generation_jobs","job_quotes","credit_ledger","credit_accounts","cloud_entitlements"] as $table) {
  $q=$db->prepare("SELECT COUNT(*) FROM $table WHERE user_id=?"); $q->execute([$user]); $count=(int)$q->fetchColumn(); if ($count!==0) { fwrite(STDERR,"Residual rows in $table: $count\\n"); exit(1); }
}
$q=$db->prepare("SELECT COUNT(*) FROM users WHERE id=?"); $q->execute([$user]); if ((int)$q->fetchColumn()!==0) { fwrite(STDERR,"User row remains\\n"); exit(1); }
$q=$db->prepare("SELECT COUNT(*) FROM email_outbox WHERE recipient=?"); $q->execute([$argv[2]]); if ((int)$q->fetchColumn()!==0) { fwrite(STDERR,"Email outbox row remains\\n"); exit(1); }
' "$user_id" "$EMAIL"
echo '[account-lifecycle-test] relational and outbox rows removed'
php backend/bin/purge-private-media.php 10 | jq -e '.retryableFailures == 1 and .purged == 0' >/dev/null
echo '[account-lifecycle-test] failed purge retained safely for retry'
rm -r "$storage_path/$storage_name"
php backend/bin/purge-private-media.php 10 | jq -e '.purged == 1 and .retryableFailures == 0' >/dev/null
echo '[account-lifecycle-test] purge retry succeeded'
test "$(php -r 'require_once "backend/src/App.php"; $c=require "backend/config.php"; $db=(new Hotice\App($c))->database(); echo $db->query("SELECT COUNT(*) FROM private_media_deletion_queue")->fetchColumn();')" = '0'
echo '[account-lifecycle-test] export isolation, deletion safeguards, relational cleanup, revoked tokens, and retryable private-media purge passed'
