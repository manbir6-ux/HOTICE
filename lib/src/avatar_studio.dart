import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'actor_archive.dart';
import 'actor_vault.dart';
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
  final ActorVault? vault;
  const AvatarsPage({super.key, required this.store, this.vault});

  @override
  State<AvatarsPage> createState() => _AvatarsPageState();
}

class _AvatarsPageState extends State<AvatarsPage> {
  late final ActorVault _vault;

  @override
  void initState() {
    super.initState();
    _vault = widget.vault ?? ActorVault();
  }

  final name = TextEditingController();
  final identityNotes = TextEditingController();
  String style = 'Photorealistic';
  bool _autoTouchUp = false;
  String? editingName;
  bool _scanInProgress = false;
  bool _transferBusy = false;
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
    final account = widget.store.selectedAccount;
    String? savedVaultId;
    try {
      savedVaultId = await _vault.save(
        StudioAvatar(actorName, style,
          identityNotes: identityNotes.text,
          capturePaths: result.paths,
          autoTouchUp: _autoTouchUp,
        ),
        account: account,
      );
    } catch (_) {
      // Never tell the user a photo was encrypted when OS key storage fails.
      // Keep this Actor in the active session; let the user export a backup.
    }
    if (!mounted || widget.store.selectedAccount != account) {
      if (savedVaultId != null) {
        try { await _vault.delete(savedVaultId, account: account); } catch (_) {}
      }
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
      return;
    }
    final saved = widget.store.addAvatar(actorName, style,
        identityNotes: identityNotes.text, capturePaths: result.paths,
        autoTouchUp: _autoTouchUp, vaultId: savedVaultId);
    if (!saved) {
      if (savedVaultId != null) {
        try { await _vault.delete(savedVaultId, account: account); } catch (_) {}
      }
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
    } else {
      setState(() {
        name.clear();
        identityNotes.clear();
        _autoTouchUp = false;
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved
          ? savedVaultId == null
              ? 'Actor created for this session only. Encrypted storage was '
                'unavailable; export a private backup before closing HOTICE.'
              : 'Actor saved in the encrypted local vault with '
                '${result.paths.length} camera angles. No cloud upload.'
          : 'Could not save Actor. Camera captures were discarded.'),
    ));
  }

  @override
  void dispose() {
    name.dispose();
    identityNotes.dispose();
    super.dispose();
  }

  Future<void> saveAvatar() async {
    if (editingName == null || _transferBusy) return;
    final oldName = editingName!;
    final account = widget.store.selectedAccount;
    final matches = widget.store.avatars.where((a) => a.name == oldName);
    if (matches.length != 1) return;
    final current = matches.single;
    final editedName = name.text.trim();
    if (editedName.isEmpty || editedName.toLowerCase() == 'none' ||
        widget.store.avatars.any((a) =>
          a.name != oldName &&
          a.name.toLowerCase() == editedName.toLowerCase())) {
      _feedback('Actor name is invalid or already used.');
      return;
    }
    setState(() => _transferBusy = true);
    try {
      if (current.vaultId != null) {
        await _vault.save(StudioAvatar(
          editedName, style,
          identityNotes: identityNotes.text,
          capturePaths: current.capturePaths,
          autoTouchUp: _autoTouchUp,
          vaultId: current.vaultId,
        ), account: account);
      }
      if (!mounted || widget.store.selectedAccount != account) return;
      final changed = widget.store.editAvatar(
        oldName, editedName, style,
        identityNotes: identityNotes.text,
        autoTouchUp: _autoTouchUp,
      );
      if (changed) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {
          editingName = null;
          name.clear();
          identityNotes.clear();
          _autoTouchUp = false;
        });
      }
      _feedback(changed ? 'Actor details updated and saved locally.'
          : 'Could not update Actor details.');
    } catch (_) {
      _feedback('Could not update the encrypted Actor record. '
          'Original Actor details were preserved.');
    } finally {
      if (mounted) setState(() => _transferBusy = false);
    }
  }

  void startEditing(StudioAvatar avatar) {
    setState(() {
      editingName = avatar.name;
      name.text = avatar.name;
      style = avatar.style;
      identityNotes.text = avatar.identityNotes;
      _autoTouchUp = avatar.autoTouchUp;
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
        content: const Text('This removes the Actor and its local encrypted '
          'record, if saved. Historical scene drafts and exported ZIP copies '
          'are not automatically deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep character')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (avatar.vaultId != null) {
      try {
        await _vault.delete(avatar.vaultId!,
          account: widget.store.selectedAccount);
      } catch (_) {
        _feedback('Could not delete encrypted Actor data. '
            'The Actor was kept to prevent unexpected restoration.');
        return;
      }
    }
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

  Future<bool> _confirmFaceTransfer(String action) async {
    if (!mounted) return false;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action Actor photos?'),
        content: const Text(
          'Actor packages contain recognizable face photos. This testing '
          'format is an UNENCRYPTED ZIP. Anyone who obtains the exported '
          'file can view the photos. Share only with consent, store it '
          'privately, and delete unwanted copies. No cloud upload is made.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    return agreed == true;
  }

  void _feedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _exportActor(StudioAvatar actor) async {
    if (_transferBusy) return;
    if (actor.capturePaths.isEmpty) {
      _feedback('This demo Actor has no guided photos to export.');
      return;
    }
    if (!await _confirmFaceTransfer('Export') || !mounted) return;
    setState(() => _transferBusy = true);
    try {
      final zipped = await ActorArchiveCodec.exportActor(actor);
      final safeName = actor.name.replaceAll(
          RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save sensitive HOTICE Actor archive',
        fileName: 'HOTICE_${safeName}.hoticeactor',
        bytes: zipped,
      );
      if (!mounted) return;
      _feedback(saved == null
          ? 'Export cancelled.'
          : 'Actor exported. Protect the unencrypted file.');
    } catch (_) {
      _feedback('Could not export this Actor. Check the captured photos.');
    } finally {
      if (mounted) setState(() => _transferBusy = false);
    }
  }

  Future<void> _importActor() async {
    if (_transferBusy) return;
    if (!await _confirmFaceTransfer('Import') || !mounted) return;
    setState(() => _transferBusy = true);
    List<String> created = [];
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['hoticeactor', 'zip'],
      );
      if (picked == null) return;
      final length = picked.lengthSync() ?? await picked.length();
      if (length == null || length < 1 ||
          length > ActorArchiveCodec.maxArchiveBytes) {
        throw const FormatException('Actor package exceeds safety size limit.');
      }
      final profile = ActorArchiveCodec.decode(await picked.readAsBytes());
      if (!mounted) return;
      var actorName = profile.name;
      var n = 2;
      while (widget.store.avatars.any(
          (a) => a.name.toLowerCase() == actorName.toLowerCase())) {
        final suffix = ' ($n)';
        actorName = profile.name.substring(
            0, profile.name.length > 60 - suffix.length
              ? 60 - suffix.length : profile.name.length) + suffix;
        n++;
        if (n > 999) throw StateError('Too many duplicate Actor names.');
      }
      created = await ActorArchiveCodec.importToTemporaryFolder(profile);
      if (!mounted) return;
      final account = widget.store.selectedAccount;
      String? vaultId;
      try {
        vaultId = await _vault.save(StudioAvatar(
          actorName, profile.style,
          identityNotes: profile.notes, capturePaths: created,
          autoTouchUp: profile.autoTouchUp,
        ), account: account);
      } catch (_) {
        // Import is allowed for the current session, but it is NOT described
        // as an encrypted persistent Actor when secure storage is unavailable.
      }
      if (!mounted || widget.store.selectedAccount != account) {
        if (vaultId != null) {
          try { await _vault.delete(vaultId, account: account); } catch (_) {}
        }
        return;
      }
      final success = widget.store.addAvatar(
        actorName, profile.style,
        identityNotes: profile.notes, capturePaths: created,
        autoTouchUp: profile.autoTouchUp, vaultId: vaultId,
      );
      if (!success && vaultId != null) {
        try { await _vault.delete(vaultId, account: account); } catch (_) {}
      }
      if (!success) {
        throw StateError('Actor profile could not be saved.');
      }
      created = [];
      _feedback('Actor imported with ${profile.photos.length} real photos. '
          '${vaultId == null ? 'Session only — save a backup before closing.' : 'Encrypted on this device.'}');
    } catch (_) {
      _feedback('Import rejected. Check ZIP safety, format and photos.');
    } finally {
      for (final path in created) {
        try { await File(path).delete(); } catch (_) {}
      }
      if (mounted) setState(() => _transferBusy = false);
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
                  'Camera working copies are temporary; saved Actors have encrypted local records. '
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
            'Create Actors with seven guided face photos. When device secure '
            'storage is available, your originals are saved in an encrypted '
            'local vault and restored after restart. Exported ZIPs are '
            'unencrypted. This is not a 3D scan or cloud backup.',
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
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto touch-up (optional)'),
                  subtitle: const Text(
                    'Gentle light/colour correction on scene references. '
                    'Natural captured photos remain unchanged.',
                  ),
                  value: _autoTouchUp,
                  onChanged: (value) => setState(() => _autoTouchUp = value),
                ),
                const SizedBox(height: 10),
                if (editingName == null) ...[
                  const Text(
                    'Next: guided front-camera capture (7 face angles). '
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
                    _autoTouchUp = false;
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
          OutlinedButton.icon(
            onPressed: _transferBusy ? null : _importActor,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import Actor (.hoticeactor)'),
          ),
          const SizedBox(height: 10),
          const Text('Exports contain private face photos in an unencrypted testing ZIP.',
            style: TextStyle(fontSize: 12)),
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
                          ? '${avatar.capturePaths.length} angle photos · '
                            '${avatar.vaultId == null ? 'session only' : 'encrypted vault'}'
                          : avatar.identityNotes.isEmpty
                              ? 'Add identity notes later'
                              : 'Identity notes ready for prompts')),
                  isThreeLine: false,
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Character options',
                    onSelected: (action) {
                      if (action == 'edit') {
                        startEditing(avatar);
                      } else if (action == 'export') {
                        _exportActor(avatar);
                      } else if (action == 'delete') {
                        deleteAvatar(avatar);
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit actor')),
                      PopupMenuItem(value: 'export', child: Text('Export Actor ZIP')),
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
