<?php
declare(strict_types=1);

namespace Hotice;

use PDO;
use Throwable;

/** Encrypted, retryable email delivery for account lifecycle messages. */
final class EmailOutbox
{
    public static function enqueue(PDO $db, array $config, string $email, string $subject, string $body, string $expiresAt): void
    {
        $id = Support::uuid();
        $key = self::key($config);
        $nonce = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt($body, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $nonce, $tag, 'hotice-email-outbox:' . $id);
        if (!is_string($ciphertext) || strlen($tag) !== 16) throw new \RuntimeException('Unable to protect email outbox payload.');
        $db->prepare('INSERT INTO email_outbox (id,recipient,subject,ciphertext,nonce,tag,expires_at,available_at) VALUES (?,?,?,?,?,?,?,UTC_TIMESTAMP())')
            ->execute([$id, $email, $subject, $ciphertext, $nonce, $tag, $expiresAt]);
    }

    /** @return array{status:string,sent:int,retried:int,failed:int} */
    public static function process(PDO $db, array $config, int $limit = 20): array
    {
        $limit = max(1, min(100, $limit));
        if ((int)$db->query("SELECT GET_LOCK('hotice_email_outbox',0)")->fetchColumn() !== 1) {
            return ['status' => 'worker_busy', 'sent' => 0, 'retried' => 0, 'failed' => 0];
        }
        $counts = ['status' => 'ok', 'sent' => 0, 'retried' => 0, 'failed' => 0];
        try {
            $counts['failed'] += (int)$db->exec("UPDATE email_outbox SET failed_at=UTC_TIMESTAMP(),ciphertext=NULL,nonce=NULL,tag=NULL,locked_until=NULL,last_error_code='expired' WHERE sent_at IS NULL AND failed_at IS NULL AND expires_at<=UTC_TIMESTAMP()");
            for ($n = 0; $n < $limit; $n++) {
                $db->beginTransaction();
                try {
                    $q = $db->query("SELECT id,recipient,subject,ciphertext,nonce,tag,attempts FROM email_outbox WHERE sent_at IS NULL AND failed_at IS NULL AND expires_at>UTC_TIMESTAMP() AND available_at<=UTC_TIMESTAMP() AND (locked_until IS NULL OR locked_until<UTC_TIMESTAMP()) ORDER BY created_at,id LIMIT 1 FOR UPDATE");
                    $row = $q->fetch();
                    if (!$row) { $db->commit(); break; }
                    $attempts = (int)$row['attempts'] + 1;
                    $db->prepare('UPDATE email_outbox SET locked_until=DATE_ADD(UTC_TIMESTAMP(), INTERVAL 90 SECOND),attempts=? WHERE id=?')
                        ->execute([$attempts, $row['id']]);
                    $db->commit();
                } catch (Throwable $e) {
                    if ($db->inTransaction()) $db->rollBack();
                    throw $e;
                }

                try {
                    $body = self::decrypt($config, (string)$row['id'], (string)$row['ciphertext'], (string)$row['nonce'], (string)$row['tag']);
                    $delivered = self::deliver($config, (string)$row['recipient'], (string)$row['subject'], $body);
                    if (!$delivered) throw new \RuntimeException('mail_delivery_failed');
                    $db->prepare('UPDATE email_outbox SET sent_at=UTC_TIMESTAMP(),locked_until=NULL,ciphertext=NULL,nonce=NULL,tag=NULL,last_error_code=NULL WHERE id=? AND sent_at IS NULL')
                        ->execute([$row['id']]);
                    $counts['sent']++;
                } catch (Throwable $e) {
                    if ($attempts >= 8 || $e->getMessage() === 'email_payload_invalid') {
                        $db->prepare('UPDATE email_outbox SET failed_at=UTC_TIMESTAMP(),locked_until=NULL,last_error_code=? WHERE id=? AND sent_at IS NULL')
                            ->execute([$e->getMessage() === 'email_payload_invalid' ? 'payload_invalid' : 'delivery_exhausted', $row['id']]);
                        $counts['failed']++;
                    } else {
                        $delay = min(3600, 30 * (2 ** min(6, $attempts - 1)));
                        $retryAt = gmdate('Y-m-d H:i:s', time() + $delay);
                        $db->prepare('UPDATE email_outbox SET available_at=?,locked_until=NULL,last_error_code=\'delivery_retry\' WHERE id=? AND sent_at IS NULL')
                            ->execute([$retryAt, $row['id']]);
                        $counts['retried']++;
                    }
                }
            }
        } finally {
            $db->query("SELECT RELEASE_LOCK('hotice_email_outbox')");
        }
        return $counts;
    }

    private static function key(array $config): string
    {
        $key = hex2bin((string)($config['app_key'] ?? ''));
        if (!is_string($key) || strlen($key) !== 32) throw new \RuntimeException('Invalid email outbox encryption key.');
        return $key;
    }

    private static function decrypt(array $config, string $id, string $ciphertext, string $nonce, string $tag): string
    {
        $body = openssl_decrypt($ciphertext, 'aes-256-gcm', self::key($config), OPENSSL_RAW_DATA,
            $nonce, $tag, 'hotice-email-outbox:' . $id);
        if (!is_string($body)) throw new \RuntimeException('email_payload_invalid');
        return $body;
    }

    private static function deliver(array $config, string $email, string $subject, string $body): bool
    {
        $transport = $config['mail_transport'] ?? null;
        if (is_callable($transport)) return (bool)$transport($email, $subject, $body);
        $from = (string)($config['mail_from'] ?? '');
        return filter_var($from, FILTER_VALIDATE_EMAIL) !== false && mail($email, $subject, $body,
            "From: HOTICE <$from>\r\nContent-Type: text/plain; charset=UTF-8");
    }
}

