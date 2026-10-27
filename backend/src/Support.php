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

    public static function jsonInput(int $limit = 262144): array
    {
        $body = file_get_contents('php://input', false, null, 0, $limit + 1);
        if ($body === false || strlen($body) > $limit) throw new ApiError(413, 'JSON request too large.');
        try {
            $value = json_decode($body, true, 32, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            throw new ApiError(400, 'Invalid JSON request.');
        }
        if (!is_array($value) || array_is_list($value)) throw new ApiError(400, 'JSON object expected.');
        return $value;
    }

    public static function jsonString(mixed $value, int $maxBytes): string
    {
        if (!is_array($value)) throw new ApiError(422, 'Document must be a JSON object.');
        try {
            $json = json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        } catch (\JsonException $e) {
            throw new ApiError(422, 'Invalid project document.');
        }
        if (strlen($json) > $maxBytes) throw new ApiError(413, 'Project document too large.');
        return $json;
    }
}
