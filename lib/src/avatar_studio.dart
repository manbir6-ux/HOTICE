import 'dart:io';
import 'package:flutter/material.dart';
import 'guided_actor_camera.dart';
import 'package:flutter/services.dart';
import 'avatar_identity.dart';
import 'design.dart';
import 'state.dart';

/// Consent-first Actor workshop; new Actors require mobile camera capture.
/// Captures are temporary local photos, not persistent biometric 3D models.
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
  String? editingName;
  bool _scanInProgress = false;
  Future<void> scanActor() async {
    final actorName = name.text.trim();
    if (actorName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an Actor name before scanning.')),
      );
      return;
    }
    if (_scanInProgress) return;
    if (editingName != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish editing before creating a new scanned Actor.')),
      );
      return;
    }
    if (widget.store.avatars.any((a) =>
        a.name.toLowerCase() == actorName.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This Actor already exists. Choose another name.')),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _scanInProgress = true);
    ActorCameraResult? result;
    try {
      result = await Navigator.of(context).push<ActorCameraResult>(
      MaterialPageRoute(
        builder: (_) => GuidedActorCameraPage(actorName: actorName),
      ),
      );
    } finally {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _scanInProgress = false);
      }
    }
    if (result == null) return;
    if (!mounted) {
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
      return;
    }
    final saved = widget.store.addAvatar(actorName, style,
        identityNotes: identityNotes.text, capturePaths: result.paths);
    if (!saved) {
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
    } else {
      setState(() {
        name.clear();
        identityNotes.clear();
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved
          ? 'Actor created with 3 temporary camera references. No upload.'
          : 'Could not save Actor. Camera captures were discarded.'),
    ));
  }

  @override
  void dispose() {
    name.dispose();
    identityNotes.dispose();
    super.dispose();
  }

  void saveAvatar() {
    // New Actors MUST pass the mobile camera flow. Only existing Actor
    // metadata may be edited here, never create an unscanned identity.
    if (editingName == null) return;
    final created = widget.store.editAvatar(
      editingName!, name.text, style,
      identityNotes: identityNotes.text,
    );
    if (created) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        editingName = null;
        name.clear();
        identityNotes.clear();
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(created
          ? 'Actor details updated.'
          : 'Actor name is invalid or already used.'),
    ));
  }

  void startEditing(StudioAvatar avatar) {
    setState(() {
      editingName = avatar.name;
      name.text = avatar.name;
      style = avatar.style;
      identityNotes.text = avatar.identityNotes;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit the character in the form above.')),
    );
  }

  Future<void> deleteAvatar(StudioAvatar avatar) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ' + avatar.name + '?'),
        content: const Text('This removes the local character preset. Previous scene drafts remain historical snapshots.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep character')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    widget.store.removeAvatar(avatar.name);
    for (final path in avatar.capturePaths) {
      try { await File(path).delete(); } catch (_) {}
    }
    if (!mounted) return;
    if (editingName == avatar.name) {
      setState(() {
        editingName = null;
        name.clear();
        identityNotes.clear();
      });
    }
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
                const Text('Reusable Actor profile · appearance notes and local references'),
                const SizedBox(height: 16),
                SelectableText(card),
                const SizedBox(height: 16),
                const DemoNotice(
                  'Camera references stay on this device temporarily, not cloud-synced. '
                  'They are not 3D meshes, biometric identity verification or guaranteed '
                  'AI face-locking.',
                ),
                if (avatar.capturePaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${avatar.capturePaths.length} captured camera angles (session only)'),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final path in avatar.capturePaths)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(path), height: 105, width: 86,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox(width: 86, height: 105,
                                    child: Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                    ],
                  ),
                ],
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
            eyebrow: 'Actor identity',
            title: 'Actors Studio',
            subtitle: 'Name your Actor, capture guided face angles and reuse references across scenes.',
          ),
          const DemoNotice(
            'New Actors are created only after guided front-camera capture '
            'with your consent. The photos stay temporarily on this device. '
            'This is not a 3D face scan or cloud backup.',
          ),
          const SizedBox(height: 16),
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(editingName == null ? 'New actor' : 'Edit ' + editingName!,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 7),
                const Text('A few details now make it easier to describe the same person in every scene.'),
                const SizedBox(height: 17),
                TextField(
                  controller: name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Actor name',
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
                if (editingName == null) ...[
                  const Text(
                    'Next: guided front-camera capture (front, left and right). '
                    'HOTICE creates the Actor only after the capture is complete.',
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: _scanInProgress
                        ? 'Opening camera...'
                        : 'Continue to guided camera',
                    icon: Icons.camera_front_outlined,
                    onPressed: _scanInProgress ? null : scanActor,
                  ),
                ] else
                  PrimaryButton(
                    label: 'Save changes',
                    icon: Icons.save_rounded,
                    onPressed: saveAvatar,
                  ),
                if (editingName != null)
                  TextButton(
                    onPressed: () => setState(() {
                      editingName = null;
                      name.clear();
                      identityNotes.clear();
                    }),
                    child: const Text('Cancel editing'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Icon(Icons.collections_bookmark_outlined, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Actors library',
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
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
                      ' · ' + (avatar.capturePaths.isNotEmpty
                          ? '${avatar.capturePaths.length} guided angle photos · temporary'
                          : avatar.identityNotes.isEmpty
                              ? 'Add identity notes later'
                              : 'Identity notes ready for prompts')),
                  isThreeLine: false,
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Character options',
                    onSelected: (action) {
                      if (action == 'edit') {
                        startEditing(avatar);
                      } else if (action == 'delete') {
                        deleteAvatar(avatar);
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit actor')),
                      PopupMenuItem(value: 'delete', child: Text('Delete actor')),
                    ],
                  ),
                  onTap: () => openProfile(avatar),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
