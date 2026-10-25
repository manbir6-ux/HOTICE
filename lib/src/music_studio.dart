import 'package:flutter/material.dart';
import 'avatar_identity.dart';
import 'design.dart';
import 'state.dart';

/// Offline storyboard templates are deliberately NOT AI outputs or transcriptions.
class MusicStoryboardTemplates {
  static List<StoryboardShot> fromBrief(String brief) {
    final story = brief.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (story.isEmpty) return const [];
    return [
      StoryboardShot('Opening', 'Establish the world and mood of: ' + story, 6),
      StoryboardShot('Introduce', 'Reveal the main character and their motivation.', 6),
      StoryboardShot('Emotion', 'Move into a striking close-up and emotional shift.', 8),
      StoryboardShot('Finale', 'Conclude with a visual payoff that reflects the opening.', 6),
    ];
  }
}

class MusicVideoStudioPage extends StatefulWidget {
  final HotIceStore store;
  final String? initialProjectId;
  const MusicVideoStudioPage({super.key, required this.store, this.initialProjectId});

  @override
  State<MusicVideoStudioPage> createState() => _MusicVideoStudioPageState();
}

class _MusicVideoStudioPageState extends State<MusicVideoStudioPage> {
  final story = TextEditingController();
  String? projectId;
  String selectedStyle = 'Cinematic realism';
  String selectedAvatar = 'None';
  List<StoryboardShot> shots = [];

  static const styles = [
    'Cinematic realism',
    'Photorealistic',
    'Anime',
    '2D animation',
    'Stylized 3D',
    'Fantasy',
    'Illustration',
    'Creature-focused',
  ];

  @override
  void initState() {
    super.initState();
    projectId = widget.initialProjectId ??
        (widget.store.projects.isEmpty ? null : widget.store.projects.first.id);
  }

  @override
  void didUpdateWidget(covariant MusicVideoStudioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId != null &&
        oldWidget.initialProjectId != widget.initialProjectId) {
      projectId = widget.initialProjectId;
    }
  }

  @override
  void dispose() {
    story.dispose();
    super.dispose();
  }

  void draftStoryboard() {
    if (story.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe your music video story first.')),
      );
      return;
    }
    setState(() => shots = MusicStoryboardTemplates.fromBrief(story.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Offline storyboard outline created. No AI or audio analysis used.')),
    );
  }

  Future<void> editShot(int index) async {
    final controller = TextEditingController(text: shots[index].description);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ' + shots[index].title),
        content: TextField(
          controller: controller,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Shot description'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save shot'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || updated == null || updated.isEmpty) return;
    setState(() {
      final original = shots[index];
      shots[index] = StoryboardShot(original.title, updated, original.estimatedSeconds);
    });
  }

  void moveShot(int index, int direction) {
    final next = index + direction;
    if (next < 0 || next >= shots.length) return;
    setState(() {
      final shot = shots.removeAt(index);
      shots.insert(next, shot);
    });
  }

  void savePlan() {
    if (shots.isEmpty || story.text.trim().isEmpty || projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a project and preview a storyboard first.')),
      );
      return;
    }
    if (!widget.store.projects.any((item) => item.id == projectId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an existing project first.')),
      );
      return;
    }
    final avatars = widget.store.avatars;
    final avatar = selectedAvatar == 'None'
        ? 'None'
        : avatars.any((item) => item.name == selectedAvatar)
            ? selectedAvatar
            : 'None';
    widget.store.saveMusicPlan(MusicVideoPlan(
      projectId: projectId!,
      storyBrief: story.text.trim(),
      visualStyle: selectedStyle,
      avatarName: avatar,
      shots: List.unmodifiable(shots),
      createdAt: DateTime.now(),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Story draft saved locally. No render job or credits used.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.store.projects;
    if (!projects.any((p) => p.id == projectId)) {
      projectId = projects.isEmpty ? null : projects.first.id;
    }
    final avatars = ['None', ...widget.store.avatars.map((a) => a.name)];
    if (!avatars.contains(selectedAvatar)) selectedAvatar = 'None';
    final matches = widget.store.avatars.where((a) => a.name == selectedAvatar);
    final avatar = matches.isEmpty ? null : matches.first;
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Music video workflow',
            title: 'Music Video Studio',
            subtitle: 'Plan the story, arrange shots, and shape the visual direction.',
          ),
          const DemoNotice(
            'Offline UI preview. Song upload, lyrics and word timing, beat detection, script AI, lip-sync and video export require later integrations.',
          ),
          const SizedBox(height: 17),
          LayoutBuilder(builder: (context, size) {
            final wide = size.maxWidth > 820;
            final setup = StudioPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start a music video', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 7),
                  const Text('Only your story description is needed for this preview.'),
                  const SizedBox(height: 17),
                  DropdownButtonFormField<String>(
                    value: projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Project'),
                    items: [
                      for (final item in projects)
                        DropdownMenuItem(value: item.id,
                            child: Text(item.title, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) => setState(() => projectId = value),
                  ),
                  const SizedBox(height: 13),
                  TextField(
                    controller: story,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 1200,
                    decoration: const InputDecoration(
                      labelText: 'Describe your music video',
                      hintText: 'A mysterious journey through a rainy city, with a recurring hero...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Visual direction', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final item in styles)
                        ChoiceChip(
                          label: Text(item),
                          selected: selectedStyle == item,
                          onSelected: (_) => setState(() => selectedStyle = item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedAvatar,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Recurring character (optional)',
                    ),
                    items: [
                      for (final name in avatars)
                        DropdownMenuItem(value: name,
                            child: Text(name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => selectedAvatar = value);
                    },
                  ),
                  if (avatar != null) ...[
                    const SizedBox(height: 7),
                    Text('Character guide: ' + AvatarPromptComposer.identityCard(avatar),
                        maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ],
                  const SizedBox(height: 17),
                  PrimaryButton(
                    label: 'Preview storyboard',
                    icon: Icons.auto_stories_rounded,
                    onPressed: draftStoryboard,
                  ),
                ],
              ),
            );
            const audio = StudioPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.library_music_outlined, size: 33),
                    title: Text('Song & audio'),
                    subtitle: Text('Upload and timeline integration coming later'),
                  ),
                  Divider(),
                  Text('Upcoming workflow',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 12),
                  Text('1. Add a song with your permission'),
                  SizedBox(height: 7),
                  Text('2. Review and correct lyrics and word timings'),
                  SizedBox(height: 7),
                  Text('3. Choose a script-planning model'),
                  SizedBox(height: 7),
                  Text('4. Match video shots with music and export'),
                  SizedBox(height: 13),
                  DemoNotice('No audio is uploaded, analysed or recorded in this demo.'),
                ],
              ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: setup),
                  const SizedBox(width: 16),
                  const Expanded(flex: 4, child: audio),
                ],
              );
            }
            return Column(children: [setup, const SizedBox(height: 14), audio]);
          }),
          const SizedBox(height: 24),
          Text('Storyboard timeline', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          const Text('Editable shot ideas only · timings are placeholders, not synced to a song.'),
          const SizedBox(height: 14),
          if (shots.isEmpty)
            const StudioPanel(
              child: Text('Your shot list appears here after you preview a story.'),
            ),
          for (var i = 0; i < shots.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StudioPanel(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          child: Text((i + 1).toString()),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(shots[i].title,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        Text(shots[i].estimatedSeconds.toString() + 's est.',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(shots[i].description),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 5,
                      children: [
                        TextButton.icon(
                          onPressed: () => editShot(i),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Edit'),
                        ),
                        IconButton(
                          tooltip: 'Move earlier',
                          onPressed: i == 0 ? null : () => moveShot(i, -1),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                        IconButton(
                          tooltip: 'Move later',
                          onPressed: i == shots.length - 1
                              ? null : () => moveShot(i, 1),
                          icon: const Icon(Icons.arrow_downward_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (shots.isNotEmpty) ...[
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Save storyboard draft',
              icon: Icons.save_alt_rounded,
              onPressed: savePlan,
            ),
          ],
          const SizedBox(height: 22),
          Text('Saved music storyboards', style: Theme.of(context).textTheme.titleLarge),
          if (widget.store.musicPlans.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No saved music video plans yet.'),
            ),
          for (final plan in widget.store.musicPlans.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(plan.storyBrief, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(plan.visualStyle + ' · ' +
                  plan.shots.length.toString() + ' editable scene ideas'),
            ),
        ],
      ),
    );
  }
}
