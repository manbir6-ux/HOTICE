<?php
declare(strict_types=1);

namespace Hotice;

use PDO;
use Throwable;

require_once __DIR__ . '/Support.php';

final class App
{
    private PDO $db;

    public function __construct(private readonly array $config)
    {
        if (!extension_loaded('pdo_mysql') || !extension_loaded('fileinfo')) {
            throw new \RuntimeException('Required PHP extensions are unavailable.');
        }
        if (!preg_match('/^[a-f0-9]{64}$/iD', (string) ($config['app_key'] ?? ''))) {
            throw new \RuntimeException('Server app_key must be a unique 64-character hex secret.');
        }
        $dsn = (string) $config['db']['dsn'];
        $this->db = new PDO($dsn, (string) $config['db']['user'],
            (string) $config['db']['password'], [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
    }

    public function database(): PDO { return $this->db; }

    public function run(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('Cache-Control: no-store, max-age=0');
        header('Referrer-Policy: no-referrer');
        $requestId = bin2hex(random_bytes(8));
        header('X-Request-ID: ' . $requestId);
        try {
            if (($this->config['require_https'] ?? true) && !$this->https()) {
                throw new ApiError(426, 'HTTPS is required.');
            }
            $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
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
                $this->send(200, [
                    'user' => ['id' => $user['id'], 'email' => $user['email']],
                    'cloud' => ['active' => $this->canWriteCloud($e),
                        'readable' => $this->canReadCloud($e),
                        'plan' => $e['plan_code'] ?? null,
                        'quotaBytes' => isset($e['quota_bytes']) ? (int) $e['quota_bytes'] : 0,
                        'usedBytes' => isset($e['used_bytes']) ? (int) $e['used_bytes'] : 0,
                        'expiresAt' => $e['expires_at'] ?? null],
                ]); return;
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
        // Use a generic response: do not disclose whether email is registered.
        $q = $this->db->prepare('INSERT INTO users (id,email,password_hash) VALUES (?,?,?)');
        try {
            $q->execute([Support::uuid(), $email, password_hash($password, PASSWORD_DEFAULT)]);
        } catch (\PDOException $e) {
            if ($e->getCode() !== '23000') throw $e;
            $this->recordFailedLogin($f);
            throw new ApiError(409, 'Account registration unavailable.');
        }
        $this->send(201, ['registered' => true, 'note' => 'No cloud entitlement activated.']);
    }

    private function login(): void
    {
        $b = Support::jsonInput(8192);
        $email = Support::email((string) ($b['email'] ?? ''));
        $password = (string) ($b['password'] ?? '');
        $fingerprint = $this->throttle($email);
        $q = $this->db->prepare('SELECT id,email,password_hash FROM users WHERE email=? LIMIT 1');
        $q->execute([$email]);
        $user = $q->fetch();
        if (!$user || !password_verify($password, $user['password_hash'])) {
            $this->recordFailedLogin($fingerprint);
            throw new ApiError(401, 'Invalid email or password.');
        }
        // Never clear the IP budget on a successful login: a single valid
        // account must not let attackers reset their IP-wide spray limit.
        $this->db->prepare('DELETE FROM login_attempts WHERE fingerprint=?')->execute([$fingerprint['email']]);
        if (password_needs_rehash($user['password_hash'], PASSWORD_DEFAULT)) {
            $this->db->prepare('UPDATE users SET password_hash=? WHERE id=?')
                ->execute([password_hash($password, PASSWORD_DEFAULT), $user['id']]);
        }
        $token = bin2hex(random_bytes(32));
        $hours = max(1, min(168, (int) ($this->config['token_ttl_hours'] ?? 24)));
        $expires = gmdate('Y-m-d H:i:s', time() + $hours * 3600);
        $this->db->prepare('INSERT INTO sessions (id,user_id,token_sha256,expires_at) VALUES (?,?,?,?)')
            ->execute([Support::uuid(), $user['id'], hash('sha256', $token), $expires]);
        $this->send(200, ['accessToken' => $token, 'tokenType' => 'Bearer',
            'expiresAt' => str_replace(' ', 'T', $expires) . 'Z']);
    }

    private function authenticate(): array
    {
        $auth = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
        if (!preg_match('/^Bearer ([a-fA-F0-9]{64})$/D', $auth, $m)) throw new ApiError(401, 'Authentication required.');
        $q = $this->db->prepare('SELECT s.id AS session_id,u.id,u.email FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_sha256=? AND s.revoked_at IS NULL AND s.expires_at > UTC_TIMESTAMP() LIMIT 1');
        $q->execute([hash('sha256', strtolower($m[1]))]);
        $user = $q->fetch();
        if (!$user) throw new ApiError(401, 'Session expired or revoked.');
        return $user;
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
        $p['document'] = json_decode($p['document_json'], true, 32, JSON_THROW_ON_ERROR);
        unset($p['document_json']);
        $p['revision'] = (int) $p['revision'];
        $files = $this->db->prepare('SELECT id,mime,byte_size,sha256,created_at FROM cloud_files WHERE project_id=? AND user_id=? ORDER BY created_at DESC LIMIT 200');
        $files->execute([$id, $user]);
        $this->send(200, ['project' => $p, 'files' => $files->fetchAll()]);
    }

    private function putProject(string $user, string $id): void
    {
        $this->requireCloud($user, true);
        $b = Support::jsonInput((int) ($this->config['max_project_bytes'] ?? 131072) + 4096);
        $title = trim((string) ($b['title'] ?? ''));
        if ($title === '' || strlen($title) > 480 || preg_match_all('/./us', $title) > 120) throw new ApiError(422, 'Project title must be 1–120 characters.');
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
        $this->db->prepare('DELETE FROM cloud_projects WHERE id=? AND user_id=?')->execute([$id, $user]);
        $this->db->prepare('UPDATE cloud_entitlements SET used_bytes=IF(used_bytes >= ?, used_bytes - ?, 0) WHERE user_id=?')
            ->execute([$bytes, $bytes, $user]);
        $this->db->commit();
        foreach ($owned as $file) $this->removePrivateFile((string) $file['storage_name']);
        $this->send(200, ['deleted' => true]);
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
            $this->send(201, ['id' => $fileId, 'byteSize' => $bytes, 'sha256' => $hash, 'mime' => $mime]);
        } finally {
            if ($temp !== '' && is_file($temp)) @unlink($temp);
        }
    }

    private function downloadFile(string $user, string $id): void
    {
        $this->requireCloud($user, false);
        $q = $this->db->prepare('SELECT storage_name,mime,byte_size FROM cloud_files WHERE id=? AND user_id=?');
        $q->execute([$id, $user]);
        $file = $q->fetch();
        if (!$file) throw new ApiError(404, 'Media not found.');
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
        $this->db->beginTransaction();
        $e = $this->db->prepare('SELECT used_bytes FROM cloud_entitlements WHERE user_id=? FOR UPDATE');
        $e->execute([$user]);
        $e->fetch();
        $q = $this->db->prepare('SELECT storage_name,byte_size FROM cloud_files WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$id, $user]);
        $file = $q->fetch();
        if (!$file) throw new ApiError(404, 'Media not found.');
        $this->db->prepare('DELETE FROM cloud_files WHERE id=? AND user_id=?')->execute([$id, $user]);
        $this->db->prepare('UPDATE cloud_entitlements SET used_bytes=IF(used_bytes >= ?, used_bytes - ?, 0) WHERE user_id=?')
            ->execute([(int) $file['byte_size'], (int) $file['byte_size'], $user]);
        $this->db->commit();
        $this->removePrivateFile((string) $file['storage_name']);
        $this->send(200, ['deleted' => true]);
    }

    private function removePrivateFile(string $name): void
    {
        if (Support::secureFileName($name)) @unlink($this->privateDir() . '/' . $name);
    }

    private function privateDir(): string
    {
        $path = (string) ($this->config['storage_path'] ?? '');
        $realPublic = realpath(dirname(__DIR__) . '/public');
        if ($path === '' || !is_dir($path) || !is_writable($path)) throw new \RuntimeException('Private media directory missing or not writable.');
        $real = realpath($path);
        if ($real === false || $realPublic === false) {
            throw new \RuntimeException('Private storage path cannot be verified.');
        }
        // The PHP app may be installed under public_html/API/public. Checking
        // only backend/public misses public_html itself and can expose backups.
        // Fail closed if storage is inside OR encloses either web root.
        $roots = [$realPublic];
        $documentRoot = realpath((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''));
        if ($documentRoot !== false) $roots[] = $documentRoot;
        foreach (array_unique($roots) as $root) {
            if ($real === $root || str_starts_with($real . '/', $root . '/')
                || str_starts_with($root . '/', $real . '/')) {
                throw new \RuntimeException('Private storage must be outside all public web roots.');
            }
        }
        return $real;
    }
}
