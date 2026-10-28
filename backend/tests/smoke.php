<?php
declare(strict_types=1);
require_once dirname(__DIR__) . '/src/Support.php';
require_once dirname(__DIR__) . '/src/AdminSecurity.php';
use Hotice\ApiError;
use Hotice\AdminSecurity;
use Hotice\Support;
$assertions = 0;
function check(bool $ok, string $label): void {
    global $assertions;
    $assertions++;
    if (!$ok) { fwrite(STDERR, "FAIL: $label\n"); exit(1); }
}
for ($i = 0; $i < 100; $i++) {
    $uuid = Support::uuid();
    check(Support::isUuid($uuid), 'uuid4 generation');
    check(!Support::isUuid(str_replace('-', '', $uuid)), 'no malformed uuid');
}
check(AdminSecurity::base32Encode('12345678901234567890') === 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', 'TOTP base32 encoding');
check(AdminSecurity::totp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', 59) === '287082', 'RFC 6238 TOTP vector');
check(AdminSecurity::verifyTotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', '287082', 59), 'valid TOTP accepted');
check(!AdminSecurity::verifyTotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', '000000', 59), 'invalid TOTP rejected');
$appKey = str_repeat('ab', 32);
$sealed = AdminSecurity::encryptProviderKey('openai', 'secret-example', $appKey);
check(AdminSecurity::decryptProviderKey('openai', $sealed['ciphertext'], $sealed['nonce'], $sealed['tag'], $appKey) === 'secret-example', 'provider secret encryption roundtrip');
try { AdminSecurity::decryptProviderKey('google', $sealed['ciphertext'], $sealed['nonce'], $sealed['tag'], $appKey); check(false, 'provider keys bound to provider'); } catch (RuntimeException) { check(true, 'provider keys bound to provider'); }
check(Support::email(' A@EXAMPLE.COM ') === 'a@example.com', 'normalize email');
try { Support::email('not-an-email'); check(false, 'invalid email rejected'); } catch (ApiError $e) { check($e->status === 422, 'invalid email'); }
$longPassword = str_repeat('a', 72) . 'first-suffix';
$differentLongPassword = str_repeat('a', 72) . 'other-suffix';
$longPasswordHash = Support::passwordHash($longPassword);
check(Support::passwordVerify($longPassword, $longPasswordHash), 'prehashed long password verifies');
check(!Support::passwordVerify($differentLongPassword, $longPasswordHash), 'long password suffix is covered by hash');
check(!Support::passwordNeedsRehash($longPasswordHash), 'current password hash marker recognized');
$nulPassword = "PasswordWith\0BinaryByte123!";
check(Support::passwordVerify($nulPassword, Support::passwordHash($nulPassword)), 'modern password hash preserves NUL bytes');
$legacyPassword = 'LegacyPassword123!';
$legacyPasswordHash = password_hash($legacyPassword, PASSWORD_DEFAULT);
check(Support::passwordVerify($legacyPassword, $legacyPasswordHash), 'legacy password hash remains verifiable');
check(Support::passwordNeedsRehash($legacyPasswordHash), 'legacy password hash requests upgrade');
check(Support::secureFileName(str_repeat('a', 64)), 'valid storage name');
check(!Support::secureFileName('../secret'), 'reject traversal');
check(Support::jsonString(['a' => 'b'], 50) === '{"a":"b"}', 'JSON serialization');
try { Support::jsonString(['a' => str_repeat('X', 50)], 10); check(false, 'reject oversized document'); } catch (ApiError $e) { check($e->status === 413, 'oversized JSON'); }
// Validate that storage cannot be public (including ancestor and symlink
// cases) even if an operator configures a cPanel document root incorrectly.
$tmpBase = sys_get_temp_dir() . '/hotice-safe-' . bin2hex(random_bytes(8));
mkdir($tmpBase . '/public/uploads', 0700, true);
mkdir($tmpBase . '/private', 0700, true);
try {
    check(Support::assertPrivateStorage($tmpBase . '/private', [$tmpBase . '/public'])
        === realpath($tmpBase . '/private'), 'separate private storage accepted');
    foreach ([$tmpBase . '/public', $tmpBase, $tmpBase . '/public/uploads'] as $unsafe) {
        try {
            Support::assertPrivateStorage($unsafe, [$tmpBase . '/public']);
            check(false, 'webroot path rejected');
        } catch (\RuntimeException $e) {
            check(true, 'webroot path rejected');
        }
    }
    if (function_exists('symlink') && @symlink($tmpBase . '/public/uploads', $tmpBase . '/alias')) {
        try {
            Support::assertPrivateStorage($tmpBase . '/alias', [$tmpBase . '/public']);
            check(false, 'symlink bypass rejected');
        } catch (\RuntimeException $e) {
            check(true, 'symlink bypass rejected');
        }
        unlink($tmpBase . '/alias');
    }
    try {
        Support::assertPrivateStorage($tmpBase . '/private', [$tmpBase . '/nonexistent']);
        check(false, 'nonexistent public root rejected');
    } catch (\RuntimeException $e) {
        check(true, 'nonexistent public root rejected');
    }
} finally {
    rmdir($tmpBase . '/public/uploads');
    rmdir($tmpBase . '/public');
    rmdir($tmpBase . '/private');
    rmdir($tmpBase);
}
echo "HOTICE backend core: $assertions assertions passed.\n";
