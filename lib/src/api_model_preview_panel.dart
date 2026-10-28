import 'package:flutter/material.dart';
import 'model_registry.dart';

/// One-prompt, source-backed future API form. It deliberately cannot run jobs.
/// The live backend must replace this research view with its verified manifest.
class ApiVideoPreviewPanel extends StatefulWidget {
  const ApiVideoPreviewPanel({super.key, required this.prompt});
  final String prompt;
  @override
  State<ApiVideoPreviewPanel> createState() => _ApiVideoPreviewPanelState();
}

class _ApiVideoPreviewPanelState extends State<ApiVideoPreviewPanel> {
  String selectedId = 'google/omni-1.1:text-video';
  String? aspect = '16:9';
  String? resolution = '360p';
  int? seconds;

  AiCapability get model => HoticeAiCatalog.find(selectedId)!;

  void changeModel(String id) {
    setState(() {
      selectedId = id;
      final next = model;
      aspect = next.aspects.isEmpty ? null : next.aspects.first;
      resolution = next.resolutions.isEmpty ? null : next.resolutions.first;
      seconds = next.controlsDuration ? next.minSeconds : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = model;
    final options = HoticeAiCatalog.entries
        .where((item) => item.task == AiTask.video &&
            item.status != AiStatus.retired)
        .toList();
    final selectedAspect = aspect;
    final selectedResolution = resolution;
    final sample = AiRequest(
      task: AiTask.video,
      prompt: widget.prompt.trim().isEmpty
          ? 'Example scene — replace with your own main prompt'
          : widget.prompt,
      seconds: seconds,
      aspect: selectedAspect,
      resolution: selectedResolution,
    );
    final errors = selected.validate(sample);
    return ExpansionTile(
      key: const ValueKey('source-model-preview'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.hub_outlined),
      title: const Text('Real API model settings preview'),
      subtitle: const Text('Source-backed inputs; no API calls or billing'),
      children: [
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('source-model-picker-' + selectedId),
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Research API model'),
          items: [for (final option in options)
            DropdownMenuItem(
              value: option.id,
              child: Text(option.name, overflow: TextOverflow.ellipsis),
            ),
          ],
          onChanged: (value) {
            if (value != null) changeModel(value);
          },
        ),
        const SizedBox(height: 13),
        Text('Provider: ' + selected.provider +
            ' · Status: ' + selected.status.name,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        if (selected.aspects.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('API output dimensions',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [for (final value in selected.aspects)
              ChoiceChip(
                label: Text(value),
                selected: value == selectedAspect,
                onSelected: (_) => setState(() => aspect = value),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (selected.resolutions.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey('source-res-' + selectedId),
            initialValue: selectedResolution,
            decoration: const InputDecoration(labelText: 'API resolution'),
            items: [for (final value in selected.resolutions)
              DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => resolution = value),
          ),
        const SizedBox(height: 12),
        if (!selected.controlsDuration)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Output length is automatic for this model. An exact seconds '
              'parameter is not documented; HOTICE will not silently invent one.',
              style: TextStyle(fontSize: 12),
            ),
          )
        else if (selected.minSeconds != null && selected.maxSeconds != null)
          DropdownButtonFormField<int>(
            key: ValueKey('source-duration-' + selectedId),
            initialValue: seconds,
            decoration: const InputDecoration(labelText: 'API duration'),
            items: [
              for (var n = selected.minSeconds!;
                  n <= selected.maxSeconds! && n <= 30; n++)
                DropdownMenuItem(value: n, child: Text(n.toString() + ' seconds')),
            ],
            onChanged: (value) => setState(() => seconds = value),
          )
        else
          const Text('Duration controls are not verified for this profile.',
              style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Verified input roles: ' +
              (selected.roles.isEmpty ? 'text only / unknown'
                  : selected.roles.map((r) => r.name).join(', '))),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Images: ' + (selected.imageLimit?.toString() ?? 'unknown') +
              ' · Native 3D mesh: ' + (selected.meshLimit == 0 ? 'not supported' : 'verify'))),
        const SizedBox(height: 10),
        if (errors.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Research parameters fit this model profile. '
                'This does not authorize a request or confirm pricing.',
                style: TextStyle(fontSize: 12)),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Not ready: ' + errors.first,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Avatar and scene attachments are NOT automatically converted '
          'to first/last frames. A real server adapter must validate every '
          'reference, MIME type, upload permission, price and model entitlement.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
