import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'backend_auth.dart';

class BackendDryRunPage extends StatefulWidget {
  const BackendDryRunPage({super.key, required this.client, required this.isAuthenticated});
  final BackendAuthClient? client;
  final bool isAuthenticated;
  @override
  State<BackendDryRunPage> createState() => _BackendDryRunPageState();
}
class _BackendDryRunPageState extends State<BackendDryRunPage> {
  final _prompt = TextEditingController();
  BackendGenerationJob? _job;
  String? _key;
  String? _error;
  bool _busy = false;
  @override
  void dispose() { _prompt.dispose(); super.dispose(); }
  String _newKey() {
    final random = math.Random.secure();
    return 'hotice-dryrun-' + List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
  }
  Future<void> _perform(Future<BackendGenerationJob> Function() call) async {
    setState(() { _busy = true; _error = null; });
    try { final value = await call(); if (mounted) setState(() => _job = value); }
    on BackendAuthException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Could not reach the HOTICE server.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _submit() {
    final client = widget.client;
    if (client == null || !widget.isAuthenticated) return;
    _key ??= _newKey();
    final key = _key!;
    _perform(() => client.submitMockVideoJob(_prompt.text, idempotencyKey: key))
      .then((_) { if (_job != null) _key = null; });
  }
  @override
  Widget build(BuildContext context) {
    final job = _job;
    final client = widget.client;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('API queue verification', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Staging dry run only. Verifies authentication, quotes, queueing and status updates. It does not call an AI provider, create a video or use cash credits.'),
      const SizedBox(height: 16),
      if (client == null) const _Notice('Server API is not configured in this build.')
      else if (!widget.isAuthenticated) const _Notice('Sign in with a server account to submit a dry run. Guest demo mode cannot access server jobs.')
      else ...[
        TextField(controller: _prompt, minLines: 3, maxLines: 6, maxLength: 2000,
          enabled: !_busy && (job == null || (job.status != 'queued' && job.status != 'processing')),
          decoration: const InputDecoration(labelText: 'Dry-run prompt', hintText: 'A quiet coastal film at blue hour...', border: OutlineInputBorder()),
          onChanged: (_) {
            if (job != null && job.status != 'queued' && job.status != 'processing') {
              setState(() { _job = null; _key = null; });
            }
          }),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy || job != null || _prompt.text.trim().isEmpty ? null : _submit,
          icon: const Icon(Icons.cloud_upload_outlined), label: Text(_busy ? 'Working…' : 'Queue server dry run')),
        if (job != null) ...[
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Job status: ${job.status}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText('Job ID: ${job.id}'),
            Text('Attempt ${job.attempts} of ${job.maxAttempts} · simulated credits reserved: ${job.reservedCredits}'),
            if (job.message != null) Text(job.message!),
            if (job.errorCode != null) Text('Error: ${job.errorCode}'),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _busy ? null : () => _perform(() => client.getMockVideoJob(job.id)), icon: const Icon(Icons.refresh), label: const Text('Refresh status')),
              if (job.status == 'queued') TextButton.icon(onPressed: _busy ? null : () => _perform(() => client.cancelMockVideoJob(job.id)), icon: const Icon(Icons.cancel_outlined), label: const Text('Cancel')),
            ]),
          ]))),
        ],
      ],
      if (_error != null) ...[const SizedBox(height: 12), _Notice(_error!)],
    ]);
  }
}
class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(text)));
}