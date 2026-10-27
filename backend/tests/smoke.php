<?php
declare(strict_types=1);
require_once dirname(__DIR__) . '/src/Support.php';
use Hotice\ApiError;
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
check(Support::email(' A@EXAMPLE.COM ') === 'a@example.com', 'normalize email');
try { Support::email('not-an-email'); check(false, 'invalid email rejected'); } catch (ApiError $e) { check($e->status === 422, 'invalid email'); }
check(Support::secureFileName(str_repeat('a', 64)), 'valid storage name');
check(!Support::secureFileName('../secret'), 'reject traversal');
check(Support::jsonString(['a' => 'b'], 50) === '{"a":"b"}', 'JSON serialization');
try { Support::jsonString(['a' => str_repeat('X', 50)], 10); check(false, 'reject oversized document'); } catch (ApiError $e) { check($e->status === 413, 'oversized JSON'); }
echo "HOTICE backend core: $assertions assertions passed.\n";
