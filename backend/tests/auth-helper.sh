register_and_verify() {
  local email="$1" password="$2" response token
  response=$(curl -sS -w '\n%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}" "$BASE/v1/auth/register")
  test "${response##*$'\n'}" = '202'
  echo "${response%$'\n'*}" | jq -e '.registered == true and .verificationRequired == true' >/dev/null
  php backend/bin/send-email-outbox.php 10 >/dev/null
  local unverified_status
  unverified_status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}" "$BASE/v1/auth/login")
  test "$unverified_status" = '403'
  token=$(php -r '
    $file = getenv("HOTICE_TEST_MAIL_CAPTURE"); $email = $argv[1];
    if (!$file || !is_file($file)) exit(2);
    foreach (array_reverse(file($file, FILE_IGNORE_NEW_LINES)) as $line) {
      $message = json_decode($line, true);
      if (($message["to"] ?? "") === $email && preg_match("/#token=([a-f0-9]{64})/", $message["body"] ?? "", $m)) { echo $m[1]; exit; }
    }
    exit(3);
  ' "$email")
  local stale_token="$token"
  curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$email\"}" \
    "$BASE/v1/auth/verification/resend" | jq -e '.accepted == true' >/dev/null
  php backend/bin/send-email-outbox.php 10 >/dev/null
  token=$(php -r '
    $file = getenv("HOTICE_TEST_MAIL_CAPTURE"); $email = $argv[1];
    foreach (array_reverse(file($file, FILE_IGNORE_NEW_LINES)) as $line) {
      $message = json_decode($line, true);
      if (($message["to"] ?? "") === $email && preg_match("/#token=([a-f0-9]{64})/", $message["body"] ?? "", $m)) { echo $m[1]; exit; }
    }
    exit(3);
  ' "$email")
  local stale_status
  stale_status=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"token\":\"$stale_token\"}" "$BASE/v1/auth/verify-email")
  test "$stale_status" = '400'
  curl -fsS -H 'Content-Type: application/json' -d "{\"token\":\"$token\"}" \
    "$BASE/v1/auth/verify-email" | jq -e '.verified == true' >/dev/null
  local replay
  replay=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"token\":\"$token\"}" "$BASE/v1/auth/verify-email")
  test "$replay" = '400'
}

reset_password() {
  local email="$1" password="$2" response token replay mail_count
  response=$(curl -sS -w '\n%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\"}" "$BASE/v1/auth/password-reset/request")
  test "${response##*$'\n'}" = '202'
  echo "${response%$'\n'*}" | jq -e '.accepted == true' >/dev/null
  php backend/bin/send-email-outbox.php 10 >/dev/null
  token=$(php -r '
    $file = getenv("HOTICE_TEST_MAIL_CAPTURE"); $email = $argv[1];
    foreach (array_reverse(file($file, FILE_IGNORE_NEW_LINES)) as $line) {
      $message = json_decode($line, true);
      if (($message["to"] ?? "") === $email && preg_match("/#reset=([a-f0-9]{64})/", $message["body"] ?? "", $m)) { echo $m[1]; exit; }
    }
    exit(3);
  ' "$email")
  mail_count=$(wc -l < "$HOTICE_TEST_MAIL_CAPTURE")
  curl -fsS -H 'Content-Type: application/json' -d "{\"email\":\"$email\"}" \
    "$BASE/v1/auth/password-reset/request" | jq -e '.accepted == true' >/dev/null
  test "$(wc -l < "$HOTICE_TEST_MAIL_CAPTURE")" = "$mail_count"
  replay=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"token\":\"$token\",\"password\":\"short\"}" "$BASE/v1/auth/password-reset/complete")
  test "$replay" = '422'
  curl -fsS -H 'Content-Type: application/json' -d "{\"token\":\"$token\",\"password\":\"$password\"}" \
    "$BASE/v1/auth/password-reset/complete" | jq -e '.passwordReset == true and .sessionsRevoked == true' >/dev/null
  replay=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"token\":\"$token\",\"password\":\"$password\"}" "$BASE/v1/auth/password-reset/complete")
  test "$replay" = '400'
}

