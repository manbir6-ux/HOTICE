<?php
declare(strict_types=1);

namespace Hotice;

/** Deterministic provider-contract fixture. This class never makes network calls. */
final class MockProviderAdapter implements ProviderAdapter
{
    public const MODEL_ID = 'hotice.mock.video.v1';

    /** @var array<string, array{request_hash:string,status:string,scenario:string,attempt:int,polls:int,result:array,error_code:?string,retryable:bool}> */
    private array $operations = [];
    /** @var array<string, string> */
    private array $idempotency = [];

    public function id(): string { return 'mock'; }

    public function modelIds(): array { return [self::MODEL_ID]; }

    public function submit(ProviderRequest $request, string $idempotencyKey): ProviderOperation
    {
        if ($request->modelId !== self::MODEL_ID) throw new ApiError(422, 'Mock provider does not support this model.');
        if (!preg_match('/^[A-Za-z0-9._:-]{16,128}$/', $idempotencyKey)) {
            throw new ApiError(422, 'Invalid provider idempotency key.');
        }
        $scenario = $request->options['simulate'] ?? 'success';
        $attempt = $request->options['attempt'] ?? 1;
        if (!in_array($scenario, ['success', 'timeout_once', 'rate_limit_once', 'malformed_once', 'permanent_failure'], true) ||
            !is_int($attempt) || $attempt < 1 || $attempt > 3) {
            throw new ApiError(422, 'Invalid mock scenario.');
        }
        $requestHash = hash('sha256', json_encode([
            'modelId' => $request->modelId,
            'prompt' => $request->prompt,
            'attachments' => $request->attachments,
            'options' => $request->options,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
        if (isset($this->idempotency[$idempotencyKey])) {
            $existingId = $this->idempotency[$idempotencyKey];
            if (!hash_equals($this->operations[$existingId]['request_hash'], $requestHash)) {
                throw new ApiError(409, 'Mock provider idempotency key was reused for another request.');
            }
            return $this->operation($existingId);
        }

        $id = Support::uuid();
        // Only a request hash and non-sensitive scenario metadata are held in
        // adapter memory. Prompt, attachments, tokens and response bodies are
        // never logged or written by this fixture.
        $this->operations[$id] = [
            'request_hash' => $requestHash,
            'status' => 'queued',
            'scenario' => $scenario,
            'attempt' => $attempt,
            'polls' => 0,
            'result' => [],
            'error_code' => null,
            'retryable' => false,
        ];
        $this->idempotency[$idempotencyKey] = $id;
        return $this->operation($id);
    }

    public function poll(string $operationId): ProviderOperation
    {
        $state = &$this->state($operationId);
        if ($state['status'] === 'queued') {
            $state['status'] = 'processing';
            return $this->operation($operationId);
        }
        if ($state['status'] !== 'processing') return $this->operation($operationId);
        $state['polls']++;
        if ($state['polls'] < 1) return $this->operation($operationId);

        $scenario = $state['scenario'];
        $attempt = $state['attempt'];
        if ($scenario === 'permanent_failure') {
            $state['status'] = 'failed';
            $state['error_code'] = 'mock_provider_rejected';
            return new ProviderOperation($operationId, 'failed', [], 'mock_provider_rejected', false);
        }
        $transientErrors = [
            'timeout_once' => 'mock_timeout',
            'rate_limit_once' => 'mock_rate_limited',
            'malformed_once' => 'mock_malformed_response',
        ];
        if ($attempt === 1 && isset($transientErrors[$scenario])) {
            $state['status'] = 'failed';
            $state['error_code'] = $transientErrors[$scenario];
            $state['retryable'] = true;
            return new ProviderOperation($operationId, 'failed', [], $transientErrors[$scenario], true);
        }

        $state['status'] = 'succeeded';
        $state['result'] = [
            'mode' => 'mock_dry_run',
            'modelId' => self::MODEL_ID,
            'message' => 'Dry run completed. No video or provider output was created.',
        ];
        return $this->operation($operationId);
    }

    public function cancel(string $operationId): ProviderOperation
    {
        $state = &$this->state($operationId);
        if (in_array($state['status'], ['queued', 'processing'], true)) $state['status'] = 'cancelled';
        return $this->operation($operationId);
    }

    private function &state(string $id): array
    {
        if (!Support::isUuid($id) || !isset($this->operations[$id])) throw new ApiError(404, 'Provider operation not found.');
        return $this->operations[$id];
    }

    private function operation(string $id): ProviderOperation
    {
        $state = $this->operations[$id];
        return new ProviderOperation($id, $state['status'], $state['result'], $state['error_code'], $state['retryable']);
    }
}
