<?php
declare(strict_types=1);

namespace Hotice;

/** Cryptographic helpers for the isolated owner panel. */
final class AdminSecurity
{
    private const AAD_TOTP = 'hotice-owner-totp-v1';
    private const AAD_PROVIDER_PREFIX = 'hotice-provider-key-v1:';

    private static function key(string $appKey): string
    {
        if (!preg_match('/^[a-f0-9]{64}$/iD', $appKey)) {
            throw new \RuntimeException('Invalid application key.');
        }
        return hash_hmac('sha256', 'hotice-admin-secret-encryption-v1', hex2bin($appKey), true);
    }

    /** @return array{ciphertext:string,nonce:string,tag:string} */
    public static function encrypt(string $plain, string $appKey, string $aad): array
    {
        $nonce = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt($plain, 'aes-256-gcm', self::key($appKey), OPENSSL_RAW_DATA,
            $nonce, $tag, $aad, 16);
        if ($ciphertext === false || strlen($tag) !== 16) throw new \RuntimeException('Encryption unavailable.');
        return compact('ciphertext', 'nonce', 'tag');
    }

    public static function decrypt(string $ciphertext, string $nonce, string $tag,
        string $appKey, string $aad): string
    {
        if (strlen($nonce) !== 12 || strlen($tag) !== 16) throw new \RuntimeException('Encrypted value invalid.');
        $plain = openssl_decrypt($ciphertext, 'aes-256-gcm', self::key($appKey), OPENSSL_RAW_DATA,
            $nonce, $tag, $aad);
        if ($plain === false) throw new \RuntimeException('Encrypted value authentication failed.');
        return $plain;
    }

    public static function encryptTotpSecret(string $secret, string $appKey): array
    {
        return self::encrypt($secret, $appKey, self::AAD_TOTP);
    }

    public static function decryptTotpSecret(string $ciphertext, string $nonce, string $tag,
        string $appKey): string
    {
        return self::decrypt($ciphertext, $nonce, $tag, $appKey, self::AAD_TOTP);
    }

    public static function encryptProviderKey(string $provider, string $secret, string $appKey): array
    {
        return self::encrypt($secret, $appKey, self::AAD_PROVIDER_PREFIX . $provider);
    }

    public static function decryptProviderKey(string $provider, string $ciphertext, string $nonce,
        string $tag, string $appKey): string
    {
        return self::decrypt($ciphertext, $nonce, $tag, $appKey, self::AAD_PROVIDER_PREFIX . $provider);
    }

    public static function base32Encode(string $bytes): string
    {
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        $buffer = 0; $bits = 0; $out = '';
        for ($i = 0, $n = strlen($bytes); $i < $n; $i++) {
            $buffer = ($buffer << 8) | ord($bytes[$i]); $bits += 8;
            while ($bits >= 5) {
                $bits -= 5;
                $out .= $alphabet[($buffer >> $bits) & 31];
            }
        }
        if ($bits > 0) $out .= $alphabet[($buffer << (5 - $bits)) & 31];
        return $out;
    }

    private static function base32Decode(string $value): string
    {
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        $value = strtoupper(rtrim($value, '='));
        if ($value === '' || preg_match('/[^A-Z2-7]/', $value)) throw new \RuntimeException('Invalid TOTP secret.');
        $buffer = 0; $bits = 0; $out = '';
        foreach (str_split($value) as $char) {
            $buffer = ($buffer << 5) | strpos($alphabet, $char); $bits += 5;
            if ($bits >= 8) {
                $bits -= 8;
                $out .= chr(($buffer >> $bits) & 255);
            }
        }
        return $out;
    }

    public static function totp(string $secret, int $unixTime): string
    {
        $key = self::base32Decode($secret);
        $counter = intdiv($unixTime, 30);
        $high = intdiv($counter, 0x100000000);
        $low = $counter % 0x100000000;
        $hash = hash_hmac('sha1', pack('N2', $high, $low), $key, true);
        $offset = ord($hash[19]) & 0x0f;
        $binary = ((ord($hash[$offset]) & 0x7f) << 24)
            | ((ord($hash[$offset + 1]) & 0xff) << 16)
            | ((ord($hash[$offset + 2]) & 0xff) << 8)
            | (ord($hash[$offset + 3]) & 0xff);
        return str_pad((string) ($binary % 1000000), 6, '0', STR_PAD_LEFT);
    }

    public static function verifyTotp(string $secret, string $code, ?int $now = null): bool
    {
        if (!preg_match('/^\d{6}$/D', $code)) return false;
        $now ??= time();
        for ($offset = -1; $offset <= 1; $offset++) {
            if (hash_equals(self::totp($secret, $now + ($offset * 30)), $code)) return true;
        }
        return false;
    }
}
