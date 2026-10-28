-- HOTICE cPanel shared-hosting backend MVP. Schema is applied by CLI only.
CREATE TABLE IF NOT EXISTS users (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  email VARCHAR(254) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Separate owner identities cannot be created through public app registration.
-- TOTP secrets are envelope-encrypted by the application before storage.
CREATE TABLE IF NOT EXISTS admin_accounts (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  email VARCHAR(254) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  totp_secret_ciphertext VARBINARY(64) NOT NULL,
  totp_nonce VARBINARY(12) NOT NULL,
  totp_tag VARBINARY(16) NOT NULL,
  disabled_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at DATETIME NULL,
  UNIQUE KEY uq_admin_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_admin_state (
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  disabled_at DATETIME NULL,
  updated_by CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY ix_user_admin_disabled (disabled_at),
  CONSTRAINT fk_user_admin_state_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_user_admin_state_admin FOREIGN KEY (updated_by) REFERENCES admin_accounts(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS provider_secrets (
  provider VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  ciphertext VARBINARY(4096) NOT NULL,
  nonce VARBINARY(12) NOT NULL,
  tag VARBINARY(16) NOT NULL,
  updated_by CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_provider_secret_admin FOREIGN KEY (updated_by) REFERENCES admin_accounts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS admin_audit_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  admin_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  event_code VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  target_type VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
  target_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NULL,
  occurred_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_admin_audit_time (occurred_at),
  KEY ix_admin_audit_actor (admin_id, occurred_at),
  CONSTRAINT fk_admin_audit_actor FOREIGN KEY (admin_id) REFERENCES admin_accounts(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS admin_login_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  occurred_at DATETIME NOT NULL,
  KEY ix_admin_attempts_fingerprint (fingerprint, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Development-only mock generation ledger. Credits are simulated units, not money.
CREATE TABLE IF NOT EXISTS credit_accounts (
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  balance BIGINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_credit_account_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS job_quotes (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  request_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  credits BIGINT UNSIGNED NOT NULL,
  expires_at DATETIME NOT NULL,
  consumed_job_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_job_quotes_user (user_id, expires_at),
  CONSTRAINT fk_job_quote_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS generation_jobs (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  quote_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  idempotency_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  request_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  model_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  request_json MEDIUMTEXT NOT NULL,
  status ENUM('queued','processing','succeeded','failed','cancelled') NOT NULL DEFAULT 'queued',
  attempt_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
  max_attempts TINYINT UNSIGNED NOT NULL DEFAULT 3,
  available_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  lease_token CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
  lease_until DATETIME NULL,
  reserved_credits BIGINT UNSIGNED NOT NULL,
  actual_credits BIGINT UNSIGNED NOT NULL DEFAULT 0,
  result_json MEDIUMTEXT NULL,
  error_code VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  finished_at DATETIME NULL,
  UNIQUE KEY uq_job_idempotency (user_id, idempotency_hash),
  UNIQUE KEY uq_job_quote (quote_id),
  KEY ix_job_worker (status, available_at),
  KEY ix_job_lease (status, lease_until),
  KEY ix_job_user_history (user_id, created_at),
  CONSTRAINT fk_job_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_job_quote FOREIGN KEY (quote_id) REFERENCES job_quotes(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Durable attempt ledger for provider lifecycle work. The current worker only
-- writes mock attempts only. This table alone does not enable live provider calls.
CREATE TABLE IF NOT EXISTS provider_attempts (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  job_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  attempt_number TINYINT UNSIGNED NOT NULL,
  provider_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  model_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  operation_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  request_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  status ENUM('prepared','dispatching','accepted','unknown','succeeded','retryable_rejected','failed','cancelled') NOT NULL,
  remote_operation_id VARCHAR(160) CHARACTER SET ascii COLLATE ascii_bin NULL,
  error_code VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
  lease_token CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  finished_at DATETIME NULL,
  UNIQUE KEY uq_provider_attempt_number (job_id, attempt_number),
  UNIQUE KEY uq_provider_operation_key (operation_key),
  KEY ix_provider_attempt_state (status, updated_at),
  KEY ix_provider_remote_operation (provider_id, remote_operation_id),
  CONSTRAINT fk_provider_attempt_job FOREIGN KEY (job_id) REFERENCES generation_jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Owner-reviewed resolution of an ambiguous provider operation. The evidence
-- field is an opaque support/ticket reference only, never provider payloads.
CREATE TABLE IF NOT EXISTS provider_attempt_reconciliations (
  attempt_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  admin_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  action_code ENUM('confirmed_not_accepted_retry','confirmed_failed_refund') NOT NULL,
  evidence_reference VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_provider_reconciliation_attempt FOREIGN KEY (attempt_id) REFERENCES provider_attempts(id) ON DELETE CASCADE,
  CONSTRAINT fk_provider_reconciliation_admin FOREIGN KEY (admin_id) REFERENCES admin_accounts(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS credit_ledger (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  job_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  event_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  event_type ENUM('grant','reserve','settle','refund') NOT NULL,
  delta BIGINT NOT NULL,
  balance_after BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_credit_event (event_key),
  KEY ix_credit_user_history (user_id, created_at),
  KEY ix_credit_job (job_id),
  CONSTRAINT fk_credit_ledger_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_credit_ledger_job FOREIGN KEY (job_id) REFERENCES generation_jobs(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sessions (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  token_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_token_hash (token_sha256),
  KEY ix_sessions_user (user_id),
  KEY ix_sessions_expiration (expires_at),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS login_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  occurred_at DATETIME NOT NULL,
  KEY ix_login_attempts_fingerprint (fingerprint, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Payment status is SERVER-MANAGED ONLY. Credit balance is intentionally separate.
CREATE TABLE IF NOT EXISTS cloud_entitlements (
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
  source ENUM('admin_trial', 'verified_billing') NOT NULL,
  plan_code VARCHAR(64) NOT NULL,
  quota_bytes BIGINT UNSIGNED NOT NULL,
  used_bytes BIGINT UNSIGNED NOT NULL DEFAULT 0,
  expires_at DATETIME NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_cloud_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cloud_projects (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  title VARCHAR(120) NOT NULL,
  document_json MEDIUMTEXT NOT NULL,
  revision INT UNSIGNED NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_projects_user (user_id, updated_at),
  CONSTRAINT fk_projects_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cloud_files (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  project_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  storage_name CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  mime VARCHAR(80) NOT NULL,
  byte_size BIGINT UNSIGNED NOT NULL,
  sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_files_project (project_id, user_id),
  KEY ix_files_owner (user_id),
  CONSTRAINT fk_files_project FOREIGN KEY (project_id) REFERENCES cloud_projects(id) ON DELETE CASCADE,
  CONSTRAINT fk_files_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
