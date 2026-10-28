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
  String? _catalogError;
  BackendModelCatalog? _catalog;
  bool _busy = false;
  bool _catalogBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshCatalog();
  }

  @override
  void didUpdateWidget(covariant BackendDryRunPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.isAuthenticated != widget.isAuthenticated) {
      _refreshCatalog();
    }
  }

  @override
  void dispose() { _prompt.dispose(); super.dispose(); }

  Future<void> _refreshCatalog() async {
    final client = widget.client;
    if (client == null || !widget.isAuthenticated) {
      if (mounted) {
        setState(() {
          _catalog = null;
          _catalogError = null;
          _catalogBusy = false;
        });
      }
      return;
    }
    setState(() { _catalogBusy = true; _catalogError = null; });
    try {
      final value = await client.loadModelCatalog();
      if (mounted) setState(() => _catalog = value);
    } on BackendAuthException catch (e) {
      if (mounted) setState(() { _catalog = null; _catalogError = e.message; });
    } catch (_) {
      if (mounted) setState(() {
        _catalog = null;
        _catalogError = 'Could not load model availability from the HOTICE server.';
      });
    } finally {
      if (mounted) setState(() => _catalogBusy = false);
    }
  }

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
    if (client == null || !widget.isAuthenticated ||
        _catalog?.mockVideoDryRun == null) return;
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
      Text('Server dry run', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Staging check only. The HOTICE server verifies availability and job handling. It does not generate a video, call an AI provider or spend money.'),
      const SizedBox(height: 16),
      if (client == null) const _Notice('Server API is not configured in this build.')
      else if (!widget.isAuthenticated) const _Notice('Sign in with a server account to submit a dry run. Guest demo mode cannot access server jobs.')
      else ...[
        _ModelAvailabilityCard(
          catalog: _catalog,
          busy: _catalogBusy,
          error: _catalogError,
          onRefresh: _catalogBusy ? null : _refreshCatalog,
        ),
        const SizedBox(height: 12),
        TextField(controller: _prompt, minLines: 3, maxLines: 6, maxLength: 2000,
          enabled: !_busy && !_catalogBusy && _catalog?.mockVideoDryRun != null &&
              (job == null || (job.status != 'queued' && job.status != 'processing')),
          decoration: const InputDecoration(labelText: 'Dry-run prompt', hintText: 'A quiet coastal film at blue hour...', border: OutlineInputBorder()),
          onChanged: (_) {
            if (job != null && job.status != 'queued' && job.status != 'processing') {
              setState(() { _job = null; _key = null; });
            }
          }),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy || _catalogBusy ||
            _catalog?.mockVideoDryRun == null || job != null ||
            _prompt.text.trim().isEmpty ? null : _submit,
          icon: const Icon(Icons.cloud_upload_outlined), label: Text(_busy ? 'Working…' : 'Run staging check')),
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

class _ModelAvailabilityCard extends StatelessWidget {
  const _ModelAvailabilityCard({
    required this.catalog,
    required this.busy,
    required this.error,
    required this.onRefresh,
  });

  final BackendModelCatalog? catalog;
  final bool busy;
  final String? error;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final model = catalog?.mockVideoDryRun;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Server model availability',
              style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            tooltip: 'Refresh model availability',
            onPressed: onRefresh,
            icon: busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ]),
        if (busy && catalog == null) const Text('Checking with the HOTICE server…')
        else if (error != null) Text(error!)
        else if (model == null) const Text(
            'No staging dry-run model is currently enabled on this server.')
        else ...[
          Text(model.name),
          if (model.notice != null) Text(model.notice!),
          Text('Catalog ${catalog!.catalogVersion} · no video output'),
        ],
      ]),
    ));
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(text)));
}
