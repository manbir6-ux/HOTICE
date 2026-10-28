<?php
declare(strict_types=1);

namespace Hotice;

use PDO;

/** Server master gates always take precedence over owner-controlled switches. */
final class FeatureFlags
{
    public const MOCK_GENERATION = 'mock_generation';

    public static function effectiveMockGeneration(bool $serverAllows, ?bool $ownerOverride): bool
    {
        return $serverAllows && ($ownerOverride ?? true);
    }

    public static function mockGenerationEnabled(PDO $db, array $config): bool
    {
        $serverAllows = ($config['mock_jobs_enabled'] ?? false) === true;
        if (!$serverAllows) return false;
        $q = $db->prepare('SELECT enabled FROM system_feature_flags WHERE flag_key=?');
        $q->execute([self::MOCK_GENERATION]);
        $value = $q->fetchColumn();
        $ownerOverride = $value === false ? null : (int)$value === 1;
        return self::effectiveMockGeneration($serverAllows, $ownerOverride);
    }
}

