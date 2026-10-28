<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/src/App.php';
try {
    $path = dirname(__DIR__) . '/config.php';
    if (!is_file($path)) throw new \RuntimeException('Missing backend configuration.');
    $config = require $path;
    if (!is_array($config)) throw new \RuntimeException('Invalid backend configuration.');
    (new \Hotice\App($config))->run();
} catch (\Throwable $e) {
    // Do not leak DSNs, filesystem paths, raw SQL, provider tokens or stack traces.
    error_log('HOTICE API startup failed: ' . get_class($e));
    http_response_code(503);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo '{"error":"Backend is not configured or unavailable."}';
}
