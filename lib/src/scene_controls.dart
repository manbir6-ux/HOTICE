import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'state.dart';
import 'video_models.dart';

/// A model-constrained cast and file-reference selector. File metadata is
/// temporary. No file contents, faces, tokens or photos leave the device.
class SceneCastAndReferences extends StatefulWidget {
  const SceneCastAndReferences({
    super.key,
    required this.actors,
    required this.cast,
    required this.references,
    required this.profile,
    required this.onCastChanged,
    required this.onReferencesChanged,
  });

  final List<StudioAvatar> actors;
  final List<SceneActor> cast;
  final List<SceneReference> references;
  final VideoModelProfile profile;
  final ValueChanged<List<SceneActor>> onCastChanged;
  final ValueChanged<List<SceneReference>> onReferencesChanged;

  @override
  State<SceneCastAndReferences> createState() => _SceneCastAndReferencesState();
}

class _SceneCastAndReferencesState extends State<SceneCastAndReferences> {
  final _role = TextEditingController();
  String? _selectedActor;
  bool _selecting = false;

  @override
  void dispose() {
    _role.dispose();
    super.dispose();
  }

  void _addRole() {
    final role = _role.text.trim();
    if (role.isEmpty || _selectedActor == null) {
      _notify('Choose an actor and a scene name.');
      return;
    }
    if (widget.cast.any((item) =>
        item.sceneName.toLowerCase() == role.toLowerCase())) {
      _notify('That scene name is already in use.');
      return;
    }
    if (widget.cast.length >= widget.profile.maxActors) {
      _notify('This model allows up to ${widget.profile.maxActors} actors.');
      return;
    }
    if (!widget.actors.any((actor) => actor.name == _selectedActor)) {
      _notify('That actor is not in your library.');
      return;
    }
    widget.onCastChanged([
      ...widget.cast,
      SceneActor(avatarName: _selectedActor!, sceneName: role),
    ]);
    _role.clear();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _chooseFiles(VideoAttachment type) async {
    final max = widget.profile.maximumFor(type);
    final used = widget.references.where((file) => file.type == type).length;
    final remaining = max - used;
    if (remaining <= 0) {
      _notify('This model permits no more ${type.label.toLowerCase()} files.');
      return;
    }
    final allowed = switch (type) {
      VideoAttachment.image => <String>['jpg', 'jpeg', 'png', 'webp'],
      VideoAttachment.video => <String>['mp4', 'mov', 'webm'],
      VideoAttachment.audio => <String>['mp3', 'wav', 'm4a'],
    };
    setState(() => _selecting = true);
    try {
      final List<PlatformFile> pickedFiles;
      if (remaining == 1) {
        final selected = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: allowed,
        );
        pickedFiles = selected == null ? <PlatformFile>[] : [selected];
      } else {
        pickedFiles = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: allowed,
        );
      }
      if (!mounted || pickedFiles.isEmpty) return;
      if (pickedFiles.length > remaining) {
        _notify('Select only $remaining more file(s) for this model.');
        return;
      }
      final accepted = <SceneReference>[];
      for (final file in pickedFiles) {
        final size = file.lengthSync();
        if (size == null || size < 1 || size > 150 * 1024 * 1024) {
          _notify('File must be nonempty and at most 150 MB in this demo.');
          return;
        }
        final ext = file.extension?.toLowerCase();
        if (!allowed.contains(ext)) {
          _notify('Unsupported file extension.');
          return;
        }
        accepted.add(SceneReference(
          type: type,
          fileName: file.name,
          bytes: size,
        ));
      }
      final updated = [...widget.references, ...accepted];
      if (widget.profile.validateInputs(updated.map((f) => f.type)) != null) {
        _notify('Selected files exceed this model’s limits.');
        return;
      }
      widget.onReferencesChanged(updated);
    } catch (_) {
      if (mounted) _notify('Could not open files. Check device permissions.');
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.actors.any((a) => a.name == _selectedActor)
        ? _selectedActor : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Actors in this scene',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text('Name each on-screen role. Up to ${widget.profile.maxActors} '
            'for this illustrative model preset.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        if (widget.actors.isEmpty)
          const Text('No actors yet. Create one in Actors Studio.'),
        if (widget.actors.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('actor-$current'),
            initialValue: current,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Library actor'),
            items: [
              for (final actor in widget.actors)
                DropdownMenuItem(value: actor.name, child: Text(actor.name)),
            ],
            onChanged: (value) => setState(() => _selectedActor = value),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _role,
            maxLength: 48,
            decoration: const InputDecoration(
              labelText: 'Name in this scene',
              hintText: 'e.g. Hero, Detective, Villain',
            ),
          ),
          OutlinedButton.icon(
            onPressed: _addRole,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add named actor'),
          ),
        ],
        const SizedBox(height: 8),
        for (final entry in widget.cast)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(entry.sceneName),
            subtitle: Text('Actor preset: ${entry.avatarName}'),
            trailing: IconButton(
              tooltip: 'Remove ${entry.sceneName}',
              onPressed: () => widget.onCastChanged(
                widget.cast.where((a) => !identical(a, entry)).toList(),
              ),
              icon: const Icon(Icons.close),
            ),
          ),
        const Divider(height: 25),
        Text('Reference attachments',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('Selected names only; no upload, AI render, or saved file data.'),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in VideoAttachment.values)
              if (widget.profile.maximumFor(type) > 0)
                OutlinedButton.icon(
                  onPressed: _selecting ? null : () => _chooseFiles(type),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(
                    '${type.label}: '
                    '${widget.references.where((f) => f.type == type).length}/'
                    '${widget.profile.maximumFor(type)}',
                  ),
                ),
          ],
        ),
        if (widget.profile.attachments.isEmpty)
          const Text('This model supports text prompts only.'),
        for (final file in widget.references)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(file.fileName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${file.type.label} · ${file.bytes} bytes'),
            trailing: IconButton(
              tooltip: 'Remove reference',
              onPressed: () => widget.onReferencesChanged(
                widget.references.where((item) => !identical(item, file)).toList(),
              ),
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
  }
}
