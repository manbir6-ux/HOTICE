<?php
declare(strict_types=1);

namespace Hotice;

/** Ephemeral normalized input passed to a server-side provider adapter. */
final readonly class ProviderRequest
{
    public function __construct(
        public string $modelId,
        public string $prompt,
        public array $attachments = [],
        public array $options = [],
    ) {
        if (!preg_match('/^[a-z0-9][a-z0-9._:-]{2,127}$/i', $modelId)) {
            throw new \InvalidArgumentException('Invalid model identifier.');
        }
        if (strlen($prompt) > 30000) throw new \InvalidArgumentException('Prompt is too large.');
        if (count($attachments) > 20) throw new \InvalidArgumentException('Too many attachments.');
    }
}

/** Provider-neutral result; error codes must be safe and contain no provider body. */
final readonly class ProviderOperation
{
    public const STATES = ['queued', 'processing', 'succeeded', 'failed', 'cancelled'];

    public function __construct(
        public string $operationId,
        public string $status,
        public array $result = [],
        public ?string $errorCode = null,
        public bool $retryable = false,
    ) {
        if (!Support::isUuid($operationId)) throw new \InvalidArgumentException('Invalid provider operation identifier.');
        if (!in_array($status, self::STATES, true)) throw new \InvalidArgumentException('Invalid provider operation state.');
        if ($errorCode !== null && !preg_match('/^[a-z][a-z0-9_]{1,63}$/', $errorCode)) {
            throw new \InvalidArgumentException('Invalid provider error code.');
        }
        if ($status !== 'failed' && ($errorCode !== null || $retryable)) {
            throw new \InvalidArgumentException('Only failed operations may carry retry information.');
        }
    }
}

/**
 * Server-only boundary for provider integrations. Implementations own their
 * credentials and must return normalized states without leaking raw responses.
 */
interface ProviderAdapter
{
    public function id(): string;

    /** @return list<string> */
    public function modelIds(): array;

    public function submit(ProviderRequest $request, string $idempotencyKey): ProviderOperation;

    public function poll(string $operationId): ProviderOperation;

    public function cancel(string $operationId): ProviderOperation;
}

/** Fail-closed model routing; one model can be owned by exactly one adapter. */
final class ProviderRegistry
{
    /** @var array<string, ProviderAdapter> */
    private array $byModel = [];

    /** @param list<ProviderAdapter> $adapters */
    public function __construct(array $adapters)
    {
        foreach ($adapters as $adapter) {
            if (!$adapter instanceof ProviderAdapter || !preg_match('/^[a-z][a-z0-9_-]{1,31}$/', $adapter->id())) {
                throw new \InvalidArgumentException('Invalid provider adapter registration.');
            }
            foreach ($adapter->modelIds() as $modelId) {
                if (!is_string($modelId) || !preg_match('/^[a-z0-9][a-z0-9._:-]{2,127}$/i', $modelId)) {
                    throw new \InvalidArgumentException('Invalid provider model registration.');
                }
                if (isset($this->byModel[$modelId])) throw new \InvalidArgumentException('Model is registered by multiple providers.');
                $this->byModel[$modelId] = $adapter;
            }
        }
    }

    public function forModel(string $modelId): ProviderAdapter
    {
        if (!isset($this->byModel[$modelId])) throw new ApiError(422, 'No enabled provider supports this model.');
        return $this->byModel[$modelId];
    }

    /** @return list<string> */
    public function enabledModelIds(): array
    {
        return array_keys($this->byModel);
    }
}
