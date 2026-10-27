<?php
/** PHP built-in server routing for local/CI integration tests only. */
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if (is_string($path) && is_file(__DIR__ . $path)) return false;
require __DIR__ . '/index.php';
