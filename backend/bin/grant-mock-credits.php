<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
try {
    if ($argc !== 4) throw new RuntimeException('Usage: php bin/grant-mock-credits.php user@example.com amount idempotency-key');
    $config = require dirname(__DIR__) . '/config.php';
    if (($config['mock_jobs_enabled'] ?? false) !== true) throw new RuntimeException('Mock credits are disabled on this server.');
    $email = \Hotice\Support::email($argv[1]);
    if (!preg_match('/^[1-9][0-9]{0,6}$/D', $argv[2])) throw new RuntimeException('Amount must be between 1 and 1000000.');
    $amount = (int)$argv[2];
    if (!preg_match('/^[A-Za-z0-9._~:-]{16,128}$/D', $argv[3])) throw new RuntimeException('Idempotency key must be 16-128 safe characters.');
    $db = (new \Hotice\App($config))->database();
    $userQuery = $db->prepare('SELECT id FROM users WHERE email=? LIMIT 1');
    $userQuery->execute([$email]);
    $user = $userQuery->fetchColumn();
    if (!is_string($user)) throw new RuntimeException('User not found.');
    $event = hash('sha256', 'mock-credit-grant:' . $email . ':' . $argv[3]);
    $db->beginTransaction();
    $db->prepare('INSERT INTO credit_accounts(user_id,balance) VALUES(?,0) ON DUPLICATE KEY UPDATE user_id=VALUES(user_id)')
        ->execute([$user]);
    $account = $db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
    $account->execute([$user]);
    $balance = (int)$account->fetchColumn();
    $prior = $db->prepare('SELECT user_id,delta FROM credit_ledger WHERE event_key=? LIMIT 1');
    $prior->execute([$event]);
    $old = $prior->fetch();
    if ($old) {
        $db->commit();
        if ($old['user_id'] !== $user || (int)$old['delta'] !== $amount) throw new RuntimeException('Idempotency key conflicts with another credit grant.');
        echo "Mock credit grant already applied; no duplicate credits added.\n"; exit;
    }
    if ($balance > PHP_INT_MAX - $amount) throw new RuntimeException('Credit balance limit reached.');
    $next = $balance + $amount;
    $db->prepare('UPDATE credit_accounts SET balance=? WHERE user_id=?')->execute([$next, $user]);
    $db->prepare("INSERT INTO credit_ledger(user_id,event_key,event_type,delta,balance_after) VALUES(?,?,'grant',?,?)")
        ->execute([$user, $event, $amount, $next]);
    $db->commit();
    echo "Granted simulated test credits only; no payment or cash value was created.\n";
} catch (Throwable $e) {
    if (isset($db) && $db instanceof PDO && $db->inTransaction()) $db->rollBack();
    fwrite(STDERR, 'Mock credit grant failed: ' . get_class($e) . "\n"); exit(1);
}
