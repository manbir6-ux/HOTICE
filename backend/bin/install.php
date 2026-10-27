<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
$path = dirname(__DIR__) . '/config.php';
if (!is_file($path)) { fwrite(STDERR, "Copy config.example.php to config.php and edit it first.\n"); exit(1); }
$config = require $path;
try {
    $app = new \Hotice\App($config);
    $schema = file_get_contents(dirname(__DIR__) . '/schema.sql');
    if ($schema === false) throw new \RuntimeException('Schema file missing.');
    foreach (explode(';', $schema) as $sql) {
        if (trim($sql) !== '') $app->database()->exec($sql);
    }
    $folder = (string) ($config['storage_path'] ?? '');
    if ($folder === '' || str_starts_with($folder, dirname(__DIR__) . '/public')) throw new \RuntimeException('Media storage cannot be publicly accessible.');
    if (!is_dir($folder) && !mkdir($folder, 0700, true) && !is_dir($folder)) {
        throw new \RuntimeException('Private media directory cannot be created.');
    }
    chmod($folder, 0700);
    echo "HOTICE tables installed; private media directory prepared.\n";
} catch (\Throwable $e) {
    fwrite(STDERR, 'Installation failed; check PHP extensions, database permissions and file paths. ' . get_class($e) . "\n");
    exit(1);
}
