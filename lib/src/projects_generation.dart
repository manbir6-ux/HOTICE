import 'package:flutter/material.dart';
import 'state.dart';
import 'video_models.dart';
import 'avatar_identity.dart';
import 'design.dart';
import 'dialogs.dart';

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

  Future<void> rename(BuildContext context, HotProject project) async {
    final title = await showHotIceTextDialog(
      context,
      title: 'Rename project',
      label: 'Project title',
      confirmLabel: 'Save name',
      initialValue: project.title,
      maxLength: 60,
    );
    if (!context.mounted || title == null) return;
    if (!store.renameProject(project.id, title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project could not be renamed.')),
      );
    }
  }

  Future<void> delete(BuildContext context, HotProject project) async {
    final draftCount =
        store.drafts.where((draft) => draft.projectId == project.id).length;
    final planCount =
        store.musicPlans.where((plan) => plan.projectId == project.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'Delete "${project.title}" and its $draftCount saved scene drafts '
          'and $planCount storyboards from this demo session? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete project'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    if (!store.deleteProject(project.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project no longer exists.')),
      );
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
          const DemoNotice(
            'Demo only: projects, scenes and storyboards are stored in memory '
            'and will be lost when the app restarts. Device storage and '
            'paid cloud backup are not connected yet.',
          ),
          const SizedBox(height: 22),
          if (store.projects.isEmpty)
            StudioPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.movie_creation_outlined,
                      size: 36, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Your next film starts here',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Create a project to plan scenes or a music video.'),
                ],
              ),
            ),
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
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final title = Text(
                                  project.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                );
                                final menu = PopupMenuButton<String>(
                                  key: ValueKey('project-options-${project.id}'),
                                  tooltip: 'Project options',
                                  icon: const Icon(Icons.more_vert_rounded),
                                  onSelected: (action) async {
                                    if (action == 'rename') {
                                      await rename(context, project);
                                    } else if (action == 'delete') {
                                      await delete(context, project);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                );
                                // The tiny-width regression test gives this
                                // tile as little as 16 logical px to use.
                                // A 48px IconButton next to a title overflows
                                // in a Row even with an Expanded title.
                                if (constraints.maxWidth < 64) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [title, menu],
                                  );
                                }
                                return Row(
                                  children: [Expanded(child: title), menu],
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${store.drafts.where((item) => item.projectId == project.id).length} '
                              'scene drafts · '
                              '${store.musicPlans.where((item) => item.projectId == project.id).length} '
                              'storyboards',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
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

class GenerationPage extends StatefulWidget {
  final HotIceStore store;
  final String? initialProjectId;
  const GenerationPage({
    super.key,
    required this.store,
    this.initialProjectId,
  });
  @override
  State<GenerationPage> createState() => _GenerationPageState();
}

class _GenerationPageState extends State<GenerationPage> {
  final prompt = TextEditingController();
  // Each in-progress scene belongs to one film project in this demo session.
  final Map<String, String> _unsavedPrompts = {};
  final Map<String, String> _unsavedModels = {};
  final Map<String, String> _unsavedRatios = {};
  final Map<String, int> _unsavedDurations = {};
  final Map<String, String> _unsavedAvatars = {};
  String? project;
  String model = 'cinematic_demo';

  VideoModelProfile get profile => demoModelById(model);
  String ratio = '16:9';
  int seconds = 8;
  String avatarName = 'None';

  @override
  void initState() {
    super.initState();
    project = widget.initialProjectId ??
        (widget.store.projects.isEmpty ? null : widget.store.projects.first.id);
  }

  void _selectProject(String? next) {
    if (project == next) return;
    if (project != null) {
      _unsavedPrompts[project!] = prompt.text;
      _unsavedModels[project!] = model;
      _unsavedRatios[project!] = ratio;
      _unsavedDurations[project!] = seconds;
      _unsavedAvatars[project!] = avatarName;
    }
    project = next;
    prompt.text = next == null ? '' : (_unsavedPrompts[next] ?? '');
    final savedModel = next == null ? null : _unsavedModels[next];
    model = demoVideoModels.any((candidate) => candidate.id == savedModel)
        ? savedModel!
        : 'cinematic_demo';
    final chosen = demoModelById(model);
    final savedDuration = next == null ? null : _unsavedDurations[next];
    seconds = savedDuration != null && chosen.durations.contains(savedDuration)
        ? savedDuration
        : 8;
    if (!chosen.durations.contains(seconds)) seconds = chosen.durations.first;
    final savedRatio = next == null ? null : _unsavedRatios[next];
    ratio = savedRatio != null && chosen.ratiosFor(seconds).contains(savedRatio)
        ? savedRatio
        : chosen.ratiosFor(seconds).first;
    avatarName = next == null ? 'None' : (_unsavedAvatars[next] ?? 'None');
    // Avatar membership is re-validated at build and at save time.
  }

  @override
  void didUpdateWidget(covariant GenerationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId != null &&
        widget.initialProjectId != oldWidget.initialProjectId) {
      _selectProject(widget.initialProjectId);
    }
  }

  @override
  void dispose() {
    prompt.dispose();
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

  void save() {
    if (prompt.text.trim().isEmpty || project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a project and enter a prompt.')),
      );
      return;
    }
    final matches = widget.store.projects.where((p) => p.id == project);
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project no longer exists. Choose another.')),
      );
      return;
    }
    if (!profile.accepts(seconds: seconds, ratio: ratio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unsupported output for this model.')),
      );
      return;
    }
    final selected = matches.first;
    widget.store.queueDraft(GenerationDraft(
      projectId: selected.id,
      modelId: profile.id,
      avatarName: avatarName,
      project: selected.title,
      prompt: AvatarPromptComposer.compose(
        scenePrompt: prompt.text,
        avatar: widget.store.avatars.where((a) => a.name == avatarName).firstOrNull,
        model: profile,
      ),
      model: profile.label,
      aspectRatio: ratio,
      durationSeconds: seconds,
      createdAt: DateTime.now(),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scene draft saved. No AI request sent.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validProjects = widget.store.projects;
    if (!validProjects.any((item) => item.id == project)) {
      _selectProject(validProjects.isEmpty ? null : validProjects.first.id);
    }
    final avatars = [
      'None',
      for (final item in widget.store.avatars) item.name,
    ];
    if (!avatars.contains(avatarName)) avatarName = 'None';
    final editor = StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scene composer',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            key: ValueKey(project),
            initialValue: project,
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
            key: ValueKey('normal-model-$project'),
            initialValue: model,
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
          Text('Accepted reference attachments',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile.attachments.isEmpty)
                const Chip(label: Text('Prompt only')),
              for (final input in profile.attachments)
                Chip(
                  avatar: const Icon(Icons.attach_file, size: 17),
                  label: Text(input.label),
                ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Capability preview only. No attachment picker or upload is connected.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 13),
          DropdownButtonFormField<String>(
            key: ValueKey('normal-avatar-$project'),
            initialValue: avatarName,
            decoration: const InputDecoration(labelText: 'Avatar'),
            items: avatars.map((name) =>
                DropdownMenuItem(value: name, child: Text(name))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => avatarName = v);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecting a character adds its reusable appearance notes to the saved scene prompt. True face locking requires future image/3D model integrations.',
            style: TextStyle(fontSize: 12),
          ),
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
            onPressed: save,
          ),
        ],
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
