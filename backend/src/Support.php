<?php
declare(strict_types=1);

namespace Hotice;

final class ApiError extends \RuntimeException
{
    public function __construct(public readonly int $status, string $message)
    {
        parent::__construct($message);
    }
}

final class Support
{
    private const PASSWORD_HASH_PREFIX = 'hotice-sha256-v1:';

    /** Pre-hash the full password because cPanel may use bcrypt's 72-byte limit. */
    public static function passwordHash(string $password): string
    {
        return self::PASSWORD_HASH_PREFIX . password_hash(hash('sha256', $password), PASSWORD_DEFAULT);
    }

    public static function passwordVerify(string $password, string $storedHash): bool
    {
        if (str_starts_with($storedHash, self::PASSWORD_HASH_PREFIX)) {
            return password_verify(hash('sha256', $password), substr($storedHash, strlen(self::PASSWORD_HASH_PREFIX)));
        }
        if (str_contains($password, "\0")) return false;
        return password_verify($password, $storedHash);
    }

    public static function passwordNeedsRehash(string $storedHash): bool
    {
        if (!str_starts_with($storedHash, self::PASSWORD_HASH_PREFIX)) return true;
        return password_needs_rehash(substr($storedHash, strlen(self::PASSWORD_HASH_PREFIX)), PASSWORD_DEFAULT);
    }

    public static function uuid(): string
    {
        $b = random_bytes(16);
        $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
        $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
        $hex = bin2hex($b);
        return sprintf('%s-%s-%s-%s-%s', substr($hex, 0, 8), substr($hex, 8, 4),
            substr($hex, 12, 4), substr($hex, 16, 4), substr($hex, 20));
    }

    public static function isUuid(string $value): bool
    {
        return (bool) preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $value);
    }

    public static function email(string $value): string
    {
        $email = strtolower(trim($value));
        if (strlen($email) > 254 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new ApiError(422, 'Valid email required.');
        }
        return $email;
    }

    public static function secureFileName(string $value): bool
    {
        return (bool) preg_match('/^[a-f0-9]{64}$/D', $value);
    }

    /**
     * Canonicalise paths and prevent storage from being inside, equal to, or
     * an ancestor of any publicly served directory. Resolve symlinks first.
     */
    public static function assertPrivateStorage(string $storage, array $roots): string
    {
        $real = realpath($storage);
        if ($real === false || !is_dir($real)) {
            throw new \RuntimeException('Private storage directory missing.');
        }
        if ($roots === []) throw new \RuntimeException('No web roots available for safety check.');
        foreach ($roots as $root) {
            $public = realpath((string) $root);
            if ($public === false || !is_dir($public)) {
                throw new \RuntimeException('Public web root cannot be verified.');
            }
            if ($real === $public || str_starts_with($real . '/', $public . '/')
                || str_starts_with($public . '/', $real . '/')) {
                throw new \RuntimeException('Private storage must be outside all public web roots.');
            }
        }
        return $real;
    }

    public static function jsonInput(int $limit = 262144): array
    {
        $body = file_get_contents('php://input', false, null, 0, $limit + 1);
        if ($body === false || strlen($body) > $limit) throw new ApiError(413, 'JSON request too large.');
        try {
            // Keep nested empty JSON objects as stdClass, not [].
            $value = json_decode($body, false, 32, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            throw new ApiError(400, 'Invalid JSON request.');
        }
        if (!$value instanceof \stdClass) throw new ApiError(400, 'JSON object expected.');
        return (array) $value;
    }

    public static function jsonString(mixed $value, int $maxBytes): string
    {
        if (!$value instanceof \stdClass && (!is_array($value) || array_is_list($value))) {
            throw new ApiError(422, 'Document must be a JSON object.');
        }
        try {
            $json = json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        } catch (\JsonException $e) {
            throw new ApiError(422, 'Invalid project document.');
        }
        if (strlen($json) > $maxBytes) throw new ApiError(413, 'Project document too large.');
        return $json;
    }
}

