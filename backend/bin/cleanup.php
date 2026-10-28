<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
try {
    $config = require dirname(__DIR__) . '/config.php';
    $db = (new \Hotice\App($config))->database();
    $db->exec('DELETE FROM sessions WHERE expires_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY) OR revoked_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY)');
    $db->exec('DELETE FROM login_attempts WHERE occurred_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 DAY)');
    $db->exec('DELETE FROM password_reset_tokens WHERE expires_at < UTC_TIMESTAMP() OR used_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY)');
    $db->exec('DELETE FROM email_verification_tokens WHERE expires_at < UTC_TIMESTAMP() OR used_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY)');
    $db->exec('DELETE FROM email_outbox WHERE expires_at < UTC_TIMESTAMP() OR sent_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY) OR failed_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY)');
    echo "Expired session/attempt records cleaned. User media unchanged.\n";
} catch (\Throwable $e) {
    fwrite(STDERR, 'Cleanup failed: ' . get_class($e) . "\n"); exit(1);
}

