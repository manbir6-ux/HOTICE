<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/src/App.php';
require_once dirname(__DIR__) . '/src/AdminSecurity.php';
require_once dirname(__DIR__) . '/src/FeatureFlags.php';

use Hotice\AdminSecurity;
use Hotice\App;
use Hotice\FeatureFlags;
use Hotice\Support;

final class OwnerPanelError extends RuntimeException {}

function h(string $value): string { return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
function redirectAdmin(): never { header('Location: /admin.php', true, 303); exit; }
function adminAudit(PDO $db, ?string $admin, string $event, ?string $type = null, ?string $id = null): void
{
    $db->prepare('INSERT INTO admin_audit_log(admin_id,event_code,target_type,target_id) VALUES(?,?,?,?)')
        ->execute([$admin, $event, $type, $id]);
}

header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
header('Cache-Control: no-store, max-age=0');
header('Referrer-Policy: no-referrer');
header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
$https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (int) ($_SERVER['SERVER_PORT'] ?? 0) === 443;
if (!$https) { http_response_code(426); exit('HTTPS is required.'); }
header('Strict-Transport-Security: max-age=31536000');
if (!extension_loaded('openssl')) { http_response_code(503); exit('Owner panel unavailable.'); }

ini_set('session.use_strict_mode', '1');
ini_set('session.use_only_cookies', '1');
ini_set('session.cookie_httponly', '1');
ini_set('session.cookie_secure', '1');
ini_set('session.cookie_samesite', 'Strict');
session_name('HOTICE_OWNER');
session_set_cookie_params(['lifetime' => 0, 'path' => '/', 'secure' => true, 'httponly' => true, 'samesite' => 'Strict']);
session_start();
if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(32));
$message = '';
$error = '';
if (isset($_SESSION['flash']) && is_string($_SESSION['flash'])) {
    $message = $_SESSION['flash'];
    unset($_SESSION['flash']);
}

try {
    $configPath = dirname(__DIR__) . '/config.php';
    if (!is_file($configPath)) throw new OwnerPanelError('Unavailable');
    $config = require $configPath;
    if (!is_array($config)) throw new RuntimeException('Unavailable');
    $app = new App($config);
    $db = $app->database();
    $appKey = (string) ($config['app_key'] ?? '');
    $providers = ['openai' => 'OpenAI', 'google' => 'Google', 'runway' => 'Runway', 'elevenlabs' => 'ElevenLabs'];

    $adminId = isset($_SESSION['admin_id']) && is_string($_SESSION['admin_id']) ? $_SESSION['admin_id'] : null;
    $owner = null;
    if ($adminId !== null) {
        $q = $db->prepare('SELECT id,email FROM admin_accounts WHERE id=? AND disabled_at IS NULL');
        $q->execute([$adminId]);
        $owner = $q->fetch() ?: null;
        if (!$owner) { $_SESSION = []; session_regenerate_id(true); $_SESSION['csrf'] = bin2hex(random_bytes(32)); $adminId = null; }
        elseif (!isset($_SESSION['auth_at'], $_SESSION['last_seen']) ||
            time() - (int)$_SESSION['last_seen'] > 1800 || time() - (int)$_SESSION['auth_at'] > 43200) {
            $_SESSION = []; session_regenerate_id(true); $_SESSION['csrf'] = bin2hex(random_bytes(32)); $adminId = null; $owner = null;
        } else {
            $_SESSION['last_seen'] = time();
        }
    }

    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
        $postedCsrf = (string) ($_POST['csrf'] ?? '');
        if (!hash_equals((string) $_SESSION['csrf'], $postedCsrf)) {
            http_response_code(400); throw new OwnerPanelError('Refresh the page and try again.');
        }
        $action = (string) ($_POST['action'] ?? '');
        if ($owner === null && $action === 'login') {
            $email = strtolower(trim((string) ($_POST['email'] ?? '')));
            if (strlen($email) > 254 || !filter_var($email, FILTER_VALIDATE_EMAIL)) $email = 'invalid';
            $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
            $fingerprints = [
                hash_hmac('sha256', 'owner-email:' . $email, $appKey),
                hash_hmac('sha256', 'owner-ip:' . $ip, $appKey),
            ];
            $count = $db->prepare('SELECT COUNT(*) FROM admin_login_attempts WHERE fingerprint=? AND occurred_at>DATE_SUB(UTC_TIMESTAMP(),INTERVAL 15 MINUTE)');
            foreach ([$fingerprints[0] => 8, $fingerprints[1] => 30] as $fp => $limit) {
                $count->execute([$fp]);
                if ((int) $count->fetchColumn() >= $limit) throw new OwnerPanelError('Too many attempts. Try again later.');
            }
            $q = $db->prepare('SELECT id,email,password_hash,totp_secret_ciphertext,totp_nonce,totp_tag FROM admin_accounts WHERE email=? AND disabled_at IS NULL LIMIT 1');
            $q->execute([$email]);
            $candidate = $q->fetch();
            $valid = false;
            if ($candidate && Support::passwordVerify((string) ($_POST['password'] ?? ''), $candidate['password_hash'])) {
                try {
                    $secret = AdminSecurity::decryptTotpSecret($candidate['totp_secret_ciphertext'],
                        $candidate['totp_nonce'], $candidate['totp_tag'], $appKey);
                    $valid = AdminSecurity::verifyTotp($secret, trim((string) ($_POST['totp'] ?? '')));
                } catch (Throwable) { $valid = false; }
            }
            if (!$valid) {
                $ins = $db->prepare('INSERT INTO admin_login_attempts(fingerprint,occurred_at) VALUES(?,UTC_TIMESTAMP())');
                foreach ($fingerprints as $fp) $ins->execute([$fp]);
                adminAudit($db, null, 'owner_login_failed');
                throw new OwnerPanelError('Sign-in failed. Check your details and authenticator code.');
            }
            $ownerPassword = (string) ($_POST['password'] ?? '');
            if (Support::passwordNeedsRehash($candidate['password_hash']) && strlen($ownerPassword) <= 72) {
                $db->prepare('UPDATE admin_accounts SET password_hash=? WHERE id=?')
                    ->execute([Support::passwordHash($ownerPassword), $candidate['id']]);
            }
            $db->prepare('DELETE FROM admin_login_attempts WHERE fingerprint=?')->execute([$fingerprints[0]]);
            session_regenerate_id(true);
            $_SESSION['admin_id'] = $candidate['id'];
            $_SESSION['auth_at'] = time();
            $_SESSION['last_seen'] = time();
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
            $db->prepare('UPDATE admin_accounts SET last_login_at=UTC_TIMESTAMP() WHERE id=?')->execute([$candidate['id']]);
            adminAudit($db, $candidate['id'], 'owner_login');
            redirectAdmin();
        }
        if ($owner === null) throw new OwnerPanelError('Sign-in is required.');
        if ($action === 'logout') {
            adminAudit($db, $adminId, 'owner_logout');
            $_SESSION = [];
            if (ini_get('session.use_cookies')) {
                $params = session_get_cookie_params();
                setcookie(session_name(), '', ['expires' => time() - 3600, 'path' => $params['path'],
                    'secure' => true, 'httponly' => true, 'samesite' => 'Strict']);
            }
            session_destroy(); redirectAdmin();
        }
        if ($action === 'set_feature_flag') {
            $flag = (string)($_POST['flag_key'] ?? '');
            $enabled = (string)($_POST['enabled'] ?? '');
            if ($flag !== FeatureFlags::MOCK_GENERATION || !in_array($enabled, ['0', '1'], true)) {
                throw new OwnerPanelError('Feature flag selection is invalid.');
            }
            if ($enabled === '1' && ($config['mock_jobs_enabled'] ?? false) !== true) {
                throw new OwnerPanelError('The server configuration keeps mock generation disabled.');
            }
            $db->beginTransaction();
            try {
                $db->prepare('INSERT INTO system_feature_flags(flag_key,enabled,updated_by) VALUES(?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),updated_by=VALUES(updated_by)')
                    ->execute([$flag, (int)$enabled, $adminId]);
                adminAudit($db, $adminId, 'feature_flag_changed', 'feature', $flag . ':' . ($enabled === '1' ? 'enabled' : 'disabled'));
                $db->commit();
            } catch (Throwable $e) {
                if ($db->inTransaction()) $db->rollBack();
                throw $e;
            }
            $message = $enabled === '1'
                ? 'Mock generation dry run enabled. No provider calls or videos are created.'
                : 'Mock generation disabled. Submission and worker processing are paused; queued jobs can still be reviewed or cancelled.';
        } elseif ($action === 'save_provider' || $action === 'delete_provider') {
            $provider = (string) ($_POST['provider'] ?? '');
            if (!isset($providers[$provider])) throw new OwnerPanelError('Unknown provider.');
            if ($action === 'delete_provider') {
                $db->prepare('DELETE FROM provider_secrets WHERE provider=?')->execute([$provider]);
                adminAudit($db, $adminId, 'provider_secret_deleted', 'provider', $provider);
                $message = $providers[$provider] . ' key removed.';
            } else {
                $secret = trim((string) ($_POST['secret'] ?? ''));
                if ($secret === '' || strlen($secret) > 4096 || preg_match('/[\r\n\x00]/', $secret)) {
                    throw new OwnerPanelError('Enter a single-line key up to 4096 bytes.');
                }
                $sealed = AdminSecurity::encryptProviderKey($provider, $secret, $appKey);
                $stmt = $db->prepare('INSERT INTO provider_secrets(provider,ciphertext,nonce,tag,updated_by) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE ciphertext=VALUES(ciphertext),nonce=VALUES(nonce),tag=VALUES(tag),updated_by=VALUES(updated_by)');
                $stmt->execute([$provider, $sealed['ciphertext'], $sealed['nonce'], $sealed['tag'], $adminId]);
                adminAudit($db, $adminId, 'provider_secret_saved', 'provider', $provider);
                $message = $providers[$provider] . ' key saved encrypted.';
            }
        } elseif ($action === 'disable_user' || $action === 'enable_user') {
            $target = (string) ($_POST['user_id'] ?? '');
            if (!\Hotice\Support::isUuid($target)) throw new OwnerPanelError('User selection is invalid.');
            $db->beginTransaction();
            $lock = $db->prepare('SELECT id FROM users WHERE id=? FOR UPDATE');
            $lock->execute([$target]);
            if (!$lock->fetch()) { $db->rollBack(); throw new OwnerPanelError('User was not found.'); }
            if ($action === 'disable_user') {
                $db->prepare('INSERT INTO user_admin_state(user_id,disabled_at,updated_by) VALUES(?,UTC_TIMESTAMP(),?) ON DUPLICATE KEY UPDATE disabled_at=UTC_TIMESTAMP(),updated_by=VALUES(updated_by)')
                    ->execute([$target, $adminId]);
                $db->prepare('UPDATE sessions SET revoked_at=UTC_TIMESTAMP() WHERE user_id=? AND revoked_at IS NULL')
                    ->execute([$target]);
                adminAudit($db, $adminId, 'user_access_disabled', 'user', $target);
                $message = 'User access disabled and active sessions revoked.';
            } else {
                $db->prepare('INSERT INTO user_admin_state(user_id,disabled_at,updated_by) VALUES(?,NULL,?) ON DUPLICATE KEY UPDATE disabled_at=NULL,updated_by=VALUES(updated_by)')
                    ->execute([$target, $adminId]);
                adminAudit($db, $adminId, 'user_access_enabled', 'user', $target);
                $message = 'User access enabled. The user must sign in again.';
            }
            $db->commit();
        } elseif ($action === 'grant_cloud_trial' || $action === 'revoke_cloud_trial') {
            $target = (string) ($_POST['user_id'] ?? '');
            if (!\Hotice\Support::isUuid($target)) throw new OwnerPanelError('User selection is invalid.');
            $db->beginTransaction();
            $lock = $db->prepare('SELECT id FROM users WHERE id=? FOR UPDATE');
            $lock->execute([$target]);
            if (!$lock->fetch()) { $db->rollBack(); throw new OwnerPanelError('User was not found.'); }
            $currentQuery = $db->prepare('SELECT source FROM cloud_entitlements WHERE user_id=? FOR UPDATE');
            $currentQuery->execute([$target]);
            $currentSource = $currentQuery->fetchColumn();
            if ($action === 'grant_cloud_trial') {
                $mib = filter_var($_POST['quota_mib'] ?? null, FILTER_VALIDATE_INT);
                $days = filter_var($_POST['days'] ?? null, FILTER_VALIDATE_INT);
                if (!$mib || $mib < 1 || $mib > 1024 || !$days || $days < 1 || $days > 60) {
                    $db->rollBack(); throw new OwnerPanelError('Trial limit is 1–1024 MiB for 1–60 days.');
                }
                if ($currentSource !== false && $currentSource !== 'admin_trial') {
                    $db->rollBack(); throw new OwnerPanelError('Paid cloud access is controlled by verified billing.');
                }
                $expires = gmdate('Y-m-d H:i:s', time() + $days * 86400);
                if ($currentSource === 'admin_trial') {
                    $db->prepare("UPDATE cloud_entitlements SET plan_code='trial',quota_bytes=?,expires_at=? WHERE user_id=? AND source='admin_trial'")
                        ->execute([$mib * 1048576, $expires, $target]);
                } else {
                    $db->prepare("INSERT INTO cloud_entitlements(user_id,source,plan_code,quota_bytes,used_bytes,expires_at) VALUES(?,'admin_trial','trial',?,0,?)")
                        ->execute([$target, $mib * 1048576, $expires]);
                }
                adminAudit($db, $adminId, 'cloud_trial_granted', 'user', $target);
                $message = 'Admin test cloud trial granted. This is not a payment or subscription.';
            } else {
                if ($currentSource !== 'admin_trial') {
                    $db->rollBack(); throw new OwnerPanelError('Only an admin test trial can be ended here.');
                }
                $db->prepare("UPDATE cloud_entitlements SET expires_at=UTC_TIMESTAMP() WHERE user_id=? AND source='admin_trial'")
                    ->execute([$target]);
                adminAudit($db, $adminId, 'cloud_trial_ended', 'user', $target);
                $message = 'Admin test trial ended. Read-only export grace remains available for 30 days.';
            }
            $db->commit();
        } else {
            throw new OwnerPanelError('Action unavailable.');
        }
        $_SESSION['flash'] = $message;
        redirectAdmin();
    }
} catch (Throwable $e) {
    if (!isset($error) || $error === '') $error = $e instanceof OwnerPanelError && $e->getMessage() !== 'Unavailable'
        ? $e->getMessage() : 'Owner panel is temporarily unavailable.';
    if (!($e instanceof OwnerPanelError) || $e->getMessage() === 'Unavailable') {
        error_log('HOTICE owner panel request failed (' . get_class($e) . ')');
    }
}

function csrfInput(): string { return '<input type="hidden" name="csrf" value="' . h((string) ($_SESSION['csrf'] ?? '')) . '">'; }
?><!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>HOTICE owner console</title>
<style>
:root{color-scheme:dark;--bg:#0b1220;--panel:#141e30;--text:#f4f7ff;--muted:#a6b2c8;--line:#2d3a50;--accent:#54c9e8;--bad:#ff9c9c}*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at 20% 0,#182946,var(--bg) 55%);color:var(--text);font:16px/1.5 system-ui,-apple-system,Segoe UI,sans-serif}.wrap{max-width:1040px;margin:0 auto;padding:28px 20px 60px}.top,.row{display:flex;align-items:center;justify-content:space-between;gap:16px}.brand{font-size:1.2rem;font-weight:800;letter-spacing:.08em}.brand span{color:var(--accent)}h1{font-size:clamp(1.8rem,4vw,2.6rem);margin:28px 0 4px}h2{margin:0 0 6px}.muted{color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(255px,1fr));gap:16px;margin:20px 0}.card{background:color-mix(in srgb,var(--panel),transparent 5%);border:1px solid var(--line);border-radius:18px;padding:20px;box-shadow:0 15px 40px #0002}.status{display:inline-flex;align-items:center;border:1px solid #416b61;color:#a7f2d3;border-radius:99px;padding:3px 10px;font-size:.82rem}.status.off{border-color:#655b3a;color:#ffdda0}label{display:block;font-weight:650;margin:13px 0 6px}input{width:100%;padding:12px;border-radius:10px;border:1px solid var(--line);background:#0c1422;color:var(--text);font:inherit}button{border:0;border-radius:10px;padding:11px 15px;background:linear-gradient(100deg,#52cbe8,#9273fa);color:#08111d;font-weight:750;font:inherit;cursor:pointer}.secondary{background:#233047;color:var(--text);border:1px solid var(--line)}.danger{background:#44252c;color:#ffd1d1;border:1px solid #78444d}.notice{padding:12px 15px;border-radius:12px;background:#163245;border:1px solid #25546b}.error{background:#3e222a;border-color:#76424b;color:var(--bad)}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:9px 6px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:600}.narrow{max-width:460px;margin:6vh auto}.small{font-size:.88rem}@media(max-width:560px){.wrap{padding:18px 14px 40px}.top{align-items:flex-start}.row{align-items:flex-start;flex-direction:column}td,th{font-size:.9rem}}
</style></head><body><main class="wrap">
<div class="top"><div class="brand"><span>◆</span> HOTICE <span class="muted">OWNER</span></div>
<?php if (!empty($owner)): ?><form method="post"><?=csrfInput()?><input type="hidden" name="action" value="logout"><button class="secondary" type="submit">Sign out</button></form><?php endif; ?></div>
<?php if ($error !== ''): ?><p class="notice error" role="alert"><?=h($error)?></p><?php endif; ?>
<?php if ($message !== ''): ?><p class="notice" role="status"><?=h($message)?></p><?php endif; ?>
<?php if (empty($owner)): ?>
<section class="card narrow"><p class="muted">Private operations access</p><h1>Owner sign in</h1><p class="muted">Enter your owner password and current authenticator code.</p>
<form method="post" autocomplete="on"><?=csrfInput()?><input type="hidden" name="action" value="login">
<label for="email">Owner email</label><input id="email" name="email" type="email" autocomplete="username" maxlength="254" required>
<label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password" maxlength="256" required>
<label for="totp">Authenticator code</label><input id="totp" name="totp" inputmode="numeric" pattern="[0-9]{6}" autocomplete="one-time-code" maxlength="6" required>
<p><button type="submit">Sign in securely</button></p></form><p class="muted small">HTTPS, an owner-only account, CSRF protection and authenticator verification are required.</p></section>
<?php else: ?>
<h1>Operations overview</h1><p class="muted">Signed in as <?=h((string)$owner['email'])?>. Provider credentials are encrypted at rest and never shown again.</p>
<?php
$mockServerAllows = ($config['mock_jobs_enabled'] ?? false) === true;
$mockGenerationEnabled = FeatureFlags::mockGenerationEnabled($db, $config);
?>
<section><h2>Feature flags</h2><div class="grid"><article class="card">
<div class="row"><h2>Mock generation dry run</h2><span class="status <?=$mockGenerationEnabled?'':'off'?>"><?=$mockGenerationEnabled?'Enabled':'Disabled'?></span></div>
<p class="muted small">This controls only the mock quote/job flow. It never contacts a provider, creates media, or charges money. The private server configuration remains the master gate.</p>
<form method="post"><?=csrfInput()?><input type="hidden" name="action" value="set_feature_flag"><input type="hidden" name="flag_key" value="<?=h(FeatureFlags::MOCK_GENERATION)?>">
<label for="mock-generation-enabled">Availability</label><select id="mock-generation-enabled" name="enabled"><option value="1" <?=$mockGenerationEnabled?'selected':''?> <?=$mockServerAllows?'':'disabled'?>>Enabled for dry runs</option><option value="0" <?=$mockGenerationEnabled?'':'selected'?>>Disabled</option></select>
<p><button type="submit">Save feature flag</button></p>
<?php if (!$mockServerAllows): ?><p class="muted small">The private server configuration blocks enabling. Keep this owner override disabled before changing that master setting.</p><?php endif; ?></form>
</article></div></section>
<?php if (!empty($providers)): ?><section><h2>Provider credentials</h2><p class="muted">Saving a key replaces the encrypted server-side value. Blank fields never reveal existing keys.</p><div class="grid">
<?php foreach ($providers as $provider => $label): $q=$db->prepare('SELECT updated_at FROM provider_secrets WHERE provider=?');$q->execute([$provider]);$saved=$q->fetch(); ?>
<article class="card"><div class="row"><h2><?=h($label)?></h2><span class="status <?=$saved?'':'off'?>"><?=$saved?'Configured':'Not configured'?></span></div>
<?php if ($saved): ?><p class="muted small">Last updated <?=h((string)$saved['updated_at'])?></p><?php endif; ?>
<form method="post" autocomplete="off"><?=csrfInput()?><input type="hidden" name="action" value="save_provider"><input type="hidden" name="provider" value="<?=h($provider)?>">
<label for="key-<?=h($provider)?>">New API key</label><input id="key-<?=h($provider)?>" name="secret" type="password" autocomplete="new-password" maxlength="4096" placeholder="Paste to replace key" required>
<p><button type="submit">Save encrypted key</button></p></form>
<?php if ($saved): ?><form method="post"><?=csrfInput()?><input type="hidden" name="action" value="delete_provider"><input type="hidden" name="provider" value="<?=h($provider)?>"><button class="danger" type="submit">Remove key</button><p class="muted small">Removal takes effect immediately.</p></form><?php endif; ?></article>
<?php endforeach; ?></div></section><?php endif; ?>
<?php
$userSearch = substr(trim((string) ($_GET['user_search'] ?? '')), 0, 254);
$userPageValue = filter_var($_GET['user_page'] ?? 1, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
$userPage = $userPageValue === false ? 1 : $userPageValue;
$userPageSize = 25;
$userCountQuery = $db->prepare('SELECT COUNT(*) FROM users WHERE LOCATE(?, email) > 0');
$userCountQuery->execute([$userSearch]);
$userTotal = (int) $userCountQuery->fetchColumn();
$userPageCount = max(1, (int) ceil($userTotal / $userPageSize));
$userPage = min($userPage, $userPageCount);
$userOffset = ($userPage - 1) * $userPageSize;
$userQuery = $db->prepare('SELECT u.id,u.email,u.created_at,s.disabled_at,e.source,e.plan_code,e.quota_bytes,e.used_bytes,e.expires_at FROM users u LEFT JOIN user_admin_state s ON s.user_id=u.id LEFT JOIN cloud_entitlements e ON e.user_id=u.id WHERE LOCATE(?, u.email) > 0 ORDER BY u.created_at DESC,u.id DESC LIMIT ? OFFSET ?');
$userQuery->bindValue(1, $userSearch, PDO::PARAM_STR);
$userQuery->bindValue(2, $userPageSize, PDO::PARAM_INT);
$userQuery->bindValue(3, $userOffset, PDO::PARAM_INT);
$userQuery->execute();
?>
<section id="user-access"><h2>User access</h2><p class="muted">Disable an account to block API access and revoke its active sessions. Admin test trials grant temporary cloud storage only; they never represent verified payment. Paid entitlements are controlled by verified billing. Owner-console accounts are managed separately through the CLI.</p><article class="card">
<form method="get" action="/admin.php" role="search"><label for="user-search">Find an account by email</label><div class="row"><input id="user-search" name="user_search" type="search" maxlength="254" value="<?=h($userSearch)?>" autocomplete="off" placeholder="Email contains…"><button type="submit">Search users</button><?php if ($userSearch !== ''): ?><a class="muted" href="/admin.php#user-access">Clear search</a><?php endif; ?></div></form>
<p class="muted small" role="status"><?=h((string) $userTotal)?> account<?=($userTotal===1?'':'s')?> found<?php if ($userTotal > 0): ?> · page <?=h((string)$userPage)?> of <?=h((string)$userPageCount)?><?php endif; ?></p>
<div style="overflow-x:auto"><table><thead><tr><th>Email</th><th>Created</th><th>Access</th><th>Account action</th><th>Cloud entitlement</th><th>Test trial action</th></tr></thead><tbody>
<?php foreach($userQuery->fetchAll() as $managed): $disabled=$managed['disabled_at']!==null; ?>
<?php $hasCloud=$managed['source']!==null; $paidCloud=$managed['source']==='verified_billing'; $cloudActive=$hasCloud && strtotime((string)$managed['expires_at'].' UTC')>time(); ?>
<tr><td><?=h((string)$managed['email'])?></td><td><?=h((string)$managed['created_at'])?></td><td><span class="status <?=$disabled?'off':''?>"><?=$disabled?'Disabled':'Enabled'?></span></td><td><form method="post"><?=csrfInput()?><input type="hidden" name="user_id" value="<?=h((string)$managed['id'])?>"><input type="hidden" name="action" value="<?=$disabled?'enable_user':'disable_user'?>"><button class="<?=$disabled?'secondary':'danger'?>" type="submit"><?=$disabled?'Enable access':'Disable access'?></button></form></td><td><?php if (!$hasCloud): ?>No cloud access<?php elseif ($paidCloud): ?>Verified billing · <?=h((string)$managed['plan_code'])?><?php else: ?>Admin trial · <?=$cloudActive?'active':'expired'?> · <?=h((string)$managed['used_bytes'])?> / <?=h((string)$managed['quota_bytes'])?> bytes<?php endif; ?></td><td><?php if (!$paidCloud): ?><form method="post"><?=csrfInput()?><input type="hidden" name="user_id" value="<?=h((string)$managed['id'])?>"><input type="hidden" name="action" value="grant_cloud_trial"><label>Quota MiB <input name="quota_mib" type="number" min="1" max="1024" value="100" required></label><label>Duration days <input name="days" type="number" min="1" max="60" value="7" required></label><button type="submit">Grant test trial</button></form><?php if ($managed['source']==='admin_trial'): ?><form method="post"><?=csrfInput()?><input type="hidden" name="user_id" value="<?=h((string)$managed['id'])?>"><input type="hidden" name="action" value="revoke_cloud_trial"><button class="danger" type="submit">End test trial</button></form><?php endif; ?><?php else: ?>Billing controlled<?php endif; ?></td></tr>
<?php endforeach; ?></tbody></table></div>
<?php if ($userTotal === 0): ?><p class="muted">No accounts match this search.</p><?php endif; ?>
<?php if ($userPageCount > 1): ?><nav class="row" aria-label="User account pages"><?php if ($userPage > 1): ?><a class="muted" href="?<?=h(http_build_query(['user_search'=>$userSearch,'user_page'=>$userPage-1]))?>#user-access">Previous page</a><?php endif; ?><span class="muted small">Page <?=h((string)$userPage)?> of <?=h((string)$userPageCount)?></span><?php if ($userPage < $userPageCount): ?><a class="muted" href="?<?=h(http_build_query(['user_search'=>$userSearch,'user_page'=>$userPage+1]))?>#user-access">Next page</a><?php endif; ?></nav><?php endif; ?>
<p class="muted small">Showing up to <?=$userPageSize?> accounts per page. Every change is audited.</p></article></section>
<section><h2>Service health</h2><div class="grid">
<?php try { $counts=[]; foreach (['users'=>'users','cloud accounts'=>'cloud_entitlements','cloud projects'=>'cloud_projects','private media objects'=>'cloud_files'] as $label=>$table) {$counts[$label]=(int)$db->query('SELECT COUNT(*) FROM '.$table)->fetchColumn();} ?>
<article class="card"><span class="status">Database connected</span><table><tbody><?php foreach($counts as $label=>$count): ?><tr><th><?=h($label)?></th><td><?=h((string)$count)?></td></tr><?php endforeach; ?></tbody></table><p class="muted small">Counts only; no personal project content or credentials are displayed.</p></article>
<?php } catch (Throwable) { ?><article class="card"><span class="status off">Partial</span><p class="muted">Some optional tables are unavailable. Run the documented database installer.</p></article><?php } ?>
<article class="card"><h2>Generation queue</h2><?php try { $queue=$db->query('SELECT status,COUNT(*) AS total FROM generation_jobs GROUP BY status')->fetchAll(); if (!$queue): ?><p class="muted">No generation jobs recorded.</p><?php else: ?><table><tbody><?php foreach($queue as $item): ?><tr><th><?=h((string)$item['status'])?></th><td><?=h((string)$item['total'])?></td></tr><?php endforeach; ?></tbody></table><?php endif; ?><p class="muted small">Job prompts and provider outputs are not displayed here.</p><?php } catch (Throwable) { ?><p class="muted">Generation queue schema is not installed.</p><?php } ?><p class="muted small">Only the explicit mock worker exists. Live provider submission remains disabled.</p></article></div></section>
<section><h2>Recent owner audit events</h2><article class="card"><table><thead><tr><th>Time (UTC)</th><th>Event</th><th>Target</th></tr></thead><tbody>
<?php $q=$db->query('SELECT occurred_at,event_code,target_type,target_id FROM admin_audit_log ORDER BY id DESC LIMIT 20'); foreach($q->fetchAll() as $event): ?><tr><td><?=h((string)$event['occurred_at'])?></td><td><?=h((string)$event['event_code'])?></td><td><?=h(trim((string)$event['target_type'].' '.(string)$event['target_id']))?></td></tr><?php endforeach; ?>
</tbody></table></article></section>
<p class="muted small">This operations panel is an early owner-console slice, not the full production administration system. Role administration, subscription controls, uploads/jobs management, backup drills, MFA recovery and service monitoring still require release gates.</p>
<?php endif; ?></main></body></html>

