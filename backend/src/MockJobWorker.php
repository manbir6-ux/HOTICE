<?php
declare(strict_types=1);

namespace Hotice;

use PDO;
use Throwable;

/** Local deterministic test worker. It never contacts a model provider. */
final class MockJobWorker
{
    public static function runOne(PDO $db, array $config): array
    {
        if (($config['mock_jobs_enabled'] ?? false) !== true) throw new \RuntimeException('Mock job worker is disabled.');
        if ((int)$db->query("SELECT GET_LOCK('hotice_mock_job_worker',0)")->fetchColumn() !== 1) {
            return ['status' => 'worker_busy'];
        }
        try {
            self::recoverExpiredLeases($db);
            $job = self::claim($db);
            if ($job === null) return ['status' => 'idle'];
            return self::simulate($db, $job);
        } finally {
            $db->query("SELECT RELEASE_LOCK('hotice_mock_job_worker')");
        }
    }

    private static function recoverExpiredLeases(PDO $db): void
    {
        $stale = $db->query("SELECT id,user_id FROM generation_jobs WHERE status='processing' AND lease_until<UTC_TIMESTAMP() ORDER BY lease_until LIMIT 20")->fetchAll();
        foreach ($stale as $candidate) {
            $db->beginTransaction();
            $account = $db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
            $account->execute([$candidate['user_id']]);
            $balance = (int)$account->fetchColumn();
            $q = $db->prepare('SELECT status,attempt_count,max_attempts,reserved_credits FROM generation_jobs WHERE id=? AND user_id=? FOR UPDATE');
            $q->execute([$candidate['id'], $candidate['user_id']]);
            $job = $q->fetch();
            if (!$job || $job['status'] !== 'processing') { $db->commit(); continue; }
            if ((int)$job['attempt_count'] < (int)$job['max_attempts']) {
                $db->prepare("UPDATE generation_jobs SET status='queued',available_at=UTC_TIMESTAMP(),error_code='worker_lease_expired',lease_token=NULL,lease_until=NULL WHERE id=?")
                    ->execute([$candidate['id']]);
                $db->commit();
                continue;
            }
            self::refundAndFail($db, $candidate['id'], $candidate['user_id'], $job, $balance, 'worker_lease_expired');
            $db->commit();
        }
    }

    private static function claim(PDO $db): ?array
    {
        $candidate = $db->query("SELECT id,user_id FROM generation_jobs WHERE status='queued' AND available_at<=UTC_TIMESTAMP() ORDER BY created_at LIMIT 1")->fetch();
        if (!$candidate) return null;
        $db->beginTransaction();
        $account = $db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
        $account->execute([$candidate['user_id']]);
        $q = $db->prepare('SELECT id,user_id,status,request_json,request_sha256,attempt_count,max_attempts,reserved_credits FROM generation_jobs WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$candidate['id'], $candidate['user_id']]);
        $job = $q->fetch();
        if (!$job || $job['status'] !== 'queued') { $db->commit(); return null; }
        $lease = bin2hex(random_bytes(16));
        $attempt = (int)$job['attempt_count'] + 1;
        $db->prepare("UPDATE generation_jobs SET status='processing',attempt_count=?,lease_token=?,lease_until=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 60 SECOND),error_code=NULL WHERE id=?")
            ->execute([$attempt, $lease, $job['id']]);
        $db->commit();
        $job['attempt_count'] = $attempt;
        $job['lease_token'] = $lease;
        $job['request'] = json_decode($job['request_json'], true, 16, JSON_THROW_ON_ERROR);
        return $job;
    }

    private static function simulate(PDO $db, array $job): array
    {
        $scenario = $job['request']['simulate'] ?? 'success';
        $attempt = (int)$job['attempt_count'];
        $retryCode = match ($scenario) {
            'timeout_once' => $attempt === 1 ? 'mock_timeout' : null,
            'rate_limit_once' => $attempt === 1 ? 'mock_rate_limited' : null,
            'malformed_once' => $attempt === 1 ? 'mock_malformed_response' : null,
            default => null,
        };
        if ($retryCode !== null) {
            if ($attempt < (int)$job['max_attempts']) {
                $db->prepare("UPDATE generation_jobs SET status='queued',available_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 2 SECOND),error_code=?,lease_token=NULL,lease_until=NULL WHERE id=? AND status='processing' AND lease_token=?")
                    ->execute([$retryCode, $job['id'], $job['lease_token']]);
                return ['jobId' => $job['id'], 'status' => 'queued', 'attempt' => $attempt, 'retryCode' => $retryCode];
            }
            return self::finalizeFailure($db, $job, $retryCode);
        }
        if ($scenario === 'permanent_failure') return self::finalizeFailure($db, $job, 'mock_provider_rejected');

        $result = json_encode([
            'mode' => 'mock_dry_run',
            'modelId' => $job['request']['modelId'],
            'message' => 'Dry run completed. No video or provider output was created.',
            'requestSha256' => $job['request_sha256'],
        ], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $db->beginTransaction();
        $account = $db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
        $account->execute([$job['user_id']]);
        $balance = (int)$account->fetchColumn();
        $q = $db->prepare('SELECT status,lease_token,reserved_credits FROM generation_jobs WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$job['id'], $job['user_id']]);
        $current = $q->fetch();
        if (!$current || $current['status'] !== 'processing' || !hash_equals((string)$current['lease_token'], $job['lease_token'])) {
            $db->commit(); return ['jobId' => $job['id'], 'status' => 'lease_lost'];
        }
        $db->prepare("UPDATE generation_jobs SET status='succeeded',actual_credits=reserved_credits,result_json=?,error_code=NULL,finished_at=UTC_TIMESTAMP(),lease_token=NULL,lease_until=NULL WHERE id=?")
            ->execute([$result, $job['id']]);
        $db->prepare("INSERT INTO credit_ledger(user_id,job_id,event_key,event_type,delta,balance_after) VALUES(?,?,?,'settle',0,?)")
            ->execute([$job['user_id'], $job['id'], hash('sha256', 'settle:' . $job['id']), $balance]);
        $db->commit();
        return ['jobId' => $job['id'], 'status' => 'succeeded', 'attempt' => $attempt];
    }

    private static function finalizeFailure(PDO $db, array $job, string $error): array
    {
        $db->beginTransaction();
        $account = $db->prepare('SELECT balance FROM credit_accounts WHERE user_id=? FOR UPDATE');
        $account->execute([$job['user_id']]);
        $balance = (int)$account->fetchColumn();
        $q = $db->prepare('SELECT status,lease_token,reserved_credits,attempt_count,max_attempts FROM generation_jobs WHERE id=? AND user_id=? FOR UPDATE');
        $q->execute([$job['id'], $job['user_id']]);
        $current = $q->fetch();
        if (!$current || $current['status'] !== 'processing' || !hash_equals((string)$current['lease_token'], $job['lease_token'])) {
            $db->commit(); return ['jobId' => $job['id'], 'status' => 'lease_lost'];
        }
        self::refundAndFail($db, $job['id'], $job['user_id'], $current, $balance, $error);
        $db->commit();
        return ['jobId' => $job['id'], 'status' => 'failed', 'attempt' => (int)$current['attempt_count'], 'errorCode' => $error];
    }

    private static function refundAndFail(PDO $db, string $id, string $user, array $job, int $balance, string $error): void
    {
        $refund = (int)$job['reserved_credits'];
        $next = $balance + $refund;
        $db->prepare('UPDATE credit_accounts SET balance=? WHERE user_id=?')->execute([$next, $user]);
        $db->prepare("INSERT INTO credit_ledger(user_id,job_id,event_key,event_type,delta,balance_after) VALUES(?,?,?,'refund',?,?)")
            ->execute([$user, $id, hash('sha256', 'refund:' . $id), $refund, $next]);
        $db->prepare("UPDATE generation_jobs SET status='failed',actual_credits=0,error_code=?,finished_at=UTC_TIMESTAMP(),lease_token=NULL,lease_until=NULL WHERE id=?")
            ->execute([$error, $id]);
    }
}
