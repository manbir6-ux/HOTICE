<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/Support.php';
try {
    $config = require dirname(__DIR__) . '/config.php';
    $dsn = (string)$config['db']['dsn'];
    $db = new PDO($dsn, (string)$config['db']['user'], (string)$config['db']['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    $roots = [dirname(__DIR__) . '/public'];
    foreach (['public_webroot_path'] as $key) if (!empty($config[$key])) $roots[] = (string)$config[$key];
    $storage = \Hotice\Support::assertPrivateStorage((string)($config['storage_path'] ?? ''), $roots);
    $limit = max(1, min(500, (int)($argv[1] ?? 100)));
    $done = 0;
    $failed = 0;
    for ($i = 0; $i < $limit; $i++) {
        $db->beginTransaction();
        $row = $db->query("SELECT storage_name FROM private_media_deletion_queue WHERE locked_at IS NULL OR locked_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 10 MINUTE) ORDER BY created_at LIMIT 1 FOR UPDATE")->fetch();
        if (!$row) { $db->commit(); break; }
        $name = (string)$row['storage_name'];
        if (!\Hotice\Support::secureFileName($name)) {
            $db->prepare("UPDATE private_media_deletion_queue SET attempts=attempts+1,locked_at=UTC_TIMESTAMP(),last_error_code='invalid_storage_name' WHERE storage_name=?")->execute([$name]);
            $db->commit(); $failed++; continue;
        }
        $db->prepare('UPDATE private_media_deletion_queue SET locked_at=UTC_TIMESTAMP() WHERE storage_name=?')->execute([$name]);
        $db->commit();
        $path = $storage . '/' . $name;
        $removed = !file_exists($path) && !is_link($path);
        if (!$removed && (is_file($path) || is_link($path))) $removed = @unlink($path);
        if ($removed) {
            $db->prepare('DELETE FROM private_media_deletion_queue WHERE storage_name=?')->execute([$name]);
            $done++;
        } else {
            $db->prepare("UPDATE private_media_deletion_queue SET attempts=attempts+1,locked_at=UTC_TIMESTAMP(),last_error_code='unlink_failed' WHERE storage_name=?")->execute([$name]);
            $failed++;
        }
    }
    echo json_encode(['purged' => $done, 'retryableFailures' => $failed], JSON_THROW_ON_ERROR) . PHP_EOL;
} catch (Throwable $e) {
    fwrite(STDERR, 'Private media purge failed: ' . get_class($e) . PHP_EOL); exit(1);
}
