import 'package:flutter/material.dart';
import 'design.dart';
import 'model_registry.dart';

/// Source-linked model requirements. Not a connected production API.
class ModelCompatibilityPage extends StatefulWidget {
  const ModelCompatibilityPage({super.key});
  @override
  State<ModelCompatibilityPage> createState() => _ModelCompatibilityPageState();
}

class _ModelCompatibilityPageState extends State<ModelCompatibilityPage> {
  AiTask? filter;
  bool showRetired = false;
  String search = '';

  String describe(AiCapability item) {
    final duration = item.task != AiTask.video ? 'N/A'
        : item.exactSeconds.isNotEmpty
          ? item.exactSeconds.join(', ') + ' seconds'
          : item.minSeconds == null || item.maxSeconds == null
            ? 'Not verified'
            : item.minSeconds.toString() + '–' + item.maxSeconds.toString() + ' seconds';
    return 'Duration: ' + duration +
        ' · Max images: ' + (item.imageLimit?.toString() ?? 'unknown') +
        ' · Native GLB: ' + (item.meshLimit == 0 ? 'No' : 'Verify');
  }

  @override
  Widget build(BuildContext context) {
    final matching = HoticeAiCatalog.entries.where((item) {
      if (!showRetired && item.status == AiStatus.retired) return false;
      if (filter != null && item.task != filter) return false;
      final query = search.trim().toLowerCase();
      return query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.provider.toLowerCase().contains(query) ||
          item.id.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('AI Model Compatibility')),
      body: PageFrame(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Model intelligence',
            title: 'Provider compatibility',
            subtitle: 'Model-specific requirements before adding API keys.',
          ),
          const DemoNotice(
            'Official-doc research only. No API key is stored in this app '
            'and no real rendering is enabled. Model/version, pricing, '
            'entitlement and API schema must be verified on the server.',
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search models or providers',
            ),
            onChanged: (value) => setState(() => search = value),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ChoiceChip(label: const Text('All'), selected: filter == null,
                  onSelected: (_) => setState(() => filter = null)),
              const SizedBox(width: 8),
              for (final item in AiTask.values) ...[
                ChoiceChip(
                  label: Text(item.name),
                  selected: filter == item,
                  onSelected: (_) => setState(() => filter = item),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include retired endpoints'),
            value: showRetired,
            onChanged: (value) => setState(() => showRetired = value ?? false),
          ),
          Text('Verified research: 28 October 2026 · ' +
            matching.length.toString() + ' profiles',
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          for (final model in matching) ...[
            StudioPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ExpansionTile(
                key: ValueKey('api-model-' + model.id),
                tilePadding: EdgeInsets.zero,
                title: Text(model.name, maxLines: 2),
                subtitle: Text(model.provider + ' · ' + model.status.name),
                leading: Icon(model.status == AiStatus.active
                    ? Icons.hub_outlined
                    : model.status == AiStatus.retired
                        ? Icons.block_outlined
                        : Icons.fact_check_outlined),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('API profile: ' + model.id),
                        const SizedBox(height: 8),
                        Text(describe(model)),
                        const SizedBox(height: 8),
                        Text('Workflow: ' + (model.workflow.isEmpty
                            ? model.task.name : model.workflow)),
                        const SizedBox(height: 6),
                        Text('API route: ' + model.route),
                        if (model.apiVersion.isNotEmpty)
                          Text('API version: ' + model.apiVersion),
                        const SizedBox(height: 8),
                        Text('Aspect options: ' + (model.aspects.isEmpty
                            ? 'Not applicable or unknown'
                            : model.aspects.join(', '))),
                        Text('Resolutions: ' + (model.resolutions.isEmpty
                            ? 'Depends on task'
                            : model.resolutions.join(', '))),
                        const SizedBox(height: 8),
                        Text('Media roles: ' + (model.roles.isEmpty
                            ? 'No verified attachments'
                            : model.roles.map((role) => role.name).join(', '))),
                        const SizedBox(height: 8),
                        if (model.notes.isNotEmpty) Text(model.notes),
                        const SizedBox(height: 12),
                        SelectableText(model.docsUrl, style: TextStyle(
                            color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(height: 13),
                        const Text(
                          'A verified backend catalog, working API key, '
                          'entitlements, rate limits, authorized uploads and '
                          'confirmed quote are required to submit jobs.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (matching.isEmpty)
            const StudioPanel(child: Text('No matching model profiles.')),
        ],
      )),
    );
  }
}
