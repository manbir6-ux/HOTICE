<?php
declare(strict_types=1);
require_once dirname(__DIR__) . '/src/App.php';
$config = require dirname(__DIR__) . '/config.php';
$db = (new \Hotice\App($config))->database();
$checks = 0;
$assert = static function (bool $ok, string $message) use (&$checks): void {
    $checks++;
    if (!$ok) throw new RuntimeException('Email outbox integration failed: ' . $message);
};
$expires = gmdate('Y-m-d H:i:s', time() + 1800);
$canary = 'HOTICE_OUTBOX_SECRET_CANARY_9d7c';

// Failed delivery retries with bounded backoff, then reaches a sanitized terminal state.
\Hotice\EmailOutbox::enqueue($db, $config, 'outbox-retry@example.test', 'Retry test', $canary, $expires);
$q = $db->prepare('SELECT id,ciphertext FROM email_outbox WHERE recipient=? ORDER BY created_at DESC LIMIT 1');
$q->execute(['outbox-retry@example.test']);
$retryRow = $q->fetch();
$assert($retryRow && !str_contains((string)$retryRow['ciphertext'], $canary), 'email body is encrypted at rest');
for ($attempt = 1; $attempt <= 8; $attempt++) {
    if ($attempt > 1) $db->prepare('UPDATE email_outbox SET available_at=UTC_TIMESTAMP() WHERE id=?')->execute([$retryRow['id']]);
    $result = \Hotice\EmailOutbox::process($db, $config, 1);
    if ($attempt < 8) $assert($result['retried'] === 1, 'failed send is scheduled for retry');
    else $assert($result['failed'] === 1, 'retry limit reaches terminal failure');
}
$q = $db->prepare('SELECT attempts,failed_at,last_error_code FROM email_outbox WHERE id=?');
$q->execute([$retryRow['id']]);
$failed = $q->fetch();
$assert((int)$failed['attempts'] === 8 && $failed['failed_at'] !== null && $failed['last_error_code'] === 'delivery_exhausted', 'retry ceiling is recorded without raw transport details');

// Tampered authenticated ciphertext fails closed without attempting delivery.
\Hotice\EmailOutbox::enqueue($db, $config, 'tamper@example.test', 'Tamper test', $canary, $expires);
$q = $db->prepare('SELECT id FROM email_outbox WHERE recipient=? ORDER BY created_at DESC LIMIT 1');
$q->execute(['tamper@example.test']);
$tamperId = (string)$q->fetchColumn();
$db->prepare('UPDATE email_outbox SET tag=? WHERE id=?')->execute([random_bytes(16), $tamperId]);
$result = \Hotice\EmailOutbox::process($db, $config, 1);
$assert($result['failed'] === 1, 'tampered payload rejected');
$q = $db->prepare('SELECT failed_at,last_error_code FROM email_outbox WHERE id=?');
$q->execute([$tamperId]);
$tampered = $q->fetch();
$assert($tampered['failed_at'] !== null && $tampered['last_error_code'] === 'payload_invalid', 'tampered payload has safe error state');

// Expired messages are never delivered and their encrypted body is erased.
\Hotice\EmailOutbox::enqueue($db, $config, 'expired@example.test', 'Expired test', $canary,
    gmdate('Y-m-d H:i:s', time() - 60));
$q = $db->prepare('SELECT id FROM email_outbox WHERE recipient=? ORDER BY created_at DESC LIMIT 1');
$q->execute(['expired@example.test']);
$expiredId = (string)$q->fetchColumn();
$result = \Hotice\EmailOutbox::process($db, $config, 1);
$assert($result['failed'] === 1, 'expired message is discarded');
$q = $db->prepare('SELECT failed_at,last_error_code,ciphertext FROM email_outbox WHERE id=?');
$q->execute([$expiredId]);
$expired = $q->fetch();
$assert($expired['failed_at'] !== null && $expired['last_error_code'] === 'expired' && $expired['ciphertext'] === null,
    'expired body is erased without delivery');

// Success delivers through the injected CI transport and erases ciphertext.
\Hotice\EmailOutbox::enqueue($db, $config, 'outbox-success@example.test', 'Success test', $canary, $expires);
$q = $db->prepare('SELECT id FROM email_outbox WHERE recipient=? ORDER BY created_at DESC LIMIT 1');
$q->execute(['outbox-success@example.test']);
$successId = (string)$q->fetchColumn();
$result = \Hotice\EmailOutbox::process($db, $config, 1);
$assert($result['sent'] === 1, 'valid message delivered');
$q = $db->prepare('SELECT sent_at,ciphertext,nonce,tag FROM email_outbox WHERE id=?');
$q->execute([$successId]);
$sent = $q->fetch();
$assert($sent['sent_at'] !== null && $sent['ciphertext'] === null && $sent['nonce'] === null && $sent['tag'] === null, 'sent ciphertext is erased');

echo "Encrypted email outbox integration: $checks assertions passed.\n";

