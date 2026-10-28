<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
require_once dirname(__DIR__) . '/src/AdminSecurity.php';

if ($argc !== 2) {
    fwrite(STDERR, "Usage: php bin/create-owner.php owner@example.com\nThis creates an owner with mandatory authenticator MFA.\n");
    exit(1);
}
try {
    $config = require dirname(__DIR__) . '/config.php';
    $email = \Hotice\Support::email($argv[1]);
    fwrite(STDERR, 'Owner password (12-256 bytes): ');
    if (function_exists('shell_exec')) @shell_exec('stty -echo');
    $password = trim((string) fgets(STDIN), "\r\n");
    if (function_exists('shell_exec')) @shell_exec('stty echo');
    fwrite(STDERR, "\n");
    if (strlen($password) < 12 || strlen($password) > 256) throw new RuntimeException('Password length must be 12-256 bytes.');
    $secret = \Hotice\AdminSecurity::base32Encode(random_bytes(20));
    $sealed = \Hotice\AdminSecurity::encryptTotpSecret($secret, (string)$config['app_key']);
    $db = (new \Hotice\App($config))->database();
    $db->prepare('INSERT INTO admin_accounts(id,email,password_hash,totp_secret_ciphertext,totp_nonce,totp_tag) VALUES(?,?,?,?,?,?)')
        ->execute([\Hotice\Support::uuid(), $email, password_hash($password, PASSWORD_DEFAULT),
            $sealed['ciphertext'], $sealed['nonce'], $sealed['tag']]);
    $label = rawurlencode('HOTICE:' . $email);
    $uri = 'otpauth://totp/' . $label . '?secret=' . $secret . '&issuer=HOTICE&algorithm=SHA1&digits=6&period=30';
    echo "Owner created. Add this TOTP URI to an authenticator now; it is not stored in plaintext:\n" . $uri . "\n\nSecret: " . $secret . "\nStore the secret securely.\n";
} catch (Throwable $e) {
    fwrite(STDERR, 'Owner creation failed: ' . get_class($e) . "\n");
    exit(1);
}
