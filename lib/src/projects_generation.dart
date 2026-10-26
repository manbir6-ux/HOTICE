import 'dart:io';
import 'package:flutter/material.dart';
import 'actor_reference_adapter.dart';
import 'state.dart';
import 'video_models.dart';
import 'avatar_identity.dart';
import 'design.dart';
import 'dialogs.dart';
import 'inspiration_catalog.dart';
import 'scene_controls.dart';

class ProjectsPage extends StatelessWidget {
  final HotIceStore store;
  final ValueChanged<String> onOpen;
  const ProjectsPage({super.key, required this.store, required this.onOpen});

  Future<void> add(BuildContext context) async {
    final title = await showHotIceTextDialog(
      context,
      title: 'New film project',
      label: 'Project title',
      confirmLabel: 'Create',
      maxLength: 60,
    );
    if (!context.mounted) return;
    if (title != null && title.trim().isNotEmpty) {
      onOpen(store.addProject(title));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Your workspace',
            title: 'Projects',
            subtitle: 'Every great film begins with an idea. Shape yours here.',
          ),
          PrimaryButton(
            label: 'New project',
            icon: Icons.add,
            onPressed: () => add(context),
          ),
          const SizedBox(height: 16),
          const DemoNotice('Projects are saved in memory for this demo session.'),
          const SizedBox(height: 22),
          LayoutBuilder(builder: (context, box) {
            final columns = box.maxWidth > 810
                ? 3
                : box.maxWidth > 520
                    ? 2
                    : 1;
            final width = ((box.maxWidth - (columns - 1) * 14) /
                    columns).clamp(0.0, 1160.0);
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final project in store.projects)
                  SizedBox(
                    width: width,
                    child: StudioPanel(
                      padding: EdgeInsets.zero,
                      // InkWell must be INSIDE the StudioPanel Material surface
                      // for visible feedback and correct Material ancestry.
                      child: InkWell(
                        onTap: () => onOpen(project.id),
                        borderRadius: BorderRadius.circular(23),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilmPreview(title: project.title),
                            const SizedBox(height: 12),
                            Text(project.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 5),
                            const Text('Open project →',
                                style: TextStyle(fontSize: 12)),
                          ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Snapshot of one project's incomplete editor so its Actor identities,
/// attachments and advanced controls cannot silently follow another film.
class _ProjectEditorDraft {
  _ProjectEditorDraft({
    required this.prompt,
    required this.modelId,
    required this.ratio,
    required this.seconds,
    required this.actors,
    required this.references,
    required this.negativePrompt,
    required this.seed,
    required this.soundEnabled,
    required this.selectedTemplate,
  });
  final String prompt;
  final String modelId;
  final String ratio;
  final int seconds;
  final List<SceneActor> actors;
  final List<SceneReference> references;
  final String negativePrompt;
  final String seed;
  final bool soundEnabled;
  final InspirationTemplate? selectedTemplate;
}

class GenerationPage extends StatefulWidget {
  final HotIceStore store;
  final String? initialProjectId;
  final InspirationTemplate? initialTemplate;
  final int templateRevision;
  const GenerationPage({
    super.key,
    required this.store,
    this.initialProjectId,
    this.initialTemplate,
    this.templateRevision = 0,
  });
  @override
  State<GenerationPage> createState() => _GenerationPageState();
}

class _GenerationPageState extends State<GenerationPage> {
  final prompt = TextEditingController();
  // Each in-progress scene belongs to one film project in this demo session.
  final Map<String, _ProjectEditorDraft> _unsavedProjects = {};
  String? project;
  String model = 'cinematic_demo';

  VideoModelProfile get profile => demoModelById(model);
  String ratio = '16:9';
  int seconds = 8;
  final List<SceneActor> sceneActors = [];
  final List<SceneReference> references = [];
  final negativePrompt = TextEditingController();
  final seedText = TextEditingController();
  bool soundEnabled = false;
  bool advancedOpen = false;
  InspirationTemplate? selectedTemplate;
  bool _savingDraft = false;

  @override
  void initState() {
    super.initState();
    project = widget.initialProjectId ??
        (widget.store.projects.isEmpty ? null : widget.store.projects.first.id);
    if (widget.initialTemplate != null) _applyTemplate(widget.initialTemplate!);
  }

  void _applyTemplate(InspirationTemplate entry) {
    selectedTemplate = entry;
    prompt.text = entry.prompt;
    model = entry.modelId;
    // Switching template replaces the previous cast/settings rather than
    // silently carrying unsupported references to the next model.
    sceneActors.clear();
    references.clear();
    negativePrompt.clear();
    seedText.clear();
    soundEnabled = false;
    final capabilities = demoModelById(model);
    if (!capabilities.durations.contains(seconds)) {
      seconds = capabilities.durations.first;
    }
    if (!capabilities.ratiosFor(seconds).contains(ratio)) {
      ratio = capabilities.ratiosFor(seconds).first;
    }
  }

  void _selectProject(String? next) {
    if (project == next) return;
    if (project != null) {
      _unsavedProjects[project!] = _ProjectEditorDraft(
        prompt: prompt.text,
        modelId: model,
        ratio: ratio,
        seconds: seconds,
        actors: List<SceneActor>.of(sceneActors),
        references: List<SceneReference>.of(references),
        negativePrompt: negativePrompt.text,
        seed: seedText.text,
        soundEnabled: soundEnabled,
        selectedTemplate: selectedTemplate,
      );
    }
    project = next;
    final previous = next == null ? null : _unsavedProjects[next];
    prompt.text = previous?.prompt ?? '';
    model = previous?.modelId ?? demoVideoModels.first.id;
    seconds = previous?.seconds ?? 8;
    ratio = previous?.ratio ?? '16:9';
    sceneActors
      ..clear()
      ..addAll(previous?.actors ?? const <SceneActor>[]);
    references
      ..clear()
      ..addAll(previous?.references ?? const <SceneReference>[]);
    negativePrompt.text = previous?.negativePrompt ?? '';
    seedText.text = previous?.seed ?? '';
    soundEnabled = previous?.soundEnabled ?? false;
    selectedTemplate = previous?.selectedTemplate;
  }

  @override
  void didUpdateWidget(covariant GenerationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId != null &&
        widget.initialProjectId != oldWidget.initialProjectId) {
      _selectProject(widget.initialProjectId);
    }
    if (widget.initialTemplate != null &&
        widget.templateRevision != oldWidget.templateRevision) {
      _applyTemplate(widget.initialTemplate!);
    }
  }

  @override
  void dispose() {
    prompt.dispose();
    negativePrompt.dispose();
    seedText.dispose();
    super.dispose();
  }

  void changeModel(String nextId) {
    final next = demoModelById(nextId);
    setState(() {
      model = next.id;
      if (!next.durations.contains(seconds)) seconds = next.durations.first;
      if (!next.ratiosFor(seconds).contains(ratio)) {
        ratio = next.ratiosFor(seconds).first;
      }
      sceneActors.removeRange(
        sceneActors.length > next.maxActors ? next.maxActors : sceneActors.length,
        sceneActors.length,
      );
      references.removeWhere((ref) => next.maximumFor(ref.type) == 0);
      for (final type in VideoAttachment.values) {
        var used = 0;
        references.removeWhere((ref) {
          if (ref.type != type) return false;
          used++;
          return used > next.maximumFor(type);
        });
      }
      if (!next.supportsNegativePrompt) negativePrompt.clear();
      if (!next.supportsSeed) seedText.clear();
      if (!next.supportsSound) soundEnabled = false;
    });
  }

  void changeDuration(int value) {
    setState(() {
      seconds = value;
      if (!profile.ratiosFor(seconds).contains(ratio)) {
        ratio = profile.ratiosFor(seconds).first;
      }
    });
  }

  Future<void> save() async {
    if (_savingDraft) return;
    if (prompt.text.trim().isEmpty || project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a project and describe your scene.')),
      );
      return;
    }
    final matches = widget.store.projects.where((p) => p.id == project);
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project not found. Choose another.')),
      );
      return;
    }
    final types = references.map((f) => f.type);
    if (!profile.accepts(seconds: seconds, ratio: ratio, inputs: types) ||
        sceneActors.length > profile.maxActors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your actors or reference files exceed this model limit.')),
      );
      return;
    }
    int? seed;
    if (seedText.text.trim().isNotEmpty) {
      seed = int.tryParse(seedText.text.trim());
      if (seed == null || seed < 0 || !profile.supportsSeed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid non-negative seed for this model.')),
        );
        return;
      }
    }
    if (negativePrompt.text.trim().isNotEmpty && !profile.supportsNegativePrompt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Negative prompting is unavailable for this model.')),
      );
      return;
    }
    if (selectedTemplate != null &&
        selectedTemplate!.prompt == prompt.text &&
        sceneActors.length < selectedTemplate!.actorSlots.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'Assign ${selectedTemplate!.actorSlots.length} named actors to use this template.',
        )),
      );
      return;
    }
    final savingProjectId = project;
    final pending = _ProjectEditorDraft(
      prompt: prompt.text,
      modelId: model,
      ratio: ratio,
      seconds: seconds,
      actors: List<SceneActor>.of(sceneActors),
      references: List<SceneReference>.of(references),
      negativePrompt: negativePrompt.text,
      seed: seedText.text,
      soundEnabled: soundEnabled,
      selectedTemplate: selectedTemplate,
    );
    final savingModel = demoModelById(pending.modelId);
    setState(() => _savingDraft = true);
    String? generatedSheetPath;
    var savedSuccessfully = false;
    try {
      var source = pending.prompt.trim();
      if (pending.selectedTemplate != null && pending.selectedTemplate!.prompt == source) {
        source = InspirationPromptBuilder.compile(pending.selectedTemplate!, pending.actors);
      }
      // Detect unresolved placeholders even when the user has edited the text.
      final roleTokens = RegExp(r'\{\{Actor[0-9]+\}\}').allMatches(source).toList();
      if (roleTokens.isNotEmpty) {
        if (pending.actors.length < roleTokens.length) {
          throw StateError('Assign the named actors before saving.');
        }
        final seen = <String>{};
        source = source.replaceAllMapped(RegExp(r'\{\{Actor[0-9]+\}\}'), (match) {
          final token = match.group(0)!;
          if (!seen.contains(token)) {
            seen.add(token);
          }
          final index = seen.toList().indexOf(token);
          return pending.actors[index].sceneName;
        });
      }
      final adapterPlan = ActorReferenceAdapter.plan(
        model: savingModel,
        cast: pending.actors,
        library: widget.store.avatars,
        otherImageAttachments: pending.references.where(
          (item) => item.type == VideoAttachment.image,
        ).length,
        otherVideoAttachments: references.where(
          (item) => item.type == VideoAttachment.video,
        ).length,
      );
      final preparedRefs = <SceneReference>[];
      if (adapterPlan.requiresMontage) {
        final jpegPath = await ActorContactSheet.saveToTemporaryFile(
          adapterPlan,
        );
        generatedSheetPath = jpegPath;
        if (!mounted) return;
        preparedRefs.add(SceneReference(
          type: VideoAttachment.image,
          fileName: jpegPath.split(Platform.pathSeparator).last,
          bytes: await File(jpegPath).length(),
          localPath: jpegPath,
        ));
      } else {
        for (final sourceRef in adapterPlan.sources) {
          final file = File(sourceRef.path);
          if (!await file.exists()) {
            throw StateError('Actor photo is missing; recapture this Actor.');
          }
          preparedRefs.add(SceneReference(
            type: VideoAttachment.image,
            fileName: '${sourceRef.sceneName}_${sourceRef.angle}.jpg',
            bytes: await file.length(),
            localPath: sourceRef.path,
          ));
        }
      }
      final attachments = [...pending.references, ...preparedRefs];
      if (savingModel.validateInputs(attachments.map((r) => r.type)) != null) {
        throw StateError('Actor and extra photos exceed this model limit.');
      }
      if (!mounted || project != savingProjectId) return;
      final selected = matches.first;
      widget.store.queueDraft(GenerationDraft(
        projectId: selected.id,
        modelId: savingModel.id,
        project: selected.title,
        prompt: AvatarPromptComposer.composeActors(
          scenePrompt: source,
          cast: List<SceneActor>.unmodifiable(pending.actors),
          library: widget.store.avatars,
          model: savingModel,
        ),
        model: savingModel.label,
        aspectRatio: pending.ratio,
        durationSeconds: pending.seconds,
        actors: List<SceneActor>.unmodifiable(pending.actors),
        referenceFiles: List<SceneReference>.unmodifiable(attachments),
        negativePrompt: pending.negativePrompt.trim(),
        seed: seed,
        soundEnabled: pending.soundEnabled,
        createdAt: DateTime.now(),
      ));
      savedSuccessfully = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scene and model-compatible Actor references saved locally. No AI request sent.')),
      );
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }

    } on FileSystemException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Could not read or prepare Actor photo files. Recapture and retry.',
          )),
        );
      }

    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'An Actor reference image has an unsupported format.',
          )),
        );
      }

    } finally {
      if (!savedSuccessfully && generatedSheetPath != null) {
        try { await File(generatedSheetPath).delete(); } catch (_) {}
      }
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validProjects = widget.store.projects;
    if (!validProjects.any((item) => item.id == project)) {
      _selectProject(validProjects.isEmpty ? null : validProjects.first.id);
    }
    // Remove stale cast entries if an actor preset was deleted.
    sceneActors.removeWhere((cast) =>
        !widget.store.avatars.any((actor) => actor.name == cast.avatarName));
    final editor = AbsorbPointer(
      absorbing: _savingDraft,
      child: StudioPanel(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scene composer',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            key: ValueKey(project),
            value: project,
            decoration: const InputDecoration(labelText: 'Project'),
            isExpanded: true,
            items: widget.store.projects.map((item) =>
              DropdownMenuItem(
                value: item.id,
                child: Text(item.title, overflow: TextOverflow.ellipsis),
              )
            ).toList(),
            onChanged: (v) => setState(() => _selectProject(v)),
          ),
          const SizedBox(height: 13),
          TextField(
            controller: prompt,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Describe your shot',
              alignLabelWithHint: true,
              hintText: 'A cinematic night scene, dramatic lighting...',
            ),
          ),
          const SizedBox(height: 13),
          DropdownButtonFormField<String>(
            value: model,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Model preview'),
            items: [
              for (final item in demoVideoModels)
                DropdownMenuItem(value: item.id, child: Text(item.label)),
            ],
            onChanged: (v) {
              if (v != null) changeModel(v);
            },
          ),
          const SizedBox(height: 9),
          const Text(
            'These are demo capability profiles, not connected AI providers.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 13),
          if (selectedTemplate != null) ...[
            const SizedBox(height: 9),
            Text('Template selected: ${selectedTemplate!.title}',
                style: Theme.of(context).textTheme.bodySmall),
            if (selectedTemplate!.actorSlots.isNotEmpty)
              Text('Add ${selectedTemplate!.actorSlots.length} named actors in order '
                  'to replace template role placeholders.',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          SceneCastAndReferences(
            profile: profile,
            actors: widget.store.avatars,
            cast: sceneActors,
            references: references,
            onCastChanged: (items) => setState(() {
              sceneActors
                ..clear()
                ..addAll(items);
            }),
            onReferencesChanged: (items) => setState(() {
              references
                ..clear()
                ..addAll(items);
            }),
          ),
          const SizedBox(height: 10),
          Builder(builder: (context) {
            try {
              final plan = ActorReferenceAdapter.plan(
                model: profile,
                cast: sceneActors,
                library: widget.store.avatars,
                otherImageAttachments: references.where(
                  (r) => r.type == VideoAttachment.image,
                ).length,
                otherVideoAttachments: references.where(
                  (r) => r.type == VideoAttachment.video,
                ).length,
              );
              final message = switch (plan.delivery) {
                ActorReferenceDelivery.textOnly =>
                  'Actor identity: text notes only (0 extra image slots used)',
                ActorReferenceDelivery.individualImages =>
                  'Actor identity: ${plan.imageCount} selected angle image(s)',
                ActorReferenceDelivery.contactSheet =>
                  'Actor identity: 1 combined reference image for ${plan.sources.length} Actors',
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Automatic model reference preparation',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                  for (final note in plan.notes)
                    Text(note, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  const Text('Actor source photos stay on-device. They are included in a local draft, not uploaded or used for AI yet.',
                      style: TextStyle(fontSize: 12)),
                ],
              );
            } on StateError catch (error) {
              return Text('Actor references unavailable: ${error.message}',
                  style: const TextStyle(color: Colors.orangeAccent));
            }
          }),
          const SizedBox(height: 17),
          Text('Aspect ratio', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            for (final item in profile.ratiosFor(seconds))
              ChoiceChip(
                label: Text(item),
                selected: ratio == item,
                onSelected: (_) => setState(() => ratio = item),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Duration', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            for (final item in profile.durations)
              ChoiceChip(
                label: Text('$item seconds'),
                selected: seconds == item,
                onSelected: (_) => changeDuration(item),
              ),
          ]),
          const SizedBox(height: 15),
          ExpansionTile(
            initiallyExpanded: false,
            title: const Text('Advanced settings'),
            subtitle: Text('${profile.label} · ${profile.priceBand}'),
            childrenPadding: const EdgeInsets.only(bottom: 15),
            children: [
              Text('Model selection is currently illustrative. Real provider '
                  'capabilities and actual prices will come from the secure admin catalog.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 11),
              if (profile.supportsNegativePrompt)
                TextField(
                  controller: negativePrompt,
                  maxLength: 350,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Negative prompt (optional)',
                  ),
                ),
              if (profile.supportsSeed)
                TextField(
                  controller: seedText,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seed (optional)'),
                ),
              if (profile.supportsSound)
                SwitchListTile(
                  title: const Text('Sound generation preview'),
                  subtitle: const Text('No audio will be generated yet.'),
                  value: soundEnabled,
                  onChanged: (value) => setState(() => soundEnabled = value),
                ),
              const SizedBox(height: 9),
              Text('Supports ${profile.maxActors} actors; '
                  '${profile.attachments.length} reference media types.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          Builder(builder: (context) {
            final quote = profile.quoteCredits(seconds, ratio);
            return Text(
              quote == null
                  ? 'Generation cost: not configured. No charge will be made.'
                  : 'Estimated cost: $quote HOTICE Credits (demo only)',
              style: Theme.of(context).textTheme.bodyMedium,
            );
          }),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Save generation draft',
            icon: Icons.auto_awesome,
            onPressed: _savingDraft ? null : save,
          ),
        ],
      ),
      ),
    );
    final preview = Column(children: [
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scene preview',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 13),
            const FilmPreview(title: 'THE NEXT FRAME'),
            const SizedBox(height: 12),
            const Text('No video rendered — placeholder preview.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      const SizedBox(height: 15),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved drafts',
                style: Theme.of(context).textTheme.titleMedium),
            if (!widget.store.drafts.any((item) => item.projectId == project))
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Your draft history will appear here.'),
              ),
            for (final draft in widget.store.drafts
                .where((item) => item.projectId == project).take(4))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.movie_creation_outlined),
                title: Text(draft.project),
                subtitle: Text(
                  draft.avatarName == 'None'
                      ? draft.prompt
                      : '${draft.prompt}\nAvatar: ${draft.avatarName}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(draft.durationSeconds.toString() + 's'),
              ),
          ],
        ),
      ),
    ]);
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Creative engine',
            title: 'Video generation',
            subtitle: 'Direct your shots with powerful cinematic controls.',
          ),
          const DemoNotice(
            'UI prototype: no AI provider or rendering engine is connected, and no credits are charged.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth > 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: editor),
                  const SizedBox(width: 18),
                  Expanded(flex: 5, child: preview),
                ],
              );
            }
            return Column(children: [
              editor,
              const SizedBox(height: 16),
              preview,
            ]);
          }),
        ],
      ),
    );
  }
}
