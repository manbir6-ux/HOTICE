<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
$path = dirname(__DIR__) . '/config.php';
if (!is_file($path)) { fwrite(STDERR, "Copy config.example.php to config.php and edit it first.\n"); exit(1); }
$config = require $path;
try {
    $app = new \Hotice\App($config);
    // Validate paths BEFORE applying any database migrations. cPanel domains
    // may have an unrelated public_html root above backend/public.
    $folder = trim((string) ($config['storage_path'] ?? ''));
    if ($folder === '') throw new \RuntimeException('Private media directory not configured.');
    if (!is_dir($folder) && !mkdir($folder, 0700, true) && !is_dir($folder)) {
        throw new \RuntimeException('Private media directory cannot be created.');
    }
    $publicWebroot = trim((string) ($config['public_webroot_path'] ?? ''));
    $roots = [dirname(__DIR__) . '/public'];
    if ($publicWebroot !== '') $roots[] = $publicWebroot;
    \Hotice\Support::assertPrivateStorage($folder, $roots);
    chmod($folder, 0700);
    $schema = file_get_contents(dirname(__DIR__) . '/schema.sql');
    if ($schema === false) throw new \RuntimeException('Schema file missing.');
    foreach (explode(';', $schema) as $sql) {
        if (trim($sql) !== '') $app->database()->exec($sql);
    }
    // Additive migration for databases installed before email verification.
    $columns = $app->database()->query('SHOW COLUMNS FROM users')->fetchAll(PDO::FETCH_COLUMN);
    if (!in_array('email_verified_at', $columns, true)) {
        $app->database()->exec('ALTER TABLE users ADD COLUMN email_verified_at DATETIME NULL AFTER password_hash');
    }
    echo "HOTICE tables installed; private media directory verified.\n";
} catch (\Throwable $e) {
    fwrite(STDERR, 'Installation failed; check PHP extensions, database permissions and file paths. ' . get_class($e) . "\n");
    exit(1);
}

