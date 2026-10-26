import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'src/state.dart';
import 'src/actor_vault.dart';
import 'src/design.dart';
import 'src/pages.dart';
import 'src/generation_hub.dart';
import 'src/diagnostics.dart';
import 'src/inspiration_catalog.dart';
import 'src/inspiration_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Remove abandoned temporary capture photos from previous sessions.
  // These are not permanent biometric records or cloud-backed references.
  try {
    final temp = await getTemporaryDirectory();
    for (final subfolder in const [
      'hotice_actor_capture',
      'hotice_actor_reference_sheets',
      'hotice_actor_touchups',
    ]) {
      final folder = Directory('${temp.path}/$subfolder');
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  } catch (_) {
    // A storage failure must never prevent app startup.
  }
  HoticeDiagnostics.install();
  runApp(const HotIceApp());
}

class HotIceApp extends StatefulWidget {
  const HotIceApp({super.key});

  @override
  State<HotIceApp> createState() => _HotIceAppState();
}

class _HotIceAppState extends State<HotIceApp> {
  final HotIceStore store = HotIceStore();
  final ActorVault _vault = ActorVault();
  final Set<String> _loadedAccounts = {};
  final Set<String> _loadingAccounts = {};
  final GlobalKey<ScaffoldMessengerState> _messages = GlobalKey<ScaffoldMessengerState>();
  bool showLogin = false;

  late ThemeMode _lastThemeMode;
  late StudioAccent _lastAccent;
  late StudioFont _lastFont;

  @override
  void initState() {
    super.initState();
    _lastThemeMode = store.themeMode;
    _lastAccent = store.accent;
    _lastFont = store.font;
    store.addListener(_handleAppearanceChanged);
    store.addListener(_restoreAccountActors);
  }

  void _restoreAccountActors() {
    if (!store.signedIn) return;
    final account = store.selectedAccount;
    if (_loadedAccounts.contains(account) ||
        !_loadingAccounts.add(account)) return;
    _loadActorVault(account);
  }

  Future<void> _loadActorVault(String account) async {
    try {
      final loaded = await _vault.restore(account);
      if (!mounted || !store.signedIn ||
          store.selectedAccount != account) {
        // Never insert another account's decrypted Actor images into the
        // currently visible workspace after an async profile switch.
        for (final actor in loaded.actors) {
          for (final path in actor.capturePaths) {
            try { await File(path).delete(); } catch (_) {}
          }
        }
        return;
      }
      for (final actor in loaded.actors) {
        if (store.avatars.any((a) =>
            a.name.toLowerCase() == actor.name.toLowerCase())) {
          // Avoid overwriting a newly created Actor while loading.
          for (final path in actor.capturePaths) {
            try { await File(path).delete(); } catch (_) {}
          }
          continue;
        }
        store.addAvatar(actor.name, actor.style,
          identityNotes: actor.identityNotes,
          capturePaths: actor.capturePaths,
          autoTouchUp: actor.autoTouchUp,
          vaultId: actor.vaultId,
        );
      }
      _loadedAccounts.add(account);
      if (loaded.failedRecords > 0) {
        _messages.currentState?.showSnackBar(SnackBar(
          content: Text('${loaded.failedRecords} encrypted Actor record(s) '
              'could not be restored. No data was overwritten.'),
        ));
      }
    } catch (_) {
      if (mounted && store.selectedAccount == account) {
        _messages.currentState?.showSnackBar(const SnackBar(
          content: Text('Could not unlock the local Actor vault. '
              'Check secure device storage. Encrypted files remain untouched.'),
        ));
      }
    } finally {
      _loadingAccounts.remove(account);
    }
  }

  // Keep the Navigator/MaterialApp stable while demo accounts, projects and
  // avatars change. Rebuild the app-level theme only for appearance changes.
  // Recreating MaterialApp for every store notification can unnecessarily
  // churn inherited widgets during transitions and popups.
  void _handleAppearanceChanged() {
    if (_lastThemeMode == store.themeMode &&
        _lastAccent == store.accent &&
        _lastFont == store.font) {
      return;
    }
    setState(() {
      _lastThemeMode = store.themeMode;
      _lastAccent = store.accent;
      _lastFont = store.font;
    });
  }

  @override
  void dispose() {
    store.removeListener(_handleAppearanceChanged);
    store.removeListener(_restoreAccountActors);
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HOTICE',
      scaffoldMessengerKey: _messages,
      debugShowCheckedModeBanner: false,
      themeMode: store.themeMode,
      theme: HotIceDesign.theme(
        Brightness.light, store.accent.color,
        fontFamily: store.font.family,
      ),
      darkTheme: HotIceDesign.theme(
        Brightness.dark, store.accent.color,
        fontFamily: store.font.family,
      ),
      home: AnimatedBuilder(
        animation: store,
        builder: (context, _) => store.signedIn
            ? StudioShell(key: ValueKey(store.selectedAccount), store: store, vault: _vault)
            : showLogin
                ? LoginPage(
                    onBack: () => setState(() => showLogin = false),
                    onSubmit: store.signInDemo,
                  )
                : WelcomePage(
                    onStart: () => setState(() => showLogin = true),
                    onDemoStart: () => store.signInDemo('creator@hotice.demo'),
                  ),
      ),
    );
  }
}

class StudioShell extends StatefulWidget {
  final HotIceStore store;
  final ActorVault vault;
  const StudioShell({super.key, required this.store, required this.vault});

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int selected = 0;
  String? openedProjectId;
  InspirationTemplate? selectedTemplate;
  int templateRevision = 0;

  void useInspiration(InspirationTemplate item) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selectedTemplate = item;
      templateRevision++;
      selected = 1;
    });
  }

  void navigate(int index) {
    // IndexedStack deliberately keeps form inputs alive; never leave a
    // hidden editor focused or its Android keyboard covering the next tab.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selected = index;
      if (index == 0) openedProjectId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final wide = MediaQuery.sizeOf(context).width >= 850;


    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: 238,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 28, 12, 34),
                        child: HotIceLogo(),
                      ),
                      for (final option in _nav)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          child: ListTile(
                            selected: selected == option.index,
                            selectedTileColor:
                                store.accent.color.withValues(alpha: .13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: Icon(option.icon),
                            title: Text(option.label),
                            onTap: () => navigate(option.index),
                          ),
                        ),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'HOTICE • Studio prototype\nAI and payments are not connected',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!wide) const HotIceLogo(compact: true),
                        if (wide)
                          Text(
                            _nav[selected].label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        const Spacer(),
                        if (wide)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text('TEST $hoticeAppVersion · $hoticeBuildId',
                              style: const TextStyle(fontSize: 10)),
                          ),
                        if (wide || MediaQuery.sizeOf(context).width >= 640)
                          TextButton.icon(
                            onPressed: () => navigate(3),
                            icon: const Icon(Icons.bolt_rounded, size: 19),
                            label: Text('${store.demoCredits} demo credits'),
                          )
                        else
                          IconButton(
                            tooltip: 'Demo credits: ${store.demoCredits}',
                            onPressed: () => navigate(3),
                            icon: const Icon(Icons.bolt_rounded),
                          ),
                        IconButton(
                          tooltip: 'Inspiration Library',
                          onPressed: () => navigate(6),
                          icon: const Icon(Icons.auto_stories_rounded),
                        ),
                        IconButton(
                          tooltip: 'Switch account',
                          onPressed: () => navigate(5),
                          icon: const CircleAvatar(
                            radius: 17,
                            child: Icon(Icons.person_outline, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    // Switching tabs must not dispose text editors. Keep each
                    // page mounted within this account's keyed StudioShell.
                    // Only the selected page is painted/interactable.
                    child: IndexedStack(
                      index: selected,
                      sizing: StackFit.expand,
                      children: [
                        ProjectsPage(
                          store: store,
                          onOpen: (id) => setState(() {
                            openedProjectId = id;
                            selected = 1;
                          }),
                        ),
                        GenerationHubPage(
                          store: store,
                          initialProjectId: openedProjectId,
                          initialTemplate: selectedTemplate,
                          templateRevision: templateRevision,
                        ),
                        AvatarsPage(store: store, vault: widget.vault),
                        CreditsPage(store: store),
                        SettingsPage(store: store),
                        AccountsPage(store: store),
                        InspirationPage(onUse: useInspiration),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected <= 3 ? selected : 4,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              onDestinationSelected: (index) {
                if (index < 4) {
                  navigate(index);
                } else {
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.auto_stories_rounded),
                            title: const Text('Inspiration Library'),
                            onTap: () { Navigator.pop(ctx); navigate(6); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.tune_rounded),
                            title: const Text('Settings & appearance'),
                            onTap: () { Navigator.pop(ctx); navigate(4); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.people_outline_rounded),
                            title: const Text('Accounts'),
                            onTap: () { Navigator.pop(ctx); navigate(5); },
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                }
              },
              destinations: [
                for (final option in _nav.take(4))
                  NavigationDestination(
                    icon: Icon(option.icon),
                    label: option.label,
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.more_horiz_rounded),
                  label: 'More',
                ),
              ],
            ),
    );
  }
}

class _Destination {
  final int index;
  final String label;
  final IconData icon;
  const _Destination(this.index, this.label, this.icon);
}

const _nav = <_Destination>[
  _Destination(0, 'Projects', Icons.grid_view_rounded),
  _Destination(1, 'Generate', Icons.movie_creation_outlined),
  _Destination(2, 'Actors', Icons.face_retouching_natural_outlined),
  _Destination(3, 'Credits', Icons.toll_outlined),
  _Destination(4, 'Settings', Icons.tune_rounded),
  _Destination(5, 'Accounts', Icons.people_outline_rounded),
  _Destination(6, 'Inspiration', Icons.auto_stories_outlined),
];
