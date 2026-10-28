<?php
declare(strict_types=1);

namespace Hotice;

use PDO;
use Throwable;

require_once __DIR__ . '/ProviderAdapter.php';
require_once __DIR__ . '/MockProviderAdapter.php';

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
            $attemptQuery = $db->prepare('SELECT id,status FROM provider_attempts WHERE job_id=? ORDER BY attempt_number DESC LIMIT 1 FOR UPDATE');
            $attemptQuery->execute([$candidate['id']]);
            $providerAttempt = $attemptQuery->fetch();
            if ($providerAttempt && in_array($providerAttempt['status'], ['dispatching', 'accepted', 'unknown'], true)) {
                // The remote provider may have accepted a billable request.
                // Preserve the reservation and stop automatic retries until an
                // operator can reconcile the durable operation record.
                $db->prepare("UPDATE provider_attempts SET status='unknown',error_code='provider_outcome_unknown' WHERE id=? AND status IN ('dispatching','accepted','unknown')")
                    ->execute([$providerAttempt['id']]);
                $db->prepare("UPDATE generation_jobs SET error_code='provider_outcome_unknown',lease_token=NULL,lease_until=NULL WHERE id=? AND status='processing'")
                    ->execute([$candidate['id']]);
                $db->commit();
                continue;
            }
            if ((int)$job['attempt_count'] < (int)$job['max_attempts']) {
                if ($providerAttempt && $providerAttempt['status'] === 'prepared') {
                    $db->prepare("UPDATE provider_attempts SET status='failed',error_code='worker_lease_expired_before_dispatch',finished_at=UTC_TIMESTAMP() WHERE id=? AND status='prepared'")
                        ->execute([$providerAttempt['id']]);
                }
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
        $request = json_decode($job['request_json'], true, 16, JSON_THROW_ON_ERROR);
        $attemptId = Support::uuid();
        $operationKey = hash('sha256', "hotice:provider-operation:v1\0" . $job['id'] . "\0" . $attempt);
        $db->prepare("UPDATE generation_jobs SET status='processing',attempt_count=?,lease_token=?,lease_until=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 60 SECOND),error_code=NULL WHERE id=?")
            ->execute([$attempt, $lease, $job['id']]);
        $db->prepare("INSERT INTO provider_attempts(id,job_id,attempt_number,provider_id,model_id,operation_key,request_sha256,status,lease_token) VALUES(?,?,?,'mock',?,?,?,'prepared',?)")
            ->execute([$attemptId, $job['id'], $attempt, $request['modelId'], $operationKey, $job['request_sha256'], $lease]);
        $db->commit();
        $job['attempt_count'] = $attempt;
        $job['lease_token'] = $lease;
        $job['request'] = $request;
        $job['provider_attempt_id'] = $attemptId;
        $job['operation_key'] = $operationKey;
        return $job;
    }

    private static function simulate(PDO $db, array $job): array
    {
        $scenario = $job['request']['simulate'] ?? 'success';
        $attempt = (int)$job['attempt_count'];
        $registry = new ProviderRegistry([new MockProviderAdapter()]);
        $adapter = $registry->forModel((string)$job['request']['modelId']);
        $providerRequest = new ProviderRequest(
            (string)$job['request']['modelId'],
            '', // Prompts are deliberately absent from the durable dry-run queue row.
            [],
            ['simulate' => $scenario, 'attempt' => $attempt],
        );
        $dispatch = $db->prepare("UPDATE provider_attempts SET status='dispatching' WHERE id=? AND lease_token=? AND status='prepared'");
        $dispatch->execute([$job['provider_attempt_id'], $job['lease_token']]);
        if ($dispatch->rowCount() !== 1) return ['jobId' => $job['id'], 'status' => 'lease_lost'];
        $operation = $adapter->submit($providerRequest, $job['operation_key']);
        $accepted = $db->prepare("UPDATE provider_attempts SET status='accepted',remote_operation_id=? WHERE id=? AND lease_token=? AND status='dispatching'");
        $accepted->execute([$operation->operationId, $job['provider_attempt_id'], $job['lease_token']]);
        if ($accepted->rowCount() !== 1) return ['jobId' => $job['id'], 'status' => 'lease_lost'];
        for ($poll = 0; $poll < 2 && in_array($operation->status, ['queued', 'processing'], true); $poll++) {
            $operation = $adapter->poll($operation->operationId);
        }

        if ($operation->status === 'failed' && $operation->retryable) {
            $retryCode = $operation->errorCode ?? 'mock_provider_retryable_failure';
            if ($attempt < (int)$job['max_attempts']) {
                $db->beginTransaction();
                $current = $db->prepare('SELECT status,lease_token FROM generation_jobs WHERE id=? FOR UPDATE');
                $current->execute([$job['id']]);
                $currentJob = $current->fetch();
                if (!$currentJob || $currentJob['status'] !== 'processing' || !hash_equals((string)$currentJob['lease_token'], $job['lease_token'])) {
                    $db->rollBack();
                    return ['jobId' => $job['id'], 'status' => 'lease_lost'];
                }
                $rejected = $db->prepare("UPDATE provider_attempts SET status='retryable_rejected',error_code=?,finished_at=UTC_TIMESTAMP() WHERE id=? AND lease_token=? AND status='accepted'");
                $rejected->execute([$retryCode, $job['provider_attempt_id'], $job['lease_token']]);
                if ($rejected->rowCount() !== 1) {
                    $db->rollBack();
                    return ['jobId' => $job['id'], 'status' => 'attempt_state_lost'];
                }
                $db->prepare("UPDATE generation_jobs SET status='queued',available_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 2 SECOND),error_code=?,lease_token=NULL,lease_until=NULL WHERE id=? AND status='processing' AND lease_token=?")
                    ->execute([$retryCode, $job['id'], $job['lease_token']]);
                $db->commit();
                return ['jobId' => $job['id'], 'status' => 'queued', 'attempt' => $attempt, 'retryCode' => $retryCode];
            }
            return self::finalizeFailure($db, $job, $retryCode);
        }
        if ($operation->status !== 'succeeded') {
            return self::finalizeFailure($db, $job, $operation->errorCode ?? 'mock_provider_failed');
        }

        $result = json_encode($operation->result, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
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
        $attemptSucceeded = $db->prepare("UPDATE provider_attempts SET status='succeeded',finished_at=UTC_TIMESTAMP() WHERE id=? AND lease_token=? AND status='accepted'");
        $attemptSucceeded->execute([$job['provider_attempt_id'], $job['lease_token']]);
        if ($attemptSucceeded->rowCount() !== 1) {
            $db->rollBack();
            return ['jobId' => $job['id'], 'status' => 'attempt_state_lost'];
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
        $attemptFailed = $db->prepare("UPDATE provider_attempts SET status='failed',error_code=?,finished_at=UTC_TIMESTAMP() WHERE id=? AND lease_token=? AND status IN ('accepted','dispatching')");
        $attemptFailed->execute([$error, $job['provider_attempt_id'], $job['lease_token']]);
        if ($attemptFailed->rowCount() !== 1) {
            $db->rollBack();
            return ['jobId' => $job['id'], 'status' => 'attempt_state_lost'];
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
