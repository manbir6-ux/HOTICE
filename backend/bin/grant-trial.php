<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
if ($argc !== 4) {
    fwrite(STDERR, "Usage: php bin/grant-trial.php email@example.com quota_MiB days\nOnly ADMIN TRIALS; NEVER use this to pretend a payment was verified.\n");
    exit(1);
}
try {
    $config = require dirname(__DIR__) . '/config.php';
    $email = \Hotice\Support::email($argv[1]);
    $mib = filter_var($argv[2], FILTER_VALIDATE_INT);
    $days = filter_var($argv[3], FILTER_VALIDATE_INT);
    if (!$mib || $mib < 1 || $mib > 1024 || !$days || $days < 1 || $days > 60) {
        throw new \RuntimeException('Trial limit: 1-1024 MiB, 1-60 days.');
    }
    $db = (new \Hotice\App($config))->database();
    $q = $db->prepare('SELECT id FROM users WHERE email=?');
    $q->execute([$email]);
    $id = $q->fetchColumn();
    if (!$id) throw new \RuntimeException('User not found.');
    $expires = gmdate('Y-m-d H:i:s', time() + $days * 86400);
    $db->prepare("INSERT INTO cloud_entitlements (user_id,source,plan_code,quota_bytes,expires_at) VALUES (?,'admin_trial','trial',?,?) ON DUPLICATE KEY UPDATE source='admin_trial',plan_code='trial',quota_bytes=VALUES(quota_bytes),expires_at=VALUES(expires_at)")
        ->execute([$id, $mib * 1048576, $expires]);
    echo "Admin cloud trial enabled. Not a payment or credit grant.\n";
} catch (\Throwable $e) {
    fwrite(STDERR, 'Trial grant failed: ' . get_class($e) . "\n"); exit(1);
}
