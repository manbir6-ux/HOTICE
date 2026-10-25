import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'avatar_identity.dart';
import 'design.dart';
import 'state.dart';

/// Local-only character workshop. The scan guide never requests the camera,
/// captures a face, or constructs a 3D model. Those require later integrations.
class AvatarsPage extends StatefulWidget {
  final HotIceStore store;
  const AvatarsPage({super.key, required this.store});

  @override
  State<AvatarsPage> createState() => _AvatarsPageState();
}

class _AvatarsPageState extends State<AvatarsPage> {
  final name = TextEditingController();
  final identityNotes = TextEditingController();
  String style = 'Photorealistic';
  bool showScanGuide = false;
  int poseIndex = 0;

  static const poses = <({String title, String hint, IconData icon})>[
    (title: 'Front portrait', hint: 'Even lighting, neutral expression and no face filters.', icon: Icons.face_outlined),
    (title: 'Left profile', hint: 'Turn about 45 degrees. Keep the camera at eye level.', icon: Icons.rotate_left_rounded),
    (title: 'Right profile', hint: 'Turn about 45 degrees to the other side.', icon: Icons.rotate_right_rounded),
    (title: 'Expression', hint: 'Keep lighting consistent; capture a natural smile later.', icon: Icons.sentiment_satisfied_alt_outlined),
    (title: 'Full-body reference', hint: 'Use a clear outfit and consistent body proportions.', icon: Icons.accessibility_new_rounded),
  ];

  @override
  void dispose() {
    name.dispose();
    identityNotes.dispose();
    super.dispose();
  }

  void saveAvatar() {
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your character a name first.')),
      );
      return;
    }
    final created = widget.store.addAvatar(
      name.text,
      style,
      identityNotes: identityNotes.text,
    );
    if (created) {
      name.clear();
      identityNotes.clear();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(created
          ? 'Character profile added to this demo workspace.'
          : 'That character name is already used. Try another name.')),
    );
  }

  void openProfile(StudioAvatar avatar) {
    final card = AvatarPromptComposer.identityCard(avatar);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(avatar.name, style: Theme.of(ctx).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text('Reusable character identity card · Text-only demo'),
                const SizedBox(height: 16),
                SelectableText(card),
                const SizedBox(height: 16),
                const DemoNotice(
                  'HOTICE can add these notes to demo video prompts. Real 3D scanning, facial matching and provider-specific references are not active.',
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: card));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy identity notes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Character identity',
            title: 'Avatar Studio',
            subtitle: 'Create once. Reuse the same character description across your shots.',
          ),
          const DemoNotice(
            'Testing mode: character descriptions work as local presets. No face images, camera scans, biometric data or 3D meshes are collected or stored.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Quick character'),
                selected: !showScanGuide,
                onSelected: (_) => setState(() => showScanGuide = false),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.face_retouching_natural_rounded, size: 18),
                label: const Text('3D face-scan guide'),
                selected: showScanGuide,
                onSelected: (_) => setState(() => showScanGuide = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showScanGuide) ...[
            StudioPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Face capture preparation',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 7),
                  const Text(
                    'Preview the planned multi-angle capture process. Camera capture, depth reconstruction and facial embeddings will be built and tested in a later phase.',
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      width: 244,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF182B50), Color(0xFF47306F), Color(0xFF112D43)],
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 165,
                            height: 185,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(70),
                              border: Border.all(color: const Color(0xFF84E8F7), width: 2),
                            ),
                          ),
                          Icon(poses[poseIndex].icon, color: Colors.white, size: 118),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Text(
                              'GUIDE ' + (poseIndex + 1).toString() + '/5',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(poses[poseIndex].title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(poses[poseIndex].hint),
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: poseIndex == 0
                            ? null
                            : () => setState(() => poseIndex--),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Back'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: poseIndex == poses.length - 1
                              ? () => setState(() => poseIndex = 0)
                              : () => setState(() => poseIndex++),
                          icon: Icon(poseIndex == poses.length - 1
                              ? Icons.replay_rounded : Icons.chevron_right),
                          label: Text(poseIndex == poses.length - 1
                              ? 'Review again' : 'Next angle'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No images are being captured. This walkthrough is a design preview, not a completed scan.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New character',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 7),
                const Text('A few details now make it easier to describe the same person in every scene.'),
                const SizedBox(height: 17),
                TextField(
                  controller: name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Character name',
                    hintText: 'e.g. The Explorer',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: style,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Look and feel'),
                  items: const [
                    DropdownMenuItem(value: 'Photorealistic',
                        child: Text('Photorealistic')),
                    DropdownMenuItem(value: 'Cinematic',
                        child: Text('Cinematic')),
                    DropdownMenuItem(value: 'Animated',
                        child: Text('Animated')),
                    DropdownMenuItem(value: 'Stylized',
                        child: Text('Stylized 3D')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => style = v);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: identityNotes,
                  maxLength: 350,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Appearance notes (optional)',
                    alignLabelWithHint: true,
                    hintText: 'Hair, beard, eye colour, clothing, distinctive features...',
                  ),
                ),
                const SizedBox(height: 13),
                PrimaryButton(
                  label: 'Save character',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: saveAvatar,
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Icon(Icons.collections_bookmark_outlined, color: accent),
              const SizedBox(width: 8),
              Text('Character library',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.store.avatars.isEmpty)
            const StudioPanel(
              child: Text('No characters yet. Create one above to start your library.'),
            ),
          for (final avatar in widget.store.avatars)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StudioPanel(
                padding: const EdgeInsets.all(8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: accent.withOpacity(.14),
                    child: Text(avatar.name[0].toUpperCase()),
                  ),
                  title: Text(avatar.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(avatar.style +
                      ' · ' + (avatar.identityNotes.isEmpty
                          ? 'Add identity notes later'
                          : 'Identity notes ready for prompts')),
                  isThreeLine: false,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openProfile(avatar),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
