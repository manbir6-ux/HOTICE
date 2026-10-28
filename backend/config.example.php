<?php
/** Copy to backend/config.php OUTSIDE public/ (never commit config.php). */
return [
    'db' => [
        'dsn' => 'mysql:host=localhost;dbname=cpaneluser_hotice;charset=utf8mb4',
        'user' => 'cpaneluser_hotice',
        'password' => 'SET_YOUR_UNIQUE_DATABASE_PASSWORD',
    ],
    // Use: php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
    'app_key' => 'REPLACE_WITH_64_RANDOM_HEX_CHARACTERS',
    'storage_path' => __DIR__ . '/private-media',
    // Set to your cPanel domain's real document root (for example
    // /home/account/public_html). The installer checks this BEFORE deployment.
    'public_webroot_path' => '/home/CPANEL_USERNAME/public_html',
    'require_https' => true,
    'allow_registration' => false, // switch on ONLY after signup/email verification controls are in place
    'token_ttl_hours' => 24,
    'max_file_bytes' => 20 * 1024 * 1024, // conservative shared-host MVP, not large source videos
    'max_project_bytes' => 128 * 1024,
    'max_cloud_projects' => 100, // server-owned per-account metadata limit
    'max_files_per_project' => 200, // avoid shared-host inode/database abuse
    // Opt-in only for staging dry runs. This never enables real provider calls.
    'mock_jobs_enabled' => false,
    'mock_job_cost_credits' => 5,
    'mock_job_quote_ttl_seconds' => 300,
    // Never put secret keys inside Flutter, JS, SQL, or Git. No live AI adapter in v0.1.
    'providers' => [
        'openai' => ['api_key' => ''],
        'google' => ['api_key' => ''],
        'runway' => ['api_key' => ''],
    ],
];
