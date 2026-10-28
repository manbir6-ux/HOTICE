<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
if ($argc !== 2) { fwrite(STDERR, "Usage: php bin/create-user.php email@example.com\nPassword is read privately from stdin.\n"); exit(1); }
try {
    $config = require dirname(__DIR__) . '/config.php';
    $email = \Hotice\Support::email($argv[1]);
    fwrite(STDERR, 'Password (at least 12 bytes): ');
    // Do not pass passwords on the command line (shell history/process list).
    if (function_exists('shell_exec')) @shell_exec('stty -echo 2>/dev/null');
    $password = trim((string) fgets(STDIN), "\r\n");
    if (function_exists('shell_exec')) @shell_exec('stty echo 2>/dev/null');
    fwrite(STDERR, "\n");
    if (strlen($password) < 12 || strlen($password) > 256) throw new \RuntimeException('Password length must be 12-256 bytes.');
    $db = (new \Hotice\App($config))->database();
    $db->prepare('INSERT INTO users(id,email,password_hash) VALUES(?,?,?)')
        ->execute([\Hotice\Support::uuid(), $email, password_hash($password, PASSWORD_DEFAULT)]);
    echo "User created (no paid cloud entitlement assigned).\n";
} catch (\Throwable $e) {
    fwrite(STDERR, 'User creation failed: ' . get_class($e) . "\n"); exit(1);
}
