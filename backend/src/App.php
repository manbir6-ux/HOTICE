<?php
declare(strict_types=1);

namespace Hotice;

use PDO;
use Throwable;

require_once __DIR__ . '/Support.php';
require_once __DIR__ . '/EmailOutbox.php';

final class App
{
    private PDO $db;
    /** @var list<string> */
    private array $webAllowedOrigins;

    public function __construct(private readonly array $config)
    {
        if (!extension_loaded('pdo_mysql') || !extension_loaded('fileinfo') || !extension_loaded('openssl')) {
            throw new \RuntimeException('Required PHP extensions (pdo_mysql, fileinfo, openssl) are unavailable.');
        }
        if (!preg_match('/^[a-f0-9]{64}$/iD', (string) ($config['app_key'] ?? ''))) {
            throw new \RuntimeException('Server app_key must be a unique 64-character hex secret.');
        }
        if (($config['allow_registration'] ?? false) === true) {
            $verificationUrl = parse_url((string)($config['verification_url'] ?? ''));
            $hasTransport = is_callable($config['mail_transport'] ?? null) ||
                filter_var((string)($config['mail_from'] ?? ''), FILTER_VALIDATE_EMAIL) !== false;
            if (!is_array($verificationUrl) || ($verificationUrl['scheme'] ?? '') !== 'https' ||
                empty($verificationUrl['host']) || isset($verificationUrl['user']) || isset($verificationUrl['pass']) ||
                isset($verificationUrl['query']) || isset($verificationUrl['fragment']) || !$hasTransport) {
                throw new \RuntimeException('Public registration requires an HTTPS verification_url and configured mail delivery.');
            }
        }
        $this->webAllowedOrigins = $this->validateWebOrigins($config['web_allowed_origins'] ?? []);
        $dsn = (string) $config['db']['dsn'];
        $this->db = new PDO($dsn, (string) $config['db']['user'],
            (string) $config['db']['password'], [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
    }

    public function database(): PDO { return $this->db; }

    /** @return list<string> */
    private function validateWebOrigins(mixed $origins): array
    {
        if (!is_array($origins) || !array_is_list($origins)) {
            throw new \RuntimeException('web_allowed_origins must be a list of exact HTTPS origins.');
        }
        $validated = [];
        foreach ($origins as $origin) {
            if (!is_string($origin) || $origin === '' || strlen($origin) > 255) {
                throw new \RuntimeException('Invalid web origin in server configuration.');
            }
            $parts = parse_url($origin);
            if (!is_array($parts) || array_diff(array_keys($parts), ['scheme', 'host', 'port']) !== [] ||
                !isset($parts['scheme'], $parts['host'])) {
                throw new \RuntimeException('Web origins must not include paths, credentials, queries, or fragments.');
            }
            $scheme = strtolower((string)$parts['scheme']);
            $host = strtolower((string)$parts['host']);
            $isLocalHost = in_array($host, ['localhost', '127.0.0.1'], true);
            if (($scheme !== 'https' && !($scheme === 'http' && $isLocalHost)) ||
                (filter_var($host, FILTER_VALIDATE_IP) === false &&
                    filter_var($host, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME) === false)) {
                throw new \RuntimeException('Web origins must use HTTPS (HTTP is allowed for localhost only).');
            }
            $port = $parts['port'] ?? null;
            if ($port !== null && ($port < 1 || $port > 65535)) {
                throw new \RuntimeException('Invalid web origin port.');
            }
            $normalized = $scheme . '://' . $host . ($port === null ? '' : ':' . $port);
            if ($origin !== $normalized || in_array($origin, $validated, true)) {
                throw new \RuntimeException('Web origins must be unique canonical origins without a trailing slash.');
            }
            $validated[] = $origin;
        }
        return $validated;
    }

    public function run(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");
        header('Cache-Control: no-store, max-age=0');
        header('Referrer-Policy: no-referrer');
        if ($this->https()) header('Strict-Transport-Security: max-age=31536000');
        $requestId = bin2hex(random_bytes(8));
        header('X-Request-ID: ' . $requestId);
        try {
            if (($this->config['require_https'] ?? true) && !$this->https()) {
                throw new ApiError(426, 'HTTPS is required.');
            }
            $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
            if ($this->handleCors($method)) return;
            $route = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
            if (!is_string($route)) throw new ApiError(400, 'Invalid request path.');
            $route = rtrim($route, '/') ?: '/';

            if ($route === '/health' && $method === 'GET') {
                $this->send(200, ['service' => 'HOTICE API', 'status' => 'ok', 'version' => '0.1']);
                return;
            }
            if ($route === '/v1/auth/register' && $method === 'POST') {
                $this->register(); return;
            }
            if ($route === '/v1/auth/verify-email' && $method === 'POST') {
                $this->verifyEmail(); return;
            }
            if ($route === '/v1/auth/verification/resend' && $method === 'POST') {
                $this->resendVerification(); return;
            }
            if ($route === '/v1/auth/password-reset/request' && $method === 'POST') {
                $this->requestPasswordReset(); return;
            }
            if ($route === '/v1/auth/password-reset/complete' && $method === 'POST') {
                $this->completePasswordReset(); return;
            }
            if ($route === '/v1/auth/login' && $method === 'POST') {
                $this->login(); return;
            }
            $user = $this->authenticate();
            if ($route === '/v1/auth/logout' && $method === 'POST') {
                $this->db->prepare('UPDATE sessions SET revoked_at=UTC_TIMESTAMP() WHERE id=? AND user_id=?')
                    ->execute([$user['session_id'], $user['id']]);
                $this->send(200, ['ok' => true]); return;
            }
            if ($route === '/v1/me' && $method === 'GET') {
                $e = $this->entitlement($user['id']);
                $credits = null;
                if (($this->config['mock_jobs_enabled'] ?? false) === true) {
                    $q = $this->db->prepare('SELECT balance FROM credit_accounts WHERE user_id=?');
                    $q->execute([$user['id']]);
                    $credits = (int)($q->fetchColumn() ?: 0);
                }
                $this->send(200, [
                    'user' => ['id' => $user['id'], 'email' => $user['email']],
                    'cloud' => ['active' => $this->canWriteCloud($e),
                        'readable' => $this->canReadCloud($e),
                        'plan' => $e['plan_code'] ?? null,
                        'quotaBytes' => isset($e['quota_bytes']) ? (int) $e['quota_bytes'] : 0,
                        'usedBytes' => isset($e['used_bytes']) ? (int) $e['used_bytes'] : 0,
                        'expiresAt' => $e['expires_at'] ?? null],
                    'mockGeneration' => ['enabled' => ($this->config['mock_jobs_enabled'] ?? false) === true,
                        'credits' => $credits, 'unit' => 'simulated_credits', 'moneyValue' => 0],
                ]); return;
            }
            if ($route === '/v1/me/export' && $method === 'GET') {
                $this->exportAccount($user['id']); return;
            }
            if ($route === '/v1/me/preferences' && $method === 'GET') {
                $this->getPreferences($user['id']); return;
            }
            if ($route === '/v1/me/preferences' && $method === 'PUT') {
                $this->putPreferences($user['id']); return;
            }
            if ($route === '/v1/me' && $method === 'DELETE') {
                $this->deleteAccount($user); return;
            }
            if ($route === '/v1/jobs/quote' && $method === 'POST') { $this->quoteMockJob($user['id']); return; }
            if ($route === '/v1/jobs' && $method === 'POST') { $this->createMockJob($user['id']); return; }
            if ($route === '/v1/jobs' && $method === 'GET') { $this->listJobs($user['id']); return; }
            if (preg_match('~^/v1/jobs/([a-f0-9-]{36})$~D', $route, $m) && Support::isUuid($m[1]) && $method === 'GET') {
                $this->getJob($user['id'], $m[1]); return;
            }
            if (preg_match('~^/v1/jobs/([a-f0-9-]{36})/cancel$~D', $route, $m) && Support::isUuid($m[1]) && $method === 'POST') {
                $this->cancelJob($user['id'], $m[1]); return;
            }
            if ($route === '/v1/projects' && $method === 'GET') {
                $this->requireCloud($user['id'], false);
                $q = $this->db->prepare('SELECT id,title,revision,updated_at FROM cloud_projects WHERE user_id=? ORDER BY updated_at DESC LIMIT 200');
                $q->execute([$user['id']]);
                $this->send(200, ['projects' => $q->fetchAll()]); return;
            }
            if (preg_match('~^/v1/projects/([a-f0-9-]{36})$~D', $route, $m) && Support::isUuid($m[1])) {
                if ($method === 'PUT') { $this->putProject($user['id'], $m[1]); return; }
                if ($method === 'GET') { $this->getProject($user['id'], $m[1]); return; }
                if ($method === 'DELETE') { $this->deleteProject($user['id'], $m[1]); return; }
            }
            if (preg_match('~^/v1/projects/([a-f0-9-]{36})/files/([a-f0-9-]{36})$~D', $route, $m)
                && Support::isUuid($m[1]) && Support::isUuid($m[2]) && $method === 'PUT') {
                $this->uploadFile($user['id'], $m[1], $m[2]); return;
            }
            if (preg_match('~^/v1/files/([a-f0-9-]{36})$~D', $route, $m) && Support::isUuid($m[1])) {
                if ($method === 'GET') { $this->downloadFile($user['id'], $m[1]); return; }
                if ($method === 'DELETE') { $this->deleteFile($user['id'], $m[1]); return; }
            }
            throw new ApiError(404, 'Endpoint not found.');
        } catch (ApiError $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            $this->send($e->status, ['error' => $e->getMessage(), 'requestId' => $requestId]);
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            error_log('HOTICE API request ' . $requestId . ' failed (' . get_class($e) . ')');
            $this->send(500, ['error' => 'Internal server error.', 'requestId' => $requestId]);
        }
    }

    /**
     * Allow browser clients only from exact configured origins. Native clients
     * omit Origin and continue to use the same bearer-authenticated API.
     */
    private function handleCors(string $method): bool
    {
        header('Vary: Origin');
        $origin = (string)($_SERVER['HTTP_ORIGIN'] ?? '');
        if ($origin !== '') {
            if (!in_array($origin, $this->webAllowedOrigins, true)) {
                throw new ApiError(403, 'Browser origin is not allowed.');
            }
            header('Access-Control-Allow-Origin: ' . $origin);
        }
        if ($method !== 'OPTIONS') return false;
        if ($origin === '') throw new ApiError(400, 'CORS preflight requires an Origin header.');

        $methods = ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'];
        $requestedMethod = strtoupper(trim((string)($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_METHOD'] ?? '')));
        if (!in_array($requestedMethod, $methods, true)) {
            throw new ApiError(403, 'Requested browser method is not allowed.');
        }
        $allowedHeaders = ['authorization', 'content-type', 'idempotency-key'];
        $requestedHeaders = trim((string)($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'] ?? ''));
        if ($requestedHeaders !== '') {
            foreach (explode(',', strtolower($requestedHeaders)) as $headerName) {
                if (!in_array(trim($headerName), $allowedHeaders, true)) {
                    throw new ApiError(403, 'Requested browser header is not allowed.');
                }
            }
        }
        header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Authorization, Content-Type, Idempotency-Key');
        header('Access-Control-Max-Age: 600');
        http_response_code(204);
        return true;
    }

    private function https(): bool
    {
        return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (int) ($_SERVER['SERVER_PORT'] ?? 0) === 443;
        // Deliberately DO NOT trust arbitrary X-Forwarded-Proto from clients.
    }

    private function send(int $code, array $data): void
    {
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }

    private function requireMockJobs(): void
    {
        if (($this->config['mock_jobs_enabled'] ?? false) !== true) {
            throw new ApiError(503, 'Mock generation is disabled on this server.');
        }
    }

    /** Normalize a deliberately small mock-only request contract. */
    private function normalizeMockJobRequest(mixed $raw): array
    {
        if (!$raw instanceof \stdClass) throw new ApiError(422, 'Job request object required.');
        $values = get_object_vars($raw);
        $unknown = array_diff(array_keys($values), ['modelId', 'prompt', 'simulate']);
        if ($unknown !== []) throw new ApiError(422, 'Unsupported job request field.');
        $model = $values['modelId'] ?? null;
        if ($model !== 'hotice.mock.video.v1') throw new ApiError(422, 'Model is not enabled for mock generation.');
        $prompt = $values['prompt'] ?? null;
        if (!is_string($prompt)) throw new ApiError(422, 'Prompt must be text.');
        $prompt = trim($prompt);
        $length = preg_match_all('/./us', $prompt);
        if ($prompt === '' || strlen($prompt) > 8000 || $length === false || $length > 2000 ||
            preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $prompt)) {
            throw new ApiError(422, 'Prompt must be 1–2000 readable characters.');
        }
        $simulate = $values['simulate'] ?? 'success';
        $allowed = ['success', 'timeout_once', 'rate_limit_once', 'malformed_once', 'permanent_failure'];
        if (!is_string($simulate) || !in_array($simulate, $allowed, true)) {
            throw new ApiError(422, 'Unsupported dry-run scenario.');
        }
        return ['modelId' => $model, 'prompt' => $prompt, 'simulate' => $simulate];
    }

    private function mockRequestHash(array $request, string $user): string
    {
        $canonical = json_encode($request, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        // A plain digest still permits offline guessing of common prompts after
        // a database disclosure. Bind a keyed digest to this account as well as
        // the canonical request so stored rows cannot be compared across users.
        return hash_hmac('sha256', "hotice:mock-request:v1\0" . $user . "\0" . $canonical,
            (string)$this->config['app_key']);
    }

    private function signMockQuote(array $payload): string
    {
        $encoded = rtrim(strtr(base64_encode(json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)), '+/', '-_'), '=');
        return $encoded . '.' . hash_hmac('sha256', $encoded, (string)$this->config['app_key']);
    }

    private function verifyMockQuote(string $token): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 2 || !preg_match('/^[A-Za-z0-9_-]+$/D', $parts[0]) ||
            !preg_match('/^[a-f0-9]{64}$/D', $parts[1]) ||
            !hash_equals(hash_hmac('sha256', $parts[0], (string)$this->config['app_key']), $parts[1])) {
            throw new ApiError(422, 'Quote signature is invalid.');
        }
        $raw = base64_decode(strtr($parts[0], '-_', '+/') . str_repeat('=', (4 - strlen($parts[0]) % 4) % 4), true);
        $payload = is_string($raw) ? json_decode($raw, true) : null;
        if (!is_array($payload)) throw new ApiError(422, 'Quote is invalid.');
        return $payload;
    }

    private function quoteMockJob(string $user): void
    {
        $this->requireMockJobs();
        $body = Support::jsonInput(16384);
        $request = $this->normalizeMockJobRequest($body['request'] ?? null);
        $requestHash = $this->mockRequestHash($request, $user);
        $credits = max(0, min(1000000, (int)($this->config['mock_job_cost_credits'] ?? 0)));
        $ttl = max(60, min(600, (int)($this->config['mock_job_quote_ttl_seconds'] ?? 300)));
        $expires = time() + $ttl;
        $quoteId = Support::uuid();
        $this->db->prepare('INSERT INTO job_quotes(id,user_id,request_sha256,credits,expires_at) VALUES(?,?,?,?,?)')
            ->execute([$quoteId, $user, $requestHash, $credits, gmdate('Y-m-d H:i:s', $expires)]);
        $token = $this->signMockQuote(['quoteId' => $quoteId, 'userId' => $user,
            'requestSha256' => $requestHash, 'credits' => $credits, 'expiresAt' => $expires]);
        $this->send(200, ['quoteToken' => $token, 'modelId' => $request['modelId'],
            'credits' => $credits, 'currency' => 'simulated_credits', 'expiresAt' => gmdate('c', $expires)]);
    }

    private function createMockJob(string $user): void
    {
        $this->requireMockJobs();
        $body = Support::jsonInput(20000);
        $request = $this->normalizeMockJobRequest($body['request'] ?? null);
        // The staging worker never sends the prompt to a provider. Keep only
        // execution metadata in its durable queue record and retain the
        // one-way hash for quote binding and idempotency. This avoids storing
        // user prompt text in plaintext in the mock jobs table.
        $requestHash = $this->mockRequestHash($request, $user);
        $requestJson = json_encode([
            'modelId' => $request['modelId'],
            'simulate' => $request['simulate'],
        ], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $idempotencyKey = trim((string)($_SERVER['HTTP_IDEMPOTENCY_KEY'] ?? ''));
        if (!preg_match('/^[A-Za-z0-9._~:-]{16,128}$/D', $idempotencyKey)) {
            throw new ApiError(400, 'Idempotency-Key header required (16–128 safe characters).');
        }
        $idempotencyHash = hash('sha256', $idempotencyKey);
        $this->db->beginTransaction();
        $this->db->prepare('INSERT INTO credit_accounts(user_id,balance) VALUES(?,0) ON DUPLICATE KEY UPDATE user_id=VALUES(user_id)')
            ->execute([$user]);
        $account = $this->db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
        $account->execute([$user]);
        $balance = (int)$account->fetchColumn();
        $existing = $this->db->prepare('SELECT id,request_sha256 FROM generation_jobs WHERE user_id=? AND idempotency_hash=? LIMIT 1 FOR UPDATE');
        $existing->execute([$user, $idempotencyHash]);
        $job = $existing->fetch();
        if ($job) {
            $this->db->commit();
            if (!hash_equals($job['request_sha256'], $requestHash)) throw new ApiError(409, 'Idempotency key was used for a different request.');
            $this->send(200, ['job' => $this->jobForUser($user, $job['id']), 'idempotentReplay' => true]);
            return;
        }
        if (!is_string($body['quoteToken'] ?? null) || strlen($body['quoteToken']) > 4096) {
            throw new ApiError(422, 'Quote token is invalid.');
        }
        $quote = $this->verifyMockQuote($body['quoteToken']);
        $quoteId = (string)($quote['quoteId'] ?? '');
        if (!Support::isUuid($quoteId) || ($quote['userId'] ?? null) !== $user ||
            ($quote['requestSha256'] ?? null) !== $requestHash || !is_int($quote['credits'] ?? null) ||
            !is_int($quote['expiresAt'] ?? null) || $quote['expiresAt'] < time()) {
            throw new ApiError(409, 'Quote is expired or does not match this account and request.');
        }
        $quoted = $this->db->prepare('SELECT user_id,request_sha256,credits,expires_at,consumed_job_id FROM job_quotes WHERE id=? FOR UPDATE');
        $quoted->execute([$quoteId]);
        $storedQuote = $quoted->fetch();
        if (!$storedQuote || $storedQuote['user_id'] !== $user ||
            !hash_equals($storedQuote['request_sha256'], $requestHash) || (int)$storedQuote['credits'] !== $quote['credits'] ||
            $storedQuote['consumed_job_id'] !== null || strtotime($storedQuote['expires_at'] . ' UTC') < time()) {
            throw new ApiError(409, 'Quote is expired or already used. Request a new quote.');
        }
        $credits = (int)$storedQuote['credits'];
        if ($balance < $credits) throw new ApiError(402, 'Insufficient simulated credits.');
        $jobId = Support::uuid();
        $this->db->prepare("INSERT INTO generation_jobs(id,user_id,quote_id,idempotency_hash,request_sha256,model_id,request_json,reserved_credits,max_attempts) VALUES(?,?,?,?,?,?,?, ?,3)")
            ->execute([$jobId, $user, $quoteId, $idempotencyHash, $requestHash, $request['modelId'], $requestJson, $credits]);
        $nextBalance = $balance - $credits;
        $this->db->prepare('UPDATE credit_accounts SET balance=? WHERE user_id=?')->execute([$nextBalance, $user]);
        $this->db->prepare("INSERT INTO credit_ledger(user_id,job_id,event_key,event_type,delta,balance_after) VALUES(?,?,?,'reserve',?,?)")
            ->execute([$user, $jobId, hash('sha256', 'reserve:' . $jobId), -$credits, $nextBalance]);
        $this->db->prepare('UPDATE job_quotes SET consumed_job_id=? WHERE id=? AND consumed_job_id IS NULL')->execute([$jobId, $quoteId]);
        $this->db->commit();
        $this->send(201, ['job' => $this->jobForUser($user, $jobId), 'idempotentReplay' => false]);
    }

    private function listJobs(string $user): void
    {
        $this->requireMockJobs();
        $q = $this->db->prepare('SELECT id FROM generation_jobs WHERE user_id=? ORDER BY created_at DESC LIMIT 50');
        $q->execute([$user]);
        $jobs = [];
        foreach ($q->fetchAll() as $row) $jobs[] = $this->jobForUser($user, $row['id']);
        $this->send(200, ['jobs' => $jobs]);
    }

    private function getJob(string $user, string $id): void
    {
        $this->requireMockJobs();
        $job = $this->jobForUser($user, $id);
        if ($job === null) throw new ApiError(404, 'Job not found.');
        $this->send(200, ['job' => $job]);
    }

    private function jobForUser(string $user, string $id): ?array
    {
        $q = $this->db->prepare('SELECT id,model_id,status,attempt_count,max_attempts,reserved_credits,actual_credits,result_json,error_code,created_at,updated_at,finished_at FROM generation_jobs WHERE user_id=? AND id=?');
        $q->execute([$user, $id]);
        $row = $q->fetch();
        if (!$row) return null;
        return ['id' => $row['id'], 'modelId' => $row['model_id'], 'status' => $row['status'],
            'attempts' => (int)$row['attempt_count'], 'maxAttempts' => (int)$row['max_attempts'],
            'reservedCredits' => (int)$row['reserved_credits'], 'chargedCredits' => (int)$row['actual_credits'],
            'result' => $row['result_json'] === null ? null : json_decode($row['result_json'], true),
            'errorCode' => $row['error_code'], 'createdAt' => $row['created_at'],
            'updatedAt' => $row['updated_at'], 'finishedAt' => $row['finished_at']];
    }

    private function cancelJob(string $user, string $id): void
    {
        $this->requireMockJobs();
        $this->db->beginTransaction();
        $this->db->prepare('INSERT INTO credit_accounts(user_id,balance) VALUES(?,0) ON DUPLICATE KEY UPDATE user_id=VALUES(user_id)')
            ->execute([$user]);
        $account = $this->db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
        $account->execute([$user]);
        $balance = (int)$account->fetchColumn();
        $q = $this->db->prepare('SELECT status,reserved_credits FROM generation_jobs WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$id, $user]);
        $job = $q->fetch();
        if (!$job) throw new ApiError(404, 'Job not found.');
        if ($job['status'] === 'cancelled') {
            $this->db->commit(); $this->send(200, ['job' => $this->jobForUser($user, $id), 'alreadyCancelled' => true]); return;
        }
        if ($job['status'] !== 'queued') throw new ApiError(409, 'Only queued jobs can be cancelled.');
        $refund = (int)$job['reserved_credits'];
        $nextBalance = $balance + $refund;
        $this->db->prepare('UPDATE credit_accounts SET balance=? WHERE user_id=?')->execute([$nextBalance, $user]);
        $this->db->prepare("INSERT INTO credit_ledger(user_id,job_id,event_key,event_type,delta,balance_after) VALUES(?,?,?,'refund',?,?)")
            ->execute([$user, $id, hash('sha256', 'refund:' . $id), $refund, $nextBalance]);
        $this->db->prepare("UPDATE generation_jobs SET status='cancelled',actual_credits=0,error_code='cancelled_by_user',finished_at=UTC_TIMESTAMP(),lease_token=NULL,lease_until=NULL WHERE id=? AND user_id=?")
            ->execute([$id, $user]);
        $this->db->commit();
        $this->send(200, ['job' => $this->jobForUser($user, $id), 'alreadyCancelled' => false]);
    }

    /**
     * Separate per-email and per-client-IP limits prevent two common bypasses:
     * distributing guesses for one account over many IPs, and spraying many
     * email addresses from one IP. All identifiers are keyed HMAC digests.
     * Clean expired rows using bin/cleanup.php (cron).
     */
    private function throttle(string $email): array
    {
        $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        $key = (string) $this->config['app_key'];
        $identities = [
            'email' => hash_hmac('sha256', 'email:' . $email, $key),
            'ip' => hash_hmac('sha256', 'ip:' . $ip, $key),
        ];
        $q = $this->db->prepare('SELECT COUNT(*) FROM login_attempts WHERE fingerprint=? AND occurred_at > DATE_SUB(UTC_TIMESTAMP(), INTERVAL 15 MINUTE)');
        foreach (['email' => 12, 'ip' => 50] as $type => $maxAttempts) {
            $q->execute([$identities[$type]]);
            if ((int) $q->fetchColumn() >= $maxAttempts) {
                throw new ApiError(429, 'Too many attempts. Try later.');
            }
        }
        return $identities;
    }

    private function recordFailedLogin(array $fingerprints): void
    {
        $q = $this->db->prepare('INSERT INTO login_attempts (fingerprint,occurred_at) VALUES (?,UTC_TIMESTAMP())');
        foreach ($fingerprints as $fingerprint) $q->execute([$fingerprint]);
    }

    private function register(): void
    {
        if (!$this->config['allow_registration']) throw new ApiError(403, 'Public registration disabled.');
        $b = Support::jsonInput(8192);
        $email = Support::email((string) ($b['email'] ?? ''));
        $password = (string) ($b['password'] ?? '');
        if (strlen($password) < 12 || strlen($password) > 256) throw new ApiError(422, 'Password must be 12–256 bytes.');
        $f = $this->throttle($email);
        $this->recordFailedLogin($f); // shared bounded signup and login-attempt budget
        // Registration never creates a usable account until the mailbox owner
        // proves control using the one-time, short-lived verification token.
        $this->db->beginTransaction();
        try {
            $userId = Support::uuid();
            $this->db->prepare('INSERT INTO users (id,email,password_hash) VALUES (?,?,?)')
                ->execute([$userId, $email, Support::passwordHash($password)]);
            $this->issueVerification($userId, $email);
            $this->db->commit();
        } catch (\PDOException $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            if ($e->getCode() !== '23000') throw $e;
            $this->send(202, ['registered' => true, 'verificationRequired' => true]);
            return;
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        $this->send(202, ['registered' => true, 'verificationRequired' => true]);
    }

    private function issueVerification(string $userId, string $email): void
    {
        $token = bin2hex(random_bytes(32));
        $expires = gmdate('Y-m-d H:i:s', time() + 30 * 60);
        $this->db->prepare('INSERT INTO email_verification_tokens (id,user_id,token_sha256,expires_at) VALUES (?,?,?,?)')
            ->execute([Support::uuid(), $userId, hash('sha256', $token), $expires]);
        $base = (string) ($this->config['verification_url'] ?? '');
        $parts = parse_url($base);
        if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'https' || empty($parts['host']) ||
            isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment'])) {
            throw new \RuntimeException('A public HTTPS verification_url is required before registration can be enabled.');
        }
        // Keep the credential in the URL fragment so static hosts, access
        // logs, and HTTP Referer headers never receive it.
        $url = rtrim($base, '/') . '#token=' . rawurlencode($token);
        $subject = 'Verify your HOTICE account';
        $body = "Verify your email address within 30 minutes by opening this link:\n\n$url\n\nIf you did not create this account, ignore this message.";
        EmailOutbox::enqueue($this->db, $this->config, $email, $subject, $body, $expires);
    }

    private function resendVerification(): void
    {
        $b = Support::jsonInput(2048);
        $email = Support::email((string) ($b['email'] ?? ''));
        $f = $this->throttle($email);
        $this->recordFailedLogin($f);
        $this->db->beginTransaction();
        try {
            $q = $this->db->prepare('SELECT id,email_verified_at FROM users WHERE email=? LIMIT 1 FOR UPDATE');
            $q->execute([$email]);
            $user = $q->fetch();
            if ($user && $user['email_verified_at'] === null) {
                $this->db->prepare('UPDATE email_verification_tokens SET used_at=UTC_TIMESTAMP() WHERE user_id=? AND used_at IS NULL')
                    ->execute([$user['id']]);
                $this->issueVerification((string) $user['id'], $email);
            }
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        $this->send(202, ['accepted' => true]);
    }

    private function verifyEmail(): void
    {
        $b = Support::jsonInput(2048);
        $token = (string) ($b['token'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/D', $token)) throw new ApiError(400, 'Verification link is invalid or expired.');
        $this->db->beginTransaction();
        try {
            $q = $this->db->prepare('SELECT id,user_id FROM email_verification_tokens WHERE token_sha256=? AND used_at IS NULL AND expires_at>UTC_TIMESTAMP() LIMIT 1 FOR UPDATE');
            $q->execute([hash('sha256', $token)]);
            $row = $q->fetch();
            if (!$row) throw new ApiError(400, 'Verification link is invalid or expired.');
            $this->db->prepare('UPDATE users SET email_verified_at=UTC_TIMESTAMP() WHERE id=? AND email_verified_at IS NULL')
                ->execute([$row['user_id']]);
            $this->db->prepare('UPDATE email_verification_tokens SET used_at=UTC_TIMESTAMP() WHERE user_id=? AND used_at IS NULL')
                ->execute([$row['user_id']]);
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        $this->send(200, ['verified' => true]);
    }

    private function requestPasswordReset(): void
    {
        $b = Support::jsonInput(2048);
        $email = Support::email((string)($b['email'] ?? ''));
        $fingerprints = $this->throttle($email);
        $this->recordFailedLogin($fingerprints);
        $this->db->beginTransaction();
        try {
            $q = $this->db->prepare('SELECT id FROM users WHERE email=? AND email_verified_at IS NOT NULL LIMIT 1 FOR UPDATE');
            $q->execute([$email]);
            $userId = $q->fetchColumn();
            if ($userId) {
                $recent = $this->db->prepare('SELECT id FROM password_reset_tokens WHERE user_id=? AND created_at>DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 MINUTE) LIMIT 1');
                $recent->execute([$userId]);
                if (!$recent->fetch()) {
                    $this->db->prepare('UPDATE password_reset_tokens SET used_at=UTC_TIMESTAMP() WHERE user_id=? AND used_at IS NULL')
                        ->execute([$userId]);
                    $token = bin2hex(random_bytes(32));
                    $expires = gmdate('Y-m-d H:i:s', time() + 30 * 60);
                    $this->db->prepare('INSERT INTO password_reset_tokens (id,user_id,token_sha256,expires_at) VALUES (?,?,?,?)')
                        ->execute([Support::uuid(), $userId, hash('sha256', $token), $expires]);
                    $url = rtrim((string)$this->config['verification_url'], '/') . '#reset=' . rawurlencode($token);
                    EmailOutbox::enqueue($this->db, $this->config, $email, 'Reset your HOTICE password',
                        "Reset your password within 30 minutes by opening this link:\n\n$url\n\nIf you did not request this, ignore this message.", $expires);
                }
            }
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        // Same status and response for existing, unknown, and unverified users.
        $this->send(202, ['accepted' => true]);
    }

    private function completePasswordReset(): void
    {
        $b = Support::jsonInput(4096);
        $token = (string)($b['token'] ?? '');
        $password = (string)($b['password'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/D', $token)) throw new ApiError(400, 'Password reset link is invalid or expired.');
        if (strlen($password) < 12 || strlen($password) > 256) throw new ApiError(422, 'Password must be 12–256 bytes.');
        $this->db->beginTransaction();
        try {
            $q = $this->db->prepare('SELECT id,user_id FROM password_reset_tokens WHERE token_sha256=? AND used_at IS NULL AND expires_at>UTC_TIMESTAMP() LIMIT 1 FOR UPDATE');
            $q->execute([hash('sha256', $token)]);
            $row = $q->fetch();
            if (!$row) throw new ApiError(400, 'Password reset link is invalid or expired.');
            $this->db->prepare('UPDATE users SET password_hash=? WHERE id=?')
                ->execute([Support::passwordHash($password), $row['user_id']]);
            $this->db->prepare('UPDATE sessions SET revoked_at=UTC_TIMESTAMP() WHERE user_id=? AND revoked_at IS NULL')
                ->execute([$row['user_id']]);
            $this->db->prepare('UPDATE password_reset_tokens SET used_at=UTC_TIMESTAMP() WHERE user_id=? AND used_at IS NULL')
                ->execute([$row['user_id']]);
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        $this->send(200, ['passwordReset' => true, 'sessionsRevoked' => true]);
    }

    private function login(): void
    {
        $b = Support::jsonInput(8192);
        $email = Support::email((string) ($b['email'] ?? ''));
        $password = (string) ($b['password'] ?? '');
        $fingerprint = $this->throttle($email);
        $this->db->beginTransaction();
        try {
            // Lock the user row so an owner suspension cannot race a new session.
            $q = $this->db->prepare('SELECT id,email,password_hash,email_verified_at FROM users WHERE email=? LIMIT 1 FOR UPDATE');
            $q->execute([$email]);
            $user = $q->fetch();
            $state = null;
            if ($user) {
                $check = $this->db->prepare('SELECT disabled_at FROM user_admin_state WHERE user_id=?');
                $check->execute([$user['id']]);
                $state = $check->fetch();
            }
            if (!$user || !Support::passwordVerify($password, $user['password_hash']) ||
                ($state && $state['disabled_at'] !== null)) {
                $this->db->rollBack();
                $this->recordFailedLogin($fingerprint);
                throw new ApiError(401, 'Invalid email or password.');
            }
            if ($user['email_verified_at'] === null) {
                $this->db->rollBack();
                throw new ApiError(403, 'Verify your email before signing in.');
            }
            // Never clear the IP budget on a successful login: a single valid
            // account must not let attackers reset their IP-wide spray limit.
            $this->db->prepare('DELETE FROM login_attempts WHERE fingerprint=?')->execute([$fingerprint['email']]);
            // Preserve long legacy bcrypt password semantics on cPanel builds.
            if (Support::passwordNeedsRehash($user['password_hash']) && strlen($password) <= 72) {
                $this->db->prepare('UPDATE users SET password_hash=? WHERE id=?')
                    ->execute([Support::passwordHash($password), $user['id']]);
            }
            $token = bin2hex(random_bytes(32));
            $hours = max(1, min(168, (int) ($this->config['token_ttl_hours'] ?? 24)));
            $expires = gmdate('Y-m-d H:i:s', time() + $hours * 3600);
            $this->db->prepare('INSERT INTO sessions (id,user_id,token_sha256,expires_at) VALUES (?,?,?,?)')
                ->execute([Support::uuid(), $user['id'], hash('sha256', $token), $expires]);
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        $this->send(200, ['accessToken' => $token, 'tokenType' => 'Bearer',
            'expiresAt' => str_replace(' ', 'T', $expires) . 'Z']);
    }

    private function authenticate(): array
    {
        $auth = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
        if (!preg_match('/^Bearer ([a-fA-F0-9]{64})$/D', $auth, $m)) throw new ApiError(401, 'Authentication required.');
        $q = $this->db->prepare('SELECT s.id AS session_id,u.id,u.email FROM sessions s JOIN users u ON u.id=s.user_id LEFT JOIN user_admin_state uas ON uas.user_id=u.id WHERE s.token_sha256=? AND s.revoked_at IS NULL AND s.expires_at > UTC_TIMESTAMP() AND uas.disabled_at IS NULL LIMIT 1');
        $q->execute([hash('sha256', strtolower($m[1]))]);
        $user = $q->fetch();
        if (!$user) throw new ApiError(401, 'Session expired or revoked.');
        return $user;
    }

    /** Export a complete bounded server-side snapshot; device-local files are not uploaded or included. */
    private function exportAccount(string $user): void
    {
        $maxBytes = max(1048576, min(25 * 1024 * 1024, (int)($this->config['max_account_export_bytes'] ?? 8 * 1024 * 1024)));
        $this->db->beginTransaction(); // Keep a consistent account snapshot if deletion races this export.
        $projectBytes = $this->db->prepare('SELECT COALESCE(SUM(OCTET_LENGTH(document_json)),0) FROM cloud_projects WHERE user_id=?');
        $projectBytes->execute([$user]);
        $jobBytes = $this->db->prepare('SELECT COALESCE(SUM(OCTET_LENGTH(request_json)+COALESCE(OCTET_LENGTH(result_json),0)),0) FROM generation_jobs WHERE user_id=?');
        $jobBytes->execute([$user]);
        $fileCount = $this->db->prepare('SELECT COUNT(*) FROM cloud_files WHERE user_id=?');
        $fileCount->execute([$user]);
        if ((int)$projectBytes->fetchColumn() + (int)$jobBytes->fetchColumn() > $maxBytes || (int)$fileCount->fetchColumn() > 5000) {
            throw new ApiError(413, 'Account export exceeds the configured size limit. Contact HOTICE support before deletion.');
        }
        $profile = $this->db->prepare('SELECT id,email,email_verified_at,created_at FROM users WHERE id=?');
        $profile->execute([$user]);
        $account = $profile->fetch();
        if (!$account) throw new ApiError(404, 'Account not found.');

        $projects = $this->db->prepare('SELECT id,title,document_json,revision,updated_at,created_at FROM cloud_projects WHERE user_id=? ORDER BY created_at,id LIMIT 201');
        $projects->execute([$user]);
        $projectRows = $projects->fetchAll();
        if (count($projectRows) > 200) throw new ApiError(413, 'Account export exceeds the project limit. Contact HOTICE support before deletion.');
        $projectIds = array_column($projectRows, 'id');
        $files = [];
        if ($projectIds !== []) {
            $placeholders = implode(',', array_fill(0, count($projectIds), '?'));
            $fileQuery = $this->db->prepare("SELECT id,project_id,mime,byte_size,sha256,created_at FROM cloud_files WHERE user_id=? AND project_id IN ($placeholders) ORDER BY created_at,id");
            $fileQuery->execute(array_merge([$user], $projectIds));
            $files = $fileQuery->fetchAll();
        }
        $jobs = $this->db->prepare('SELECT id,quote_id,model_id,request_json,status,attempt_count,reserved_credits,actual_credits,result_json,error_code,created_at,updated_at,finished_at FROM generation_jobs WHERE user_id=? ORDER BY created_at,id LIMIT 501');
        $jobs->execute([$user]);
        $jobRows = $jobs->fetchAll();
        if (count($jobRows) > 500) throw new ApiError(413, 'Account export exceeds the job history limit. Contact HOTICE support before deletion.');
        $ledger = $this->db->prepare('SELECT event_key,event_type,delta,balance_after,created_at FROM credit_ledger WHERE user_id=? ORDER BY created_at,id LIMIT 2001');
        $ledger->execute([$user]);
        $ledgerRows = $ledger->fetchAll();
        if (count($ledgerRows) > 2000) throw new ApiError(413, 'Account export exceeds the credit history limit. Contact HOTICE support before deletion.');

        foreach ($projectRows as &$project) {
            $project['revision'] = (int)$project['revision'];
            $project['document'] = json_decode((string)$project['document_json'], false, 32, JSON_THROW_ON_ERROR);
        }
        unset($project);
        foreach ($jobRows as &$job) {
            $job['attempt_count'] = (int)$job['attempt_count'];
            $job['reserved_credits'] = (int)$job['reserved_credits'];
            $job['actual_credits'] = (int)$job['actual_credits'];
            $job['request'] = json_decode((string)$job['request_json'], false, 32, JSON_THROW_ON_ERROR);
            $job['result'] = $job['result_json'] === null ? null : json_decode((string)$job['result_json'], false, 32, JSON_THROW_ON_ERROR);
            unset($job['request_json'], $job['result_json']);
        }
        unset($job);
        foreach ($projectRows as &$project) unset($project['document_json']);
        unset($project);
        foreach ($files as &$file) $file['byte_size'] = (int)$file['byte_size'];
        unset($file);
        foreach ($ledgerRows as &$entry) {
            $entry['delta'] = (int)$entry['delta'];
            $entry['balance_after'] = (int)$entry['balance_after'];
        }
        unset($entry);
        $entitlement = $this->db->prepare('SELECT source,plan_code,quota_bytes,used_bytes,expires_at FROM cloud_entitlements WHERE user_id=?');
        $entitlement->execute([$user]);
        $entitlementData = $entitlement->fetch() ?: null;
        if ($entitlementData) {
            $entitlementData['quota_bytes'] = (int)$entitlementData['quota_bytes'];
            $entitlementData['used_bytes'] = (int)$entitlementData['used_bytes'];
        }
        $preferences = $this->accountPreferences($user);
        $balance = $this->db->prepare('SELECT balance FROM credit_accounts WHERE user_id=?');
        $balance->execute([$user]);
        $payload = ['format' => 'hotice-account-export-v1', 'exportedAt' => gmdate('Y-m-d\TH:i:s\Z'),
            'account' => $account, 'preferences' => $preferences, 'cloudEntitlement' => $entitlementData,
            'simulatedCreditBalance' => ($value = $balance->fetchColumn()) === false ? null : (int)$value,
            'cloudProjects' => $projectRows, 'cloudMediaMetadata' => $files,
            'generationJobs' => $jobRows, 'simulatedCreditLedger' => $ledgerRows,
            'includedMediaBytes' => false, 'deviceLocalProjectsIncluded' => false];
        $json = json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if (strlen($json) > $maxBytes) throw new ApiError(413, 'Account export exceeds the configured size limit. Contact HOTICE support before deletion.');
        $this->db->commit();
        header('Content-Type: application/json; charset=utf-8');
        header('Content-Disposition: attachment; filename="hotice-account-export.json"');
        http_response_code(200);
        echo $json;
    }

    /** Return the current account's supported cross-client presentation settings. */
    private function accountPreferences(string $user): array
    {
        $query = $this->db->prepare('SELECT theme_mode,accent,font,updated_at FROM user_preferences WHERE user_id=?');
        $query->execute([$user]);
        $row = $query->fetch();
        if (!$row) return ['themeMode' => 'dark', 'accent' => 'electric', 'font' => 'modern'];
        return ['themeMode' => $row['theme_mode'], 'accent' => $row['accent'],
            'font' => $row['font'], 'updatedAt' => $row['updated_at']];
    }

    private function getPreferences(string $user): void
    {
        $this->send(200, ['preferences' => $this->accountPreferences($user)]);
    }

    private function putPreferences(string $user): void
    {
        $body = Support::jsonInput(4096);
        $allowed = ['themeMode', 'accent', 'font'];
        if (array_diff(array_keys($body), $allowed) !== [] || array_diff($allowed, array_keys($body)) !== []) {
            throw new ApiError(422, 'Provide exactly themeMode, accent and font preferences.');
        }
        $allowedValues = [
            'themeMode' => ['system', 'light', 'dark'],
            'accent' => ['electric', 'ocean', 'ember', 'glacier', 'moss'],
            'font' => ['modern', 'editorial', 'technical'],
        ];
        foreach ($allowedValues as $field => $values) {
            if (!is_string($body[$field]) || !in_array($body[$field], $values, true)) {
                throw new ApiError(422, 'One or more account preferences are unsupported.');
            }
        }
        $this->db->prepare('INSERT INTO user_preferences(user_id,theme_mode,accent,font) VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE theme_mode=VALUES(theme_mode),accent=VALUES(accent),font=VALUES(font)')
            ->execute([$user, $body['themeMode'], $body['accent'], $body['font']]);
        $this->send(200, ['preferences' => $this->accountPreferences($user)]);
    }

    /** Permanently remove a user's account and queue private bytes for retryable purge. */
    private function deleteAccount(array $sessionUser): void
    {
        $body = Support::jsonInput(8192);
        if (($body['confirmation'] ?? null) !== 'DELETE' || !is_string($body['password'] ?? null)) {
            throw new ApiError(422, 'Enter DELETE and your current password to confirm account deletion.');
        }
        $fingerprints = $this->throttle((string)$sessionUser['email']);
        $this->db->beginTransaction();
        try {
            $q = $this->db->prepare('SELECT email,password_hash FROM users WHERE id=? FOR UPDATE');
            $q->execute([$sessionUser['id']]);
            $account = $q->fetch();
            if (!$account || !Support::passwordVerify($body['password'], (string)$account['password_hash'])) {
                $this->db->rollBack();
                $this->recordFailedLogin($fingerprints);
                throw new ApiError(403, 'Current password is incorrect.');
            }
            $storage = $this->privateDir(); // Verify before destructive DB changes; queue covers later unlink failures.
            $fileQuery = $this->db->prepare('SELECT storage_name FROM cloud_files WHERE user_id=? FOR UPDATE');
            $fileQuery->execute([$sessionUser['id']]);
            $names = array_column($fileQuery->fetchAll(), 'storage_name');
            $this->queuePrivateFiles($names);
            $emailHash = hash_hmac('sha256', 'email:' . strtolower((string)$account['email']), (string)$this->config['app_key']);
            $this->db->prepare('DELETE FROM login_attempts WHERE fingerprint=?')->execute([$emailHash]);
            $this->db->prepare('DELETE FROM email_outbox WHERE recipient=?')->execute([$account['email']]);
            // generation_jobs.quote_id is RESTRICT, so jobs must go before quotes.
            $this->db->prepare('DELETE FROM generation_jobs WHERE user_id=?')->execute([$sessionUser['id']]);
            $this->db->prepare('DELETE FROM job_quotes WHERE user_id=?')->execute([$sessionUser['id']]);
            $this->db->prepare('DELETE FROM users WHERE id=?')->execute([$sessionUser['id']]);
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        $purged = $this->purgePrivateFilesNow($names, $storage);
        $this->send(200, ['deleted' => true, 'queuedMediaFiles' => max(0, count($names) - $purged),
            'accountDataRemoved' => true]);
    }

    private function entitlement(string $user): ?array
    {
        $q = $this->db->prepare('SELECT source,plan_code,quota_bytes,used_bytes,expires_at FROM cloud_entitlements WHERE user_id=?');
        $q->execute([$user]);
        return $q->fetch() ?: null;
    }

    private function canWriteCloud(?array $e): bool
    {
        return $e && strtotime($e['expires_at'] . ' UTC') > time();
    }

    private function canReadCloud(?array $e): bool
    {
        // Grace period for export/restore, not uploads. No auto-purge in MVP.
        return $e && strtotime($e['expires_at'] . ' UTC') + 30 * 86400 > time();
    }

    private function requireCloud(string $user, bool $write): array
    {
        $ent = $this->entitlement($user);
        $valid = $write ? $this->canWriteCloud($ent) : $this->canReadCloud($ent);
        if (!$valid) throw new ApiError(403, 'Cloud access requires an active paid entitlement; contact support to export expired data.');
        return $ent;
    }

    private function getProject(string $user, string $id): void
    {
        $this->requireCloud($user, false);
        $q = $this->db->prepare('SELECT id,title,document_json,revision,updated_at FROM cloud_projects WHERE user_id=? AND id=?');
        $q->execute([$user, $id]);
        $p = $q->fetch();
        if (!$p) throw new ApiError(404, 'Project not found.');
        // Decode as objects to preserve {} vs [] throughout cloud sync.
        $p['document'] = json_decode($p['document_json'], false, 32, JSON_THROW_ON_ERROR);
        unset($p['document_json']);
        $p['revision'] = (int) $p['revision'];
        $files = $this->db->prepare('SELECT id,mime,byte_size,sha256,scan_status,created_at FROM cloud_files WHERE project_id=? AND user_id=? ORDER BY created_at DESC LIMIT 200');
        $files->execute([$id, $user]);
        $this->send(200, ['project' => $p, 'files' => $files->fetchAll()]);
    }

    private function putProject(string $user, string $id): void
    {
        $this->requireCloud($user, true);
        $b = Support::jsonInput((int) ($this->config['max_project_bytes'] ?? 131072) + 4096);
        $title = trim((string) ($b['title'] ?? ''));
        // A malformed UTF-8 title must be rejected as input, not handed
        // to MySQL as a server error; controls cannot appear in metadata.
        $titleLength = preg_match_all('/./us', $title);
        if ($title === '' || strlen($title) > 480 || $titleLength === false ||
            $titleLength > 120 || preg_match('/[\x00-\x1F\x7F]/', $title)) {
            throw new ApiError(422, 'Project title must be 1–120 readable characters.');
        }
        $revision = $b['expectedRevision'] ?? null;
        if (!is_int($revision) || $revision < 0) throw new ApiError(422, 'expectedRevision must be a nonnegative integer.');
        $document = Support::jsonString($b['document'] ?? null, (int) ($this->config['max_project_bytes'] ?? 131072));
        $this->db->beginTransaction();
        // Re-check entitlement within transaction (billing revocation race).
        $ent = $this->db->prepare('SELECT expires_at FROM cloud_entitlements WHERE user_id=? FOR UPDATE');
        $ent->execute([$user]);
        $currentEnt = $ent->fetch();
        if (!$this->canWriteCloud($currentEnt)) throw new ApiError(403, 'Cloud subscription expired.');
        $q = $this->db->prepare('SELECT revision,user_id FROM cloud_projects WHERE id=? FOR UPDATE');
        $q->execute([$id]);
        $row = $q->fetch();
        if ($row) {
            if ($row['user_id'] !== $user) throw new ApiError(404, 'Project not found.');
            if ((int) $row['revision'] !== $revision) throw new ApiError(409, 'Cloud version conflict. Fetch latest before retrying.');
            $next = $revision + 1;
            $this->db->prepare('UPDATE cloud_projects SET title=?,document_json=?,revision=? WHERE id=? AND user_id=?')
                ->execute([$title, $document, $next, $id, $user]);
        } else {
            if ($revision !== 0) throw new ApiError(409, 'Cloud version conflict; new projects require expectedRevision=0.');
            $count = $this->db->prepare('SELECT COUNT(*) FROM cloud_projects WHERE user_id=?');
            $count->execute([$user]);
            $maxProjects = max(1, min(1000, (int) ($this->config['max_cloud_projects'] ?? 100)));
            if ((int) $count->fetchColumn() >= $maxProjects) {
                throw new ApiError(413, 'Cloud project count limit reached.');
            }
            $next = 1;
            $this->db->prepare('INSERT INTO cloud_projects (id,user_id,title,document_json,revision) VALUES (?,?,?,?,1)')
                ->execute([$id, $user, $title, $document]);
        }
        $this->db->commit();
        $this->send(200, ['id' => $id, 'revision' => $next]);
    }

    private function deleteProject(string $user, string $id): void
    {
        $storage = $this->privateDir();
        $this->db->beginTransaction();
        // Deleting one's data stays available even after subscription expiration.
        $ent = $this->db->prepare('SELECT used_bytes FROM cloud_entitlements WHERE user_id=? FOR UPDATE');
        $ent->execute([$user]);
        $ent->fetch();
        $q = $this->db->prepare('SELECT id FROM cloud_projects WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$id, $user]);
        if (!$q->fetch()) throw new ApiError(404, 'Project not found.');
        $files = $this->db->prepare('SELECT storage_name,byte_size FROM cloud_files WHERE project_id=? AND user_id=? FOR UPDATE');
        $files->execute([$id, $user]);
        $owned = $files->fetchAll();
        $bytes = array_sum(array_column($owned, 'byte_size'));
        $names = array_column($owned, 'storage_name');
        $this->queuePrivateFiles($names);
        $this->db->prepare('DELETE FROM cloud_projects WHERE id=? AND user_id=?')->execute([$id, $user]);
        $this->db->prepare('UPDATE cloud_entitlements SET used_bytes=IF(used_bytes >= ?, used_bytes - ?, 0) WHERE user_id=?')
            ->execute([$bytes, $bytes, $user]);
        $this->db->commit();
        $purged = $this->purgePrivateFilesNow($names, $storage);
        $this->send(200, ['deleted' => true, 'queuedMediaFiles' => count($names) - $purged]);
    }

    private function uploadFile(string $user, string $project, string $fileId): void
    {
        $this->requireCloud($user, true);
        $max = max(1, min(20 * 1024 * 1024, (int) ($this->config['max_file_bytes'] ?? 20 * 1024 * 1024)));
        $length = filter_var($_SERVER['CONTENT_LENGTH'] ?? null, FILTER_VALIDATE_INT);
        if (!$length || $length < 1) throw new ApiError(411, 'Content-Length required.');
        if ($length > $max) throw new ApiError(413, 'Media upload exceeds shared-host limit.');
        $dir = $this->privateDir();
        $temp = tempnam($dir, 'upload-');
        if ($temp === false) throw new \RuntimeException('Cannot create private temporary file.');
        $bytes = 0;
        try {
            $input = fopen('php://input', 'rb');
            $output = fopen($temp, 'wb');
            if ($input === false || $output === false) throw new \RuntimeException('Media stream unavailable.');
            try {
                while (!feof($input)) {
                    $chunk = fread($input, 65536);
                    if ($chunk === false) throw new ApiError(400, 'Media stream failed.');
                    if ($chunk === '') break;
                    $bytes += strlen($chunk);
                    if ($bytes > $max) throw new ApiError(413, 'Media too large.');
                    if (fwrite($output, $chunk) !== strlen($chunk)) throw new \RuntimeException('Private storage write failed.');
                }
            } finally {
                fclose($input); fclose($output);
            }
            if ($bytes !== $length) throw new ApiError(400, 'Media upload length mismatch.');
            $mime = (new \finfo(FILEINFO_MIME_TYPE))->file($temp);
            $allowed = ['image/jpeg', 'image/png', 'image/webp', 'audio/mpeg', 'audio/x-wav',
                'audio/wav', 'audio/mp4', 'video/mp4', 'video/webm', 'audio/ogg'];
            if (!is_string($mime) || !in_array($mime, $allowed, true)) throw new ApiError(415, 'Unsupported media type.');
            $hash = hash_file('sha256', $temp);
            $name = bin2hex(random_bytes(32));
            $this->db->beginTransaction();
            $e = $this->db->prepare('SELECT quota_bytes,used_bytes,expires_at FROM cloud_entitlements WHERE user_id=? FOR UPDATE');
            $e->execute([$user]);
            $ent = $e->fetch();
            if (!$this->canWriteCloud($ent)) throw new ApiError(403, 'Cloud subscription expired.');
            if ((int) $ent['used_bytes'] + $bytes > (int) $ent['quota_bytes']) throw new ApiError(413, 'Cloud storage quota exceeded.');
            $p = $this->db->prepare('SELECT id FROM cloud_projects WHERE id=? AND user_id=? FOR UPDATE');
            $p->execute([$project, $user]);
            if (!$p->fetch()) throw new ApiError(404, 'Cloud project not found.');
            $exists = $this->db->prepare('SELECT id FROM cloud_files WHERE id=? FOR UPDATE');
            $exists->execute([$fileId]);
            if ($exists->fetch()) throw new ApiError(409, 'Media ID already exists.');
            $count = $this->db->prepare('SELECT COUNT(*) FROM cloud_files WHERE project_id=? AND user_id=?');
            $count->execute([$project, $user]);
            $maxFiles = max(1, min(2000, (int) ($this->config['max_files_per_project'] ?? 200)));
            if ((int) $count->fetchColumn() >= $maxFiles) {
                throw new ApiError(413, 'Cloud file count limit reached.');
            }
            if (!rename($temp, $dir . '/' . $name)) throw new \RuntimeException('Private storage unavailable.');
            $temp = '';
            try {
                $this->db->prepare('INSERT INTO cloud_files (id,project_id,user_id,storage_name,mime,byte_size,sha256) VALUES (?,?,?,?,?,?,?)')
                    ->execute([$fileId, $project, $user, $name, $mime, $bytes, $hash]);
                $this->db->prepare('UPDATE cloud_entitlements SET used_bytes=used_bytes+? WHERE user_id=?')
                    ->execute([$bytes, $user]);
                $this->db->commit();
            } catch (Throwable $e) {
                @unlink($dir . '/' . $name);
                throw $e;
            }
            $this->send(201, ['id' => $fileId, 'byteSize' => $bytes, 'sha256' => $hash, 'mime' => $mime, 'scanStatus' => 'pending']);
        } finally {
            if ($temp !== '' && is_file($temp)) @unlink($temp);
        }
    }

    private function downloadFile(string $user, string $id): void
    {
        $this->requireCloud($user, false);
        $q = $this->db->prepare('SELECT storage_name,mime,byte_size,scan_status FROM cloud_files WHERE id=? AND user_id=?');
        $q->execute([$id, $user]);
        $file = $q->fetch();
        if (!$file) throw new ApiError(404, 'Media not found.');
        if ($file['scan_status'] !== 'clean') {
            throw new ApiError(423, $file['scan_status'] === 'blocked'
                ? 'Media was rejected by the security scanner.'
                : 'Media is unavailable until its security scan is complete.');
        }
        $name = $file['storage_name'];
        if (!Support::secureFileName($name)) throw new \RuntimeException('Invalid stored file path.');
        $path = $this->privateDir() . '/' . $name;
        if (!is_file($path) || !is_readable($path)) throw new ApiError(404, 'Stored media unavailable.');
        header('Content-Type: ' . $file['mime']);
        header('Content-Disposition: attachment; filename="hotice-media-' . $id . '"');
        header('Content-Length: ' . (int) $file['byte_size']);
        readfile($path);
    }

    private function deleteFile(string $user, string $id): void
    {
        $storage = $this->privateDir();
        $this->db->beginTransaction();
        $e = $this->db->prepare('SELECT used_bytes FROM cloud_entitlements WHERE user_id=? FOR UPDATE');
        $e->execute([$user]);
        $e->fetch();
        $q = $this->db->prepare('SELECT storage_name,byte_size FROM cloud_files WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$id, $user]);
        $file = $q->fetch();
        if (!$file) throw new ApiError(404, 'Media not found.');
        $names = [(string)$file['storage_name']];
        $this->queuePrivateFiles($names);
        $this->db->prepare('DELETE FROM cloud_files WHERE id=? AND user_id=?')->execute([$id, $user]);
        $this->db->prepare('UPDATE cloud_entitlements SET used_bytes=IF(used_bytes >= ?, used_bytes - ?, 0) WHERE user_id=?')
            ->execute([(int) $file['byte_size'], (int) $file['byte_size'], $user]);
        $this->db->commit();
        $purged = $this->purgePrivateFilesNow($names, $storage);
        $this->send(200, ['deleted' => true, 'queuedMediaFiles' => count($names) - $purged]);
    }

    /** @param list<string> $names */
    private function queuePrivateFiles(array $names): void
    {
        $q = $this->db->prepare('INSERT IGNORE INTO private_media_deletion_queue (storage_name) VALUES (?)');
        foreach ($names as $name) {
            if (!Support::secureFileName($name)) throw new \RuntimeException('Invalid stored file path.');
            $q->execute([$name]);
        }
    }

    /** @param list<string> $names */
    private function purgePrivateFilesNow(array $names, string $storage): int
    {
        $purged = 0;
        foreach ($names as $name) {
            $path = $storage . '/' . $name;
            $removed = !file_exists($path) && !is_link($path);
            if (!$removed && (is_file($path) || is_link($path))) $removed = @unlink($path);
            if ($removed) {
                $this->db->prepare('DELETE FROM private_media_deletion_queue WHERE storage_name=?')->execute([$name]);
                $purged++;
            }
        }
        return $purged;
    }

    private function privateDir(): string
    {
        $path = (string) ($this->config['storage_path'] ?? '');
        if ($path === '' || !is_dir($path) || !is_writable($path)) throw new \RuntimeException('Private media directory missing or not writable.');
        // The runtime DOCUMENT_ROOT is authoritative; the configured cPanel
        // root adds protection against alternate domains and aliases.
        $roots = [dirname(__DIR__) . '/public'];
        $documentRoot = trim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''));
        if ($documentRoot !== '') $roots[] = $documentRoot;
        $configuredRoot = trim((string) ($this->config['public_webroot_path'] ?? ''));
        if ($configuredRoot !== '') $roots[] = $configuredRoot;
        return Support::assertPrivateStorage($path, $roots);
    }
}

