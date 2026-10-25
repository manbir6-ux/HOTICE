import 'package:flutter/material.dart';
import 'projects_generation.dart';
import 'music_studio.dart';
import 'state.dart';
import 'inspiration_catalog.dart';

/// One obvious mode switch rather than a maze of generator settings.
class GenerationHubPage extends StatefulWidget {
  final HotIceStore store;
  final String? initialProjectId;
  final InspirationTemplate? initialTemplate;
  final int templateRevision;
  const GenerationHubPage({
    super.key, required this.store, this.initialProjectId,
    this.initialTemplate, this.templateRevision = 0,
  });

  @override
  State<GenerationHubPage> createState() => _GenerationHubPageState();
}

class _GenerationHubPageState extends State<GenerationHubPage> {
  bool musicMode = false;

  @override
  void didUpdateWidget(covariant GenerationHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.templateRevision != widget.templateRevision) {
      musicMode = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.videocam_outlined, size: 19),
                  label: const Text('Normal video'),
                  selected: !musicMode,
                  onSelected: (_) => setState(() => musicMode = false),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.music_video_outlined, size: 19),
                  label: const Text('Music video studio'),
                  selected: musicMode,
                  onSelected: (_) => setState(() => musicMode = true),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 8),
                  child: Text(
                    'TEST PREVIEW',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                        letterSpacing: 1.4, color: primary),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          // Both editors stay mounted: switching modes must not silently
          // erase a partially typed scene or storyboard.
          child: IndexedStack(
            index: musicMode ? 1 : 0,
            sizing: StackFit.expand,
            children: [
              GenerationPage(
                store: widget.store,
                initialProjectId: widget.initialProjectId,
                initialTemplate: widget.initialTemplate,
                templateRevision: widget.templateRevision,
              ),
              MusicVideoStudioPage(
                store: widget.store,
                initialProjectId: widget.initialProjectId,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
