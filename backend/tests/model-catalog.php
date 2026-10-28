<?php
declare(strict_types=1);
require_once __DIR__ . '/../src/ModelCatalog.php';

use Hotice\ModelCatalog;

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
echo "Model catalog tests passed.\n";

