<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
try {
    $config = require dirname(__DIR__) . '/config.php';
    $db = (new \Hotice\App($config))->database();
    $limit = isset($argv[1]) ? (int)$argv[1] : 20;
    $result = \Hotice\EmailOutbox::process($db, $config, $limit);
    echo "Email outbox: {$result['status']}; sent={$result['sent']}; retried={$result['retried']}; failed={$result['failed']}\n";
} catch (\Throwable $e) {
    fwrite(STDERR, 'Email outbox worker failed: ' . get_class($e) . "\n"); exit(1);
}

