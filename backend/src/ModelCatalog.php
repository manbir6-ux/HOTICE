<?php
declare(strict_types=1);

namespace Hotice;

/** Server-authoritative model availability for clients sharing this API. */
final class ModelCatalog
{
    public const VERSION = '2026-10-29.1';

    /**
     * This deliberately lists only the local dry-run model. Research profiles
     * and configured provider keys do not enable billable model submission.
     */
    public static function response(array $config): array
    {
        $enabled = ($config['mock_jobs_enabled'] ?? false) === true;
        $models = [];
        if ($enabled) {
            $models[] = [
                'id' => 'hotice.mock.video.v1',
                'name' => 'HOTICE generation dry run',
                'provider' => 'hotice',
                'mediaType' => 'video',
                'availability' => 'dry_run',
                'enabled' => true,
                'capabilities' => ['text_to_video'],
                'inputs' => ['prompt'],
                'outputs' => [],
                'limits' => ['promptCharacters' => 2000, 'durationSeconds' => null],
                'pricing' => [
                    'kind' => 'simulated_credits',
                    'credits' => max(0, min(1000000, (int)($config['mock_job_cost_credits'] ?? 0))),
                    'moneyValue' => 0,
                    'currency' => null,
                ],
                'notice' => 'Dry run only. It creates no video and makes no provider call.',
            ];
        }

        return [
            'catalogVersion' => self::VERSION,
            'liveGenerationEnabled' => false,
            'models' => $models,
        ];
    }
}

