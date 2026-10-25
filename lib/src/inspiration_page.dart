import 'package:flutter/material.dart';

import 'design.dart';
import 'inspiration_catalog.dart';
import 'video_models.dart';

/// A searchable local preview of editor-authored prompts. The public
/// catalog never exposes unapproved third-party media or raw source URLs.
class InspirationPage extends StatefulWidget {
  const InspirationPage({super.key, required this.onUse});

  final ValueChanged<InspirationTemplate> onUse;

  @override
  State<InspirationPage> createState() => _InspirationPageState();
}

class _InspirationPageState extends State<InspirationPage> {
  late final Future<List<InspirationTemplate>> _catalog =
      InspirationCatalog.load();
  final _search = TextEditingController();
  String _category = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Explore & create',
            title: 'Inspiration Library',
            subtitle: 'Find a scene idea, then make it yours with named Actors.',
          ),
          const DemoNotice(
            'Original HOTICE-written templates. Model choices are illustrative, '
            'and no video has been generated or uploaded in this demo.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search scene ideas',
              hintText: 'Camera, fantasy, music, action...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<InspirationTemplate>>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return StudioPanel(
                  child: Text('Could not load the inspiration catalog. '
                      'The local data file may be missing.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final categories = [
                'All',
                ...{for (final item in snapshot.data!) item.category},
              ];
              final needle = _search.text.trim().toLowerCase();
              final list = snapshot.data!.where((item) {
                if (_category != 'All' && item.category != _category) {
                  return false;
                }
                return needle.isEmpty ||
                    ('${item.title} ${item.category} ${item.tags.join(' ')} '
                            '${item.prompt}')
                        .toLowerCase()
                        .contains(needle);
              }).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final category in categories)
                        ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  if (list.isEmpty)
                    const StudioPanel(
                      child: Text('No matching scene ideas. Try another search.'),
                    ),
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final columns = bounds.maxWidth >= 900
                          ? 3
                          : bounds.maxWidth >= 560
                              ? 2
                              : 1;
                      final width = ((bounds.maxWidth -
                                  14 * (columns - 1)) /
                              columns)
                          .clamp(0.0, 1600.0);
                      return Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          for (final item in list)
                            SizedBox(
                              width: width,
                              child: StudioPanel(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item.category.toUpperCase(),
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.1)),
                                    const SizedBox(height: 9),
                                    Text(item.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 10),
                                    Text(item.prompt,
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Model: ${demoModelById(item.modelId).label} '
                                      '· ${item.actorSlots.length} actor roles',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      onPressed: () => widget.onUse(item),
                                      icon: const Icon(Icons.auto_awesome),
                                      label: const Text('Use this prompt'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
