import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'actor_archive.dart';
import 'actor_transfer_cipher.dart';
import 'actor_backup_password_dialog.dart';
import 'actor_vault.dart';
import 'package:flutter/material.dart';
import 'guided_actor_camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
  bool _autoTouchUp = false;
  String? editingName;
  bool _scanInProgress = false;
  bool _transferBusy = false;
  bool _vaultReady = false;
  bool _vaultBusy = false;
  String? _vaultProblem;

  bool get _deviceVaultAvailable => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _restoreVault();
  }

  Future<void> _restoreVault() async {
    // Flutter widget tests and unsupported desktop platforms have no Keychain/
    // Keystore. Continue as a clearly marked ephemeral demonstration there.
    if (!_deviceVaultAvailable) {
      if (mounted) setState(() => _vaultReady = true);
      return;
    }
    final account = widget.store.selectedAccount;
    try {
      final loaded = await ActorLocalVault.instance.load(account);
      if (!mounted || widget.store.selectedAccount != account) {
        for (final actor in loaded.actors) {
          for (final path in actor.capturePaths) {
            try { await File(path).delete(); } catch (_) {}
          }
        }
        return;
      }
      // Drop old session-only paths for deleted/corrupt entries while
      // atomically replacing restored Actor photos in this demo workspace.
      final previousPaths = widget.store.avatars
          .expand((actor) => actor.capturePaths)
          .toSet();
      widget.store.reconcileVaultActors(loaded.actors);
      final newPaths = loaded.actors
          .expand((actor) => actor.capturePaths)
          .toSet();
      for (final oldPath in previousPaths.difference(newPaths)) {
        try { await File(oldPath).delete(); } catch (_) {}
      }
      if (!mounted || widget.store.selectedAccount != account) return;
      if (mounted) {
        setState(() {
          _vaultReady = true;
          _vaultProblem = loaded.failedEntries == 0 ? null
              : '${loaded.failedEntries} encrypted Actor record(s) could not be opened.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _vaultReady = false;
          _vaultProblem = 'Secure Actor storage is unavailable. Do not scan until it is restored.';
        });
      }
    }
  }

  bool _sameActiveAccount(String account) =>
      mounted && widget.store.signedIn &&
      widget.store.selectedAccount == account;

  Future<void> _persistActor(StudioAvatar actor, {
    required String account,
    String? formerName,
  }) async {
    if (!_sameActiveAccount(account)) {
      throw StateError('Account changed during Actor operation.');
    }
    if (!_deviceVaultAvailable) return;
    if (!_vaultReady) throw StateError('Secure Actor vault is not available.');
    // Always use the account captured BEFORE async camera/file dialogs,
    // never whichever account happens to be selected after an await.
    await ActorLocalVault.instance.save(
      account, actor, formerName: formerName,
    );
  }

  Future<void> scanActor() async {
    final account = widget.store.selectedAccount;
    final actorName = name.text.trim();
    if (actorName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an Actor name before scanning.')),
      );
      return;
    }
    if (_scanInProgress || _transferBusy || _vaultBusy || !_vaultReady) {
      _feedback('Secure Actor vault is not ready. Try reopening Actors Studio.');
      return;
    }
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
    if (!_sameActiveAccount(account)) {
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
      return;
    }
    final profile = StudioAvatar(
      actorName, style, identityNotes: identityNotes.text.trim(),
      capturePaths: result.paths, autoTouchUp: _autoTouchUp,
    );
    try {
      await _persistActor(profile, account: account);
    } catch (_) {
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
      _feedback('Actor was not saved: device encryption/storage unavailable.');
      return;
    }
    if (!_sameActiveAccount(account)) {
      for (final path in result.paths) {
        try { await File(path).delete(); } catch (_) {}
      }
      return;
    }
    final saved = widget.store.addAvatar(actorName, style,
        identityNotes: identityNotes.text, capturePaths: result.paths,
        autoTouchUp: _autoTouchUp);
    if (!saved && _deviceVaultAvailable) {
      try {
        await ActorLocalVault.instance.delete(account, actorName);
      } catch (_) {}
    }
    if (!saved) {
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
          ? 'Actor created with ${result.paths.length} photos. Encrypted local vault on mobile; no upload.'
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
    if (editingName == null || !_vaultReady || _vaultBusy) return;
    final account = widget.store.selectedAccount;
    final currentName = editingName!;
    final nameValue = name.text.trim();
    if (nameValue.isEmpty || nameValue.toLowerCase() == 'none' ||
        widget.store.avatars.any((a) =>
          a.name != currentName &&
          a.name.toLowerCase() == nameValue.toLowerCase())) {
      _feedback('Actor name is invalid or already used.');
      return;
    }
    final existing = widget.store.avatars.where((a) => a.name == currentName);
    if (existing.isEmpty) return;
    final updated = StudioAvatar(
      nameValue, style, identityNotes: identityNotes.text.trim(),
      capturePaths: existing.single.capturePaths, autoTouchUp: _autoTouchUp,
    );
    setState(() => _vaultBusy = true);
    try {
      // Persist first. No UI mutation if authenticated encryption fails.
      if (updated.capturePaths.isNotEmpty) {
        await _persistActor(
          updated, account: account, formerName: currentName,
        );
      }
      if (!_sameActiveAccount(account)) return;
      final success = widget.store.editAvatar(
        currentName, nameValue, style,
        identityNotes: updated.identityNotes,
        autoTouchUp: _autoTouchUp,
      );
      if (success) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {
          editingName = null;
          name.clear();
          identityNotes.clear();
          _autoTouchUp = false;
        });
      }
      _feedback(success ? 'Encrypted Actor details updated.'
          : 'Actor could not be edited.');
    } catch (_) {
      _feedback('Changes were not saved: encrypted storage is unavailable.');
    } finally {
      if (mounted) setState(() => _vaultBusy = false);
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
    if (_transferBusy || _scanInProgress || _vaultBusy || !_vaultReady) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ' + avatar.name + '?'),
        content: const Text(
          'This permanently removes the encrypted Actor record, local face '
          'photos and saved scene/music drafts containing this Actor. '
          'Previously exported backups are not deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep character')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (_vaultBusy || !_vaultReady) return;
    final account = widget.store.selectedAccount;
    // Collect derived reference JPEGs *before* removing draft metadata.
    final derivedPaths = widget.store.drafts
        .where((draft) =>
            draft.avatarName.toLowerCase() == avatar.name.toLowerCase() ||
            draft.actors.any((a) =>
                a.avatarName.toLowerCase() == avatar.name.toLowerCase()))
        .expand((draft) => draft.referenceFiles)
        .map((ref) => ref.localPath)
        .whereType<String>()
        .toSet();
    setState(() => _vaultBusy = true);
    try {
      if (_deviceVaultAvailable && avatar.capturePaths.isNotEmpty) {
        await ActorLocalVault.instance.delete(account, avatar.name);
      }
    } catch (_) {
      _feedback('Could not remove encrypted Actor. Nothing was deleted.');
      if (mounted) setState(() => _vaultBusy = false);
      return;
    }
    if (mounted && widget.store.selectedAccount == account) {
      widget.store.removeAvatar(avatar.name);
    }
    // Only delete files from HOTICE-owned generated asset directories.
    // Never follow arbitrary draft paths into a user's personal files.
    try {
      final temp = (await getTemporaryDirectory()).absolute.path;
      for (final path in derivedPaths) {
        if (path.startsWith('$temp/hotice_actor_reference_sheets/') ||
            path.startsWith('$temp/hotice_actor_touchups/')) {
          try { await File(path).delete(); } catch (_) {}
        }
      }
    } catch (_) {}
    for (final path in avatar.capturePaths) {
      try { await File(path).delete(); } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _vaultBusy = false);
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
        content: Text(action == 'Export'
            ? 'This backup contains recognizable face photos. HOTICE will '
              'encrypt the file with a password you choose. A lost password '
              'cannot be recovered. Keep the password separate from the '
              'backup; nothing will be uploaded.'
            : 'Only import face photos with the person\'s consent. HOTICE '
              'supports password-encrypted Actor backups and older '
              'UNENCRYPTED ZIP files; old files can expose private faces. '
              'Nothing will be uploaded.'),
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
    if (_transferBusy || _vaultBusy || !_vaultReady) return;
    final account = widget.store.selectedAccount;
    if (actor.capturePaths.isEmpty) {
      _feedback('This demo Actor has no guided photos to export.');
      return;
    }
    if (!await _confirmFaceTransfer('Export') || !mounted) return;
    final password = await requestActorBackupPassword(
      context, creatingBackup: true,
    );
    if (password == null || !_sameActiveAccount(account)) return;
    setState(() => _transferBusy = true);
    try {
      final zipped = await ActorArchiveCodec.exportActor(actor);
      final encrypted = await ActorTransferCipher.encrypt(
        zipped, password: password,
      );
      if (!_sameActiveAccount(account)) return;
      final safeName = actor.name.replaceAll(
          RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save encrypted HOTICE Actor backup',
        fileName: 'HOTICE_${safeName}.hoticeactor',
        bytes: encrypted,
      );
      if (!mounted) return;
      _feedback(saved == null
          ? 'Export cancelled.'
          : 'Actor backup encrypted. Keep your password safe.');
    } catch (_) {
      _feedback('Could not encrypt/export Actor backup. Check photos and storage.');
    } finally {
      if (mounted) setState(() => _transferBusy = false);
    }
  }

  Future<void> _importActor() async {
    if (_transferBusy || _vaultBusy || !_vaultReady) return;
    final account = widget.store.selectedAccount;
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
          length > ActorArchiveCodec.maxArchiveBytes + 64) {
        throw const FormatException('Actor package exceeds safety size limit.');
      }
      final archiveBytes = await picked.readAsBytes();
      Uint8List decodedZip;
      if (ActorTransferCipher.isEncrypted(archiveBytes)) {
        if (!mounted) return;
        final password = await requestActorBackupPassword(
          context, creatingBackup: false,
        );
        if (password == null || !mounted) return;
        decodedZip = await ActorTransferCipher.decrypt(
          archiveBytes, password: password,
        );
      } else if (ActorTransferCipher.isLegacyZip(archiveBytes)) {
        if (!mounted) return;
        final allowLegacy = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unencrypted older Actor backup'),
            content: const Text(
              'This older ZIP has no password protection. Anyone with a '
              'copy can view the face photos. Import only with consent.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import legacy ZIP'),
              ),
            ],
          ),
        );
        if (allowLegacy != true || !mounted) return;
        decodedZip = archiveBytes;
      } else {
        throw const FormatException('Unknown Actor backup format.');
      }
      final profile = ActorArchiveCodec.decode(decodedZip);
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
      await _persistActor(StudioAvatar(
        actorName, profile.style, identityNotes: profile.notes,
        capturePaths: created, autoTouchUp: profile.autoTouchUp,
      ), account: account);
      if (!_sameActiveAccount(account)) return;
      final success = widget.store.addAvatar(
        actorName, profile.style,
        identityNotes: profile.notes, capturePaths: created,
        autoTouchUp: profile.autoTouchUp,
      );
      if (!success) {
        if (_deviceVaultAvailable) {
          try {
            await ActorLocalVault.instance.delete(
              account, actorName,
            );
          } catch (_) {}
        }
        throw StateError('Actor profile could not be saved.');
      }
      created = [];
      _feedback('Actor imported with ${profile.photos.length} photos. '
          'Encrypted on this mobile device.');
    } catch (_) {
      _feedback('Import rejected. Verify password, file integrity and Actor photos.');
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
                  'Mobile Actor originals are stored encrypted on-device and unpacked only ' 
                  'into app-private temporary files while the app is running. '
                  'They are not 3D meshes, biometric identity verification or guaranteed '
                  'AI face-locking.',
                ),
                if (avatar.capturePaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${avatar.capturePaths.length} captured angles (encrypted local backup on mobile)'),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final path in avatar.capturePaths)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(path), cacheWidth: 320,
                            height: 105, width: 86,
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
            'New Actors require consented guided-camera capture. Android/iOS '
            'store an encrypted local copy; app previews use temporary photos. '
            'No cloud upload, account authentication or 3D reconstruction.',
          ),
          const SizedBox(height: 12),
          if (!_vaultReady)
            DemoNotice(_vaultProblem ??
                'Preparing private Actor storage before face capture...'),
          if (_vaultReady && _vaultProblem != null)
            DemoNotice(_vaultProblem!),
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
                    onPressed: (_scanInProgress || !_vaultReady || _vaultBusy) ? null : scanActor,
                  ),
                ] else
                  PrimaryButton(
                    label: 'Save changes',
                    icon: Icons.save_rounded,
                    onPressed: (_vaultReady && !_vaultBusy) ? saveAvatar : null,
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
            onPressed: (_transferBusy || !_vaultReady || _vaultBusy) ? null : _importActor,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import Actor (.hoticeactor)'),
          ),
          const SizedBox(height: 10),
          const Text('New backups are password-encrypted. Legacy Actor ZIPs remain unencrypted.',
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
                          ? '${avatar.capturePaths.length} guided photos · encrypted local vault (mobile)'
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
                      PopupMenuItem(value: 'export', child: Text('Export encrypted Actor backup')),
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
