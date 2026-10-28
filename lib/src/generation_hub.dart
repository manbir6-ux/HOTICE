import 'package:flutter/material.dart';
import 'backend_auth.dart';
import 'backend_dry_run.dart';
import 'projects_generation.dart';
import 'music_studio.dart';
import 'state.dart';

/// One obvious mode switch rather than a maze of generator settings.
class GenerationHubPage extends StatefulWidget {
  final HotIceStore store;
  final String? initialProjectId;
  final bool isActive;
  final BackendAuthClient? backendClient;
  const GenerationHubPage({super.key, required this.store, this.initialProjectId, this.isActive = true, this.backendClient});

  @override
  State<GenerationHubPage> createState() => _GenerationHubPageState();
}

class _GenerationHubPageState extends State<GenerationHubPage> {
  int mode = 0;

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
                  selected: mode == 0,
                  onSelected: (_) => setState(() => mode = 0),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.music_video_outlined, size: 19),
                  label: const Text('Music video studio'),
                  selected: mode == 1,
                  onSelected: (_) => setState(() => mode = 1),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.cloud_sync_outlined, size: 19),
                  label: const Text('Server dry run'),
                  selected: mode == 2,
                  onSelected: (_) => setState(() => mode = 2),
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
            index: mode,
            sizing: StackFit.expand,
            children: [
              GenerationPage(
                store: widget.store,
                initialProjectId: widget.initialProjectId,
              ),
              MusicVideoStudioPage(
                store: widget.store,
                initialProjectId: widget.initialProjectId,
                audioActive: widget.isActive && mode == 1,
              ),
              BackendDryRunPage(client: widget.backendClient,
                isAuthenticated: widget.store.backendAuthenticated),
            ],
          ),
        ),
      ],
    );
  }
}
