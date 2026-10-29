<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require_once dirname(__DIR__) . '/src/App.php';
$config = require dirname(__DIR__) . '/config.php';
$scanner = (string)($config['clamdscan_path'] ?? '');
if ($scanner === '' || !str_starts_with($scanner, '/') || !is_executable($scanner)) {
    fwrite(STDERR, "Media scanning is not configured; uploads remain quarantined.\n");
    exit(2);
}
try {
    $app = new \Hotice\App($config);
    $db = $app->database();
    $storage = (string)($config['storage_path'] ?? '');
    if ($storage === '' || !is_dir($storage)) throw new RuntimeException('Private storage unavailable.');
    $roots = [dirname(__DIR__) . '/public'];
    $webroot = trim((string)($config['public_webroot_path'] ?? ''));
    if ($webroot !== '') $roots[] = $webroot;
    \Hotice\Support::assertPrivateStorage($storage, $roots);
    $limit = isset($argv[1]) && ctype_digit($argv[1]) ? max(1, min(100, (int)$argv[1])) : 20;
    $q = $db->prepare("SELECT id,storage_name FROM cloud_files WHERE scan_status='pending' ORDER BY created_at,id LIMIT ?");
    $q->bindValue(1, $limit, PDO::PARAM_INT);
    $q->execute();
    $clean = $blocked = $retryable = 0;
    foreach ($q->fetchAll() as $file) {
        $name = (string)$file['storage_name'];
        if (!\Hotice\Support::secureFileName($name)) { $retryable++; continue; }
        $path = $storage . '/' . $name;
        if (!is_file($path) || !is_readable($path)) { $retryable++; continue; }
        $pipes = [];
        $process = proc_open([$scanner, '--no-summary', '--', $path], [
            0 => ['file', '/dev/null', 'r'],
            1 => ['file', '/dev/null', 'a'],
            2 => ['file', '/dev/null', 'a'],
        ], $pipes);
        if (!is_resource($process)) { $retryable++; continue; }
        $started = microtime(true);
        do {
            $state = proc_get_status($process);
            if (!$state['running']) { $code = $state['exitcode']; break; }
            if (microtime(true) - $started >= 120) {
                proc_terminate($process, 9);
                $code = -1;
                break;
            }
            usleep(200000);
        } while (true);
        proc_close($process);
        if ($code !== 0 && $code !== 1) { $retryable++; continue; }
        $status = $code === 0 ? 'clean' : 'blocked';
        $update = $db->prepare("UPDATE cloud_files SET scan_status=? WHERE id=? AND storage_name=? AND scan_status='pending'");
        $update->execute([$status, $file['id'], $name]);
        if ($update->rowCount() === 1) $status === 'clean' ? $clean++ : $blocked++;
    }
    echo json_encode(['scannedClean' => $clean, 'blocked' => $blocked, 'retryableFailures' => $retryable], JSON_THROW_ON_ERROR) . "\n";
    exit($retryable > 0 ? 1 : 0);
} catch (Throwable $e) {
    fwrite(STDERR, 'Media scan failed; files remain quarantined. ' . get_class($e) . "\n");
    exit(1);
}

