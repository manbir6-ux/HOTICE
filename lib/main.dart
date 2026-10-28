import 'package:flutter/material.dart';
import 'src/state.dart';
import 'src/design.dart';
import 'src/pages.dart';
import 'src/generation_hub.dart';
import 'src/diagnostics.dart';
import 'src/local_store.dart';
import 'src/backend_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HoticeDiagnostics.install();
  final store = HotIceStore();
  final authClient = BackendAuthClient.fromEnvironment();
  try {
    final archive = await HotIceLocalArchive.openOnDevice();
    final snapshot = await archive.restore();
    if (snapshot != null) store.restoreLocalSnapshot(snapshot);
    if (authClient != null) {
      final user = await authClient.restoreSession();
      if (user != null) store.signInBackend(user.email);
    }
    // A crash must never silently reset the user's encrypted projects.
    // Capture immutable JSON snapshots before queuing any asynchronous writes.
    store.addListener(() => archive.enqueue(store.exportLocalSnapshot()));
    runApp(HotIceApp(initialStore: store, authClient: authClient));
  } catch (_) {
    authClient?.close();
    store.dispose();
    runApp(const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'HOTICE could not safely open your encrypted projects. '
                'Your saved files were NOT erased or replaced. '
                'Please recover your device key or backup before continuing.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

class HotIceApp extends StatefulWidget {
  const HotIceApp({super.key, this.initialStore, this.authClient});
  final HotIceStore? initialStore;
  final BackendAuthClient? authClient;

  @override
  State<HotIceApp> createState() => _HotIceAppState();
}

class _HotIceAppState extends State<HotIceApp> {
  late final HotIceStore store;
  bool showLogin = false;
  bool showBackendLogin = false;

  late ThemeMode _lastThemeMode;
  late StudioAccent _lastAccent;
  late StudioFont _lastFont;

  @override
  void initState() {
    super.initState();
    store = widget.initialStore ?? HotIceStore();
    _lastThemeMode = store.themeMode;
    _lastAccent = store.accent;
    _lastFont = store.font;
    store.addListener(_handleAppearanceChanged);
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
    store.dispose();
    widget.authClient?.close();
    super.dispose();
  }

  Future<void> _signInBackend(String email, String password) async {
    final auth = widget.authClient;
    if (auth == null) {
      throw const BackendAuthException('Server sign-in is not configured in this build.');
    }
    final user = await auth.signIn(email, password);
    store.signInBackend(user.email);
  }

  Future<String?> _signOut() async {
    String? warning;
    if (store.backendAuthenticated && widget.authClient != null) {
      try {
        await widget.authClient!.signOut();
      } catch (_) {
        warning = 'Signed out on this device. Server revocation could not be confirmed; the server session remains valid until its configured expiry.';
      }
    }
    store.signOut();
    return warning;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HOTICE',
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
            ? StudioShell(
                key: ValueKey(store.selectedAccount),
                store: store,
                onSignOut: _signOut,
              )
            : showLogin
                ? LoginPage(
                    onBack: () => setState(() => showLogin = false),
                    onSubmit: store.signInDemo,
                  )
                : showBackendLogin
                    ? BackendLoginPage(
                        onBack: () => setState(() => showBackendLogin = false),
                        onSubmit: widget.authClient == null ? null : _signInBackend,
                      )
                : WelcomePage(
                    onStart: () => setState(() => showLogin = true),
                    onDemoStart: () => store.signInDemo('creator@hotice.demo'),
                    onBackendLogin: () => setState(() => showBackendLogin = true),
                  ),
      ),
    );
  }
}

class StudioShell extends StatefulWidget {
  final HotIceStore store;
  final Future<String?> Function()? onSignOut;
  const StudioShell({super.key, required this.store, this.onSignOut});

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int selected = 0;
  String? openedProjectId;

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
                        if (wide || MediaQuery.sizeOf(context).width >= 410)
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
                          isActive: selected == 1,
                        ),
                        AvatarsPage(store: store),
                        CreditsPage(store: store),
                        SettingsPage(store: store),
                        AccountsPage(store: store, onSignOut: widget.onSignOut),
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
              selectedIndex: selected <= 4 ? selected : 4,
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
  _Destination(2, 'Avatars', Icons.face_retouching_natural_outlined),
  _Destination(3, 'Credits', Icons.toll_outlined),
  _Destination(4, 'Settings', Icons.tune_rounded),
  _Destination(5, 'Accounts', Icons.people_outline_rounded),
];
