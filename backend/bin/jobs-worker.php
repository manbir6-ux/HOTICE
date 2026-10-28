<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
require_once dirname(__DIR__) . '/src/MockJobWorker.php';
try {
    if ($argc > 1 && $argv[1] !== '--once') throw new RuntimeException('Usage: php bin/jobs-worker.php [--once]');
    $config = require dirname(__DIR__) . '/config.php';
    $db = (new \Hotice\App($config))->database();
    echo json_encode(\Hotice\MockJobWorker::runOne($db, $config), JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n";
} catch (Throwable $e) {
    fwrite(STDERR, 'Mock worker failed: ' . get_class($e) . "\n"); exit(1);
}
