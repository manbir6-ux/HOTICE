import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'smart_references.dart';
import 'live_face_capture.dart';
import 'face_capture_quality.dart';
import 'dart:io';
import 'avatar_identity.dart';
import 'design.dart';
import 'state.dart';

/// Local character workshop with separate guided live 2D camera capture.
/// The five-pose illustration remains a design preview, not a mesh scanner.
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
  bool showScanGuide = false;
  bool showLiveCapture = false;
  String? captureTarget;
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
    final created = editingName == null
        ? widget.store.addAvatar(name.text, style,
            identityNotes: identityNotes.text)
        : widget.store.editAvatar(editingName!, name.text, style,
            identityNotes: identityNotes.text);
    if (created) {
      name.clear();
      identityNotes.clear();
      setState(() => editingName = null);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(created
          ? 'Character profile saved in this demo workspace.'
          : 'That character name is already used. Try another name.')),
    );
  }

  void startEditing(StudioAvatar avatar) {
    setState(() {
      editingName = avatar.name;
      name.text = avatar.name;
      style = avatar.style;
      identityNotes.text = avatar.identityNotes;
      showScanGuide = false;
      showLiveCapture = false;
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
    if (editingName == avatar.name) {
      setState(() {
        editingName = null;
        name.clear();
        identityNotes.clear();
      });
    }
  }

  Future<void> startRealCapture(StudioAvatar avatar) async {
    if (widget.store.avatarPackFor(avatar.name).assets.length > 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Remove some previous photos before adding five more.'),
      ));
      return;
    }
    final photos = await Navigator.of(context).push<List<CapturedFacePhoto>>(
      MaterialPageRoute(builder: (_) => const LiveFaceScanPage()),
    );
    if (photos == null || photos.isEmpty) return;
    const viewByPose = <CapturePose, FaceView>{
      CapturePose.front: FaceView.front,
      CapturePose.left45: FaceView.left45,
      CapturePose.right45: FaceView.right45,
      CapturePose.left90: FaceView.left90,
      CapturePose.right90: FaceView.right90,
    };
    var saved = 0;
    for (final shot in photos) {
      final success = widget.store.addAvatarReference(
        avatar.name,
        AvatarReference(
          id: createLocalProjectId(),
          ownerName: avatar.name,
          role: ReferenceRole.avatar,
          format: ReferenceFormat.image,
          mimeType: 'image/jpeg',
          localPath: shot.path,
          view: viewByPose[shot.pose],
          ownedTemporaryFile: true,
          // These are 2D photos, never claim a verified 3D mesh.
          isScanVerified: false,
        ),
      );
      if (success) {
        saved++;
      } else {
        try { await File(shot.path).delete(); } catch (_) {}
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved.toString() +
          ' guided 2D face references saved for this session. Not a 3D mesh.'),
    ));
  }

  Future<void> importFacePhoto(StudioAvatar avatar) async {
    final view = await showModalBottomSheet<FaceView>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Label this face view'),
                subtitle: Text('Choose the angle shown in your actual photo.')),
            for (final angle in FaceView.values)
              ListTile(
                title: Text(angle.label),
                onTap: () => Navigator.pop(ctx, angle),
              ),
          ],
        ),
      ),
    );
    if (!mounted || view == null) return;
    final consent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import face reference?'),
        content: const Text(
          'This photo contains sensitive likeness data. HOTICE will retain '
          'only a temporary local picker file reference in this demo session. '
          'It is not a verified 3D scan, encrypted vault, or cloud backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Choose photo')),
        ],
      ),
    );
    if (!mounted || consent != true) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (!mounted || file == null) return;
      final fileBytes = file.lengthSync() ?? await file.length();
      if (!mounted) return;
      final ext = (file.extension ?? '').toLowerCase();
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };
      final path = file.path;
      if (mime == null || path == null || path.isEmpty ||
          fileBytes == null || fileBytes <= 0 || fileBytes > 15 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose a JPG/PNG/WebP photo under 15 MB.'),
        ));
        return;
      }
      final saved = widget.store.addAvatarReference(avatar.name, AvatarReference(
        id: createLocalProjectId(),
        ownerName: avatar.name,
        role: ReferenceRole.avatar,
        format: ReferenceFormat.image,
        mimeType: mime,
        localPath: path,
        view: view,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved
          ? '${view.label} reference added for this session.'
          : 'Could not add reference. Check avatar and limit (16).')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Image selection failed or was cancelled.'),
      ));
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
                const Text('Reusable character identity card · Text-only demo'),
                const SizedBox(height: 16),
                SelectableText(card),
                const SizedBox(height: 16),
                const DemoNotice(
                  'HOTICE can add these notes to demo video prompts. Real 3D scanning, facial matching and provider-specific references are not active.',
                ),
                const SizedBox(height: 14),
                Text('Imported face references: '
                    '${widget.store.avatarPackFor(avatar.name).assets.length} '
                    '(session only)'),
                for (final photo in widget.store.avatarPackFor(avatar.name).assets)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_outlined),
                    title: Text(photo.view?.label ?? 'Reference'),
                    subtitle: const Text('Unverified face photo'),
                    trailing: IconButton(
                      tooltip: 'Remove this reference',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        widget.store.removeAvatarReference(avatar.name, photo.id);
                        Navigator.pop(ctx);
                      },
                    ),
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
            'Beta: live guided multi-angle 2D capture is available on Android/iOS with consent, plus manual references. Photos are temporarily cached, not encrypted. No 3D reconstruction, identity verification or cloud storage.'
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Quick character'),
                selected: !showScanGuide && !showLiveCapture,
                onSelected: (_) => setState(() {
                  showScanGuide = false;
                  showLiveCapture = false;
                }),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.face_retouching_natural_rounded, size: 18),
                label: const Text('3D face-scan guide'),
                selected: showScanGuide,
                onSelected: (_) => setState(() {
                  showScanGuide = true;
                  showLiveCapture = false;
                }),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.camera_front_outlined, size: 18),
                label: const Text('Live face capture'),
                selected: showLiveCapture,
                onSelected: (_) => setState(() {
                  showLiveCapture = true;
                  showScanGuide = false;
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showLiveCapture) StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On-device guided capture',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 9),
                const Text('Capture five face views with camera framing, head angles and eyes-open checks. This creates real 2D reference photos, not a 3D model. Temporary cache only.'),
                const SizedBox(height: 16),
                if (widget.store.avatars.isEmpty)
                  const Text('Save a character below before scanning its face.'),
                if (widget.store.avatars.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('scan-avatar-selector'),
                    initialValue: widget.store.avatars.any((a) => a.name == captureTarget)
                        ? captureTarget : widget.store.avatars.first.name,
                    decoration: const InputDecoration(labelText: 'Attach to character'),
                    items: [for (final avatar in widget.store.avatars)
                      DropdownMenuItem(value: avatar.name, child: Text(avatar.name))],
                    onChanged: (value) => setState(() => captureTarget = value),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      final chosen = widget.store.avatars.firstWhere(
                        (a) => a.name == captureTarget,
                        orElse: () => widget.store.avatars.first,
                      );
                      startRealCapture(chosen);
                    },
                    icon: const Icon(Icons.face_retouching_natural),
                    label: const Text('Start live scanner'),
                  ),
                ],
              ],
            ),
          ),
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
                Text(editingName == null ? 'New character' : 'Edit ' + editingName!,
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
                  initialValue: style,
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
                  label: editingName == null ? 'Save character' : 'Save changes',
                  icon: Icons.person_add_alt_1_rounded,
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
                  'Character library',
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
                    backgroundColor: accent.withValues(alpha: .14),
                    child: Text(avatar.name[0].toUpperCase()),
                  ),
                  title: Text(avatar.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(avatar.style +
                      ' · ${widget.store.avatarPackFor(avatar.name).assets.length} photos · ' +
                      (avatar.identityNotes.isEmpty
                          ? 'Add identity notes later'
                          : 'Identity notes ready')),

                  isThreeLine: false,
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Character options',
                    onSelected: (action) {
                      if (action == 'scan') {
                        startRealCapture(avatar);
                      } else if (action == 'import') {
                        importFacePhoto(avatar);
                      } else if (action == 'edit') {
                        startEditing(avatar);
                      } else if (action == 'delete') {
                        deleteAvatar(avatar);
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'scan', child: Text('Start live guided face capture')),
                      PopupMenuItem(value: 'import', child: Text('Add face reference photo')),
                      PopupMenuItem(value: 'edit', child: Text('Edit character')),
                      PopupMenuItem(value: 'delete', child: Text('Delete character')),
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
