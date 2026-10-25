import 'package:flutter/material.dart';
import 'state.dart';
import 'design.dart';

class ProjectsPage extends StatelessWidget {
  final HotIceStore store;
  final ValueChanged<String> onOpen;
  const ProjectsPage({super.key, required this.store, required this.onOpen});

  Future<void> add(BuildContext context) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New film project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
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
            final width = (box.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final project in store.projects)
                  SizedBox(
                    width: width,
                    child: InkWell(
                      onTap: () => onOpen(project.id),
                      borderRadius: BorderRadius.circular(23),
                      child: StudioPanel(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilmPreview(title: project.title),
                            const SizedBox(height: 12),
                            Text(project.title,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 5),
                            const Text('Open project →',
                                style: TextStyle(fontSize: 12)),
                          ],
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
  String? project;
  String model = 'Cinematic Draft';
  String ratio = '16:9';
  int seconds = 8;
  String avatarName = 'None';

  @override
  void initState() {
    super.initState();
    project = widget.initialProjectId ?? widget.store.projects.first.id;
  }

  @override
  void didUpdateWidget(covariant GenerationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId != null &&
        widget.initialProjectId != oldWidget.initialProjectId) {
      project = widget.initialProjectId;
    }
  }

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  void save() {
    if (prompt.text.trim().isEmpty || project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a project and enter a prompt.')),
      );
      return;
    }
    final selected = widget.store.projects.firstWhere((p) => p.id == project);
    widget.store.queueDraft(GenerationDraft(
      project: selected.title,
      prompt: prompt.text.trim(),
      model: model,
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
            value: project,
            decoration: const InputDecoration(labelText: 'Project'),
            isExpanded: true,
            items: widget.store.projects.map((item) =>
              DropdownMenuItem(value: item.id, child: Text(item.title))
            ).toList(),
            onChanged: (v) => setState(() => project = v),
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
            decoration: const InputDecoration(labelText: 'Workflow preset'),
            items: const [
              DropdownMenuItem(
                value: 'Cinematic Draft', child: Text('Cinematic Draft')),
              DropdownMenuItem(
                value: 'Character Focus', child: Text('Character Focus')),
              DropdownMenuItem(
                value: 'Storyboard Mode', child: Text('Storyboard Mode')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => model = v);
            },
          ),
          const SizedBox(height: 13),
          DropdownButtonFormField<String>(
            value: avatarName,
            decoration: const InputDecoration(labelText: 'Avatar'),
            items: avatars.map((name) =>
                DropdownMenuItem(value: name, child: Text(name))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => avatarName = v);
            },
          ),
          const SizedBox(height: 17),
          Text('Aspect ratio', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            for (final item in ['16:9', '9:16', '1:1'])
              ChoiceChip(
                label: Text(item),
                selected: ratio == item,
                onSelected: (_) => setState(() => ratio = item),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Duration', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            for (final item in [4, 8, 10])
              ChoiceChip(
                label: Text(item.toString() + ' seconds'),
                selected: seconds == item,
                onSelected: (_) => setState(() => seconds = item),
              ),
          ]),
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
            if (widget.store.drafts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Your draft history will appear here.'),
              ),
            for (final draft in widget.store.drafts.take(4))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.movie_creation_outlined),
                title: Text(draft.project),
                subtitle: Text(draft.prompt,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
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
