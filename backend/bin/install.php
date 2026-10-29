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
    $statementNumber = 0;
    foreach (explode(';', $schema) as $sql) {
        if (trim($sql) === '') continue;
        $statementNumber++;
        try {
            $app->database()->exec($sql);
        } catch (\PDOException $e) {
            throw new \RuntimeException('Schema statement #' . $statementNumber . ' failed.', 0, $e);
        }
    }
    // Additive migration for databases installed before email verification.
    $columns = $app->database()->query('SHOW COLUMNS FROM users')->fetchAll(PDO::FETCH_COLUMN);
    if (!in_array('email_verified_at', $columns, true)) {
        $app->database()->exec('ALTER TABLE users ADD COLUMN email_verified_at DATETIME NULL AFTER password_hash');
    }
    // Existing uploads must be rescanned before they can be downloaded.
    $fileColumns = $app->database()->query('SHOW COLUMNS FROM cloud_files')->fetchAll(PDO::FETCH_COLUMN);
    if (!in_array('scan_status', $fileColumns, true)) {
        $app->database()->exec("ALTER TABLE cloud_files ADD COLUMN scan_status ENUM('pending','clean','blocked') NOT NULL DEFAULT 'pending' AFTER sha256");
    }
    echo "HOTICE tables installed; private media directory verified.\n";
} catch (\Throwable $e) {
    $detail = '';
    $cause = $e;
    while ($cause->getPrevious() !== null) $cause = $cause->getPrevious();
    if ($cause instanceof \PDOException) {
        $info = is_array($cause->errorInfo ?? null) ? $cause->errorInfo : [];
        $state = (string) ($info[0] ?? $cause->getCode());
        $driverCode = $info[1] ?? null;
        if (preg_match('/^[A-Z0-9]{5}$/iD', $state)) $detail .= ' SQLSTATE ' . $state;
        if (is_int($driverCode) || (is_string($driverCode) && ctype_digit($driverCode))) {
            $detail .= ' driver code ' . $driverCode;
        }
    }
    $statement = $e->getPrevious() instanceof \PDOException && preg_match('/^Schema statement #[0-9]+ failed\.$/D', $e->getMessage())
        ? ' ' . $e->getMessage()
        : '';
    fwrite(STDERR, 'Installation failed; check PHP extensions, database permissions and file paths. ' . get_class($cause) . $statement . $detail . "\n");
    exit(1);
}


