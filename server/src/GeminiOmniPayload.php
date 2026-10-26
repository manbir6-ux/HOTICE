<?php
declare(strict_types=1);

namespace Hotice\Provider;

/**
 * Pure, server-only Gemini Omni Flash Interactions payload builder.
 *
 * IMPORTANT: This does not send requests, store API keys, authenticate users,
 * upload files, or charge credits. An authenticated HOTICE backend MUST verify
 * ownership, consent, file safety, provider policy and server-side prices before
 * invoking any paid model. Never expose it as an unauthenticated route.
 */
final class GeminiOmniPayload
{
    public const MODEL = 'gemini-omni-1.1-flash';
    public const ALLOWED_TASKS = [
        'text_to_video', 'image_to_video', 'reference_to_video', 'edit', 'extend',
    ];

    /**
     * @param array<int,array{data:string,mime_type:string}> $images
     * @return array<string,mixed>
     */
    public static function prepare(
        string $prompt,
        string $aspectRatio,
        array $images = [],
        ?string $task = null
    ): array {
        $prompt = trim($prompt);
        if ($prompt === '' || mb_strlen($prompt) > 8000) {
            throw new \InvalidArgumentException('Prompt length is invalid.');
        }
        if (!in_array($aspectRatio, ['16:9', '9:16'], true)) {
            throw new \InvalidArgumentException('Unsupported output ratio.');
        }
        if ($task !== null && !in_array($task, self::ALLOWED_TASKS, true)) {
            throw new \InvalidArgumentException('Unsupported Omni video task.');
        }
        // 2 is a conservative HOTICE demo policy, NOT an official API max.
        // The production backend must use an independently verified policy.
        if (count($images) > 2) {
            throw new \InvalidArgumentException('Too many staged images.');
        }

        $input = [];
        foreach ($images as $item) {
            if (!isset($item['data'], $item['mime_type']) ||
                !is_string($item['data']) || !is_string($item['mime_type']) ||
                !in_array($item['mime_type'], ['image/jpeg', 'image/png'], true) ||
                strlen($item['data']) > 8 * 1024 * 1024 ||
                strlen($item['data']) < 4 ||
                !preg_match('/^[A-Za-z0-9+\/=]+$/D', $item['data']) ||
                base64_decode($item['data'], true) === false) {
                throw new \InvalidArgumentException('Invalid image payload.');
            }
            // Extension/MIME supplied by a client is not proof of an image.
            // Verify the decoded bytes before a future provider gateway
            // forwards sensitive media to a billed external service.
            $binary = base64_decode($item['data'], true);
            $details = $binary === false ? false : @getimagesizefromstring($binary);
            if ($details === false ||
                ($details['mime'] ?? null) !== $item['mime_type'] ||
                $details[0] < 1 || $details[1] < 1 ||
                $details[0] > 8192 || $details[1] > 8192 ||
                $details[0] * $details[1] > 20_000_000) {
                throw new \InvalidArgumentException('Image bytes, MIME or dimensions are invalid.');
            }
            $input[] = [
                'type' => 'image',
                'data' => $item['data'],
                'mime_type' => $item['mime_type'],
            ];
        }
        $input[] = ['type' => 'text', 'text' => $prompt];

        $payload = [
            'model' => self::MODEL,
            'input' => $input,
            'response_format' => [
                'type' => 'video',
                'aspect_ratio' => $aspectRatio,
            ],
        ];
        if ($task !== null) {
            $payload['generation_config'] = [
                'video_config' => ['task' => $task],
            ];
        }
        return $payload;
    }
}
