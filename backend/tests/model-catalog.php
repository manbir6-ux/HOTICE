<?php
declare(strict_types=1);
require_once __DIR__ . '/../src/ModelCatalog.php';
require_once __DIR__ . '/../src/FeatureFlags.php';

use Hotice\ModelCatalog;
use Hotice\FeatureFlags;

function checkCatalog(bool $ok, string $message): void
{
    if (!$ok) { fwrite(STDERR, "FAIL: {$message}\n"); exit(1); }
}

$disabled = ModelCatalog::response([
    'mock_jobs_enabled' => false,
    'mock_job_cost_credits' => 5,
    'providers' => ['openai' => ['api_key' => 'must-never-leak']],
]);
checkCatalog($disabled['models'] === [], 'disabled generation exposes no available model');
checkCatalog($disabled['liveGenerationEnabled'] === false, 'live generation is explicitly disabled');
checkCatalog(!str_contains(json_encode($disabled, JSON_THROW_ON_ERROR), 'must-never-leak'), 'secrets never appear in manifest');

$enabled = ModelCatalog::response(['mock_jobs_enabled' => true, 'mock_job_cost_credits' => 7]);
checkCatalog(count($enabled['models']) === 1, 'only the mock model is advertised');
$model = $enabled['models'][0];
checkCatalog($model['id'] === 'hotice.mock.video.v1', 'server model ID matches the dry-run job contract');
checkCatalog($model['availability'] === 'dry_run' && $model['enabled'] === true, 'dry-run status is explicit');
checkCatalog($model['outputs'] === [], 'dry run claims no media output');
checkCatalog($model['pricing'] === ['kind' => 'simulated_credits', 'credits' => 7, 'moneyValue' => 0, 'currency' => null], 'mock pricing has zero monetary value');
checkCatalog($enabled['liveGenerationEnabled'] === false, 'provider calls remain unavailable');
checkCatalog(FeatureFlags::effectiveMockGeneration(true, null), 'missing owner override inherits the staging master gate');
checkCatalog(!FeatureFlags::effectiveMockGeneration(true, false), 'owner can disable a server-allowed dry run');
checkCatalog(!FeatureFlags::effectiveMockGeneration(false, true), 'owner cannot override a disabled server master gate');
checkCatalog(ModelCatalog::response(['mock_jobs_enabled' => true], false)['models'] === [], 'owner disablement removes the model from server availability');
echo "Model catalog tests passed.\n";


