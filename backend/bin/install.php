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
    echo "HOTICE tables installed; private media directory verified.\n";
} catch (\Throwable $e) {
    $detail = '';
    if ($e instanceof \PDOException) {
        $info = is_array($e->errorInfo ?? null) ? $e->errorInfo : [];
        $state = (string) ($info[0] ?? $e->getCode());
        $driverCode = $info[1] ?? null;
        if (preg_match('/^[A-Z0-9]{5}$/iD', $state)) $detail .= ' SQLSTATE ' . $state;
        if (is_int($driverCode) || (is_string($driverCode) && ctype_digit($driverCode))) {
            $detail .= ' driver code ' . $driverCode;
        }
    }
    fwrite(STDERR, 'Installation failed; check PHP extensions, database permissions and file paths. ' . get_class($e) . $detail . "\n");
    exit(1);
}
