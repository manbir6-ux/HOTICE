import 'package:flutter/material.dart';
import 'backend_auth.dart';
import 'design.dart';
import 'state.dart';
import 'diagnostics.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onDemoStart;
  final VoidCallback? onBackendLogin;
  const WelcomePage({
    super.key,
    required this.onStart,
    required this.onDemoStart,
    this.onBackendLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1528), Color(0xFF1B1830), Color(0xFF0C3848)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // During Android route transitions the first frame may arrive
              // with zero or tiny constraints; never build full-width branding
              // and fixed-size controls into an impossible layout.
              if (constraints.maxWidth < 120) {
                return const SizedBox.shrink();
              }
              if (constraints.maxWidth < 400) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: FittedBox(child: HotIceLogo(compact: true))),
                      const SizedBox(height: 20),
                      const FittedBox(
                        child: Text('Create without limits.',
                            style: TextStyle(color: Colors.white,
                                fontSize: 32, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cinematic video, recurring characters and your creative studio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFCAD3E7), fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      FittedBox(
                        child: TextButton.icon(
                          onPressed: onDemoStart,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Explore demo studio'),
                        ),
                      ),
                      FittedBox(
                        child: TextButton(
                          onPressed: onStart,
                          child: const Text('Continue with demo email'),
                        ),
                      ),
                      if (onBackendLogin != null)
                        FittedBox(
                          child: TextButton.icon(
                            onPressed: onBackendLogin,
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Sign in to HOTICE'),
                          ),
                        ),
                      if (constraints.maxWidth >= 280) ...[
                        const SizedBox(height: 18),
                        const FilmPreview(title: 'YOUR STORY. YOUR UNIVERSE.'),
                      ],
                    ],
                  ),
                );
              }
              // Flutter can briefly lay out a new route with zero width.
              // Never subtract padding from a transient 0px constraint.
              // The previous `constraints.maxWidth - 50` produced -50.0,
              // causing the original BoxConstraints failure on Android.
              final double panelWidth = constraints.maxWidth > 820
                  ? 450.0
                  : (constraints.maxWidth - 50.0).clamp(0.0, 450.0);
              return SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Theme(
                        data: ThemeData.dark(),
                        child: const HotIceLogo(),
                      ),
                      const SizedBox(height: 55),
                      Wrap(
                        spacing: 36,
                        runSpacing: 35,
                        children: [
                          SizedBox(
                            width: panelWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('THE NEXT FRAME STARTS HERE',
                                    style: TextStyle(
                                      color: Color(0xFF7CE3FC),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2,
                                    )),
                                const SizedBox(height: 22),
                                Text('Create without limits.',
                                    style: TextStyle(
                                      fontSize: constraints.maxWidth < 510 ? 37 : 49,
                                      height: 1.05,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -2,
                                    )),
                                const SizedBox(height: 18),
                                const Text(
                                  'Cinematic video. Consistent characters. A creative studio built for the boldest ideas.',
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: Color(0xFFCAD3E7),
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 30),
                                PrimaryButton(
                                  label: 'Explore demo studio',
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: onDemoStart,
                                ),
                                const SizedBox(height: 8),
                                FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: TextButton.icon(
                                    onPressed: onStart,
                                    icon: const Icon(Icons.alternate_email),
                                    label: const Text('Continue with a demo email',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                                if (onBackendLogin != null)
                                  TextButton.icon(
                                    onPressed: onBackendLogin,
                                    icon: const Icon(Icons.lock_outline),
                                    label: const Text('Sign in to HOTICE',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                const SizedBox(height: 17),
                                const Text(
                                  'TEST BUILD $hoticeAppVersion · $hoticeBuildId\nSTUDIO UI PROTOTYPE • RENDERING COMING LATER',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    letterSpacing: 1,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: panelWidth,
                            child: const FilmPreview(
                                title: 'YOUR STORY. YOUR UNIVERSE.'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 45),
                      const Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Highlight('AI video', Icons.movie_filter_outlined),
                          _Highlight('Avatar lab', Icons.face_outlined),
                          _Highlight('Project studio', Icons.layers_outlined),
                          _Highlight('Multi-model workflow', Icons.hub_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  final String title;
  final IconData icon;
  const _Highlight(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: .09),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<String> onSubmit;
  const LoginPage({
    super.key,
    required this.onBack,
    required this.onSubmit,
  });
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  void submit() {
    if (formKey.currentState?.validate() ?? false) {
      widget.onSubmit(email.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageFrame(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 475),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Back to welcome',
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const HotIceLogo(),
                  const SizedBox(height: 30),
                  Text('Welcome to HOTICE',
                    style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  const Text('Enter any valid email format to try a separate local demo workspace.'),
                  const SizedBox(height: 20),
                  StudioPanel(
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const DemoNotice(
                            'No real login or registration is connected. Never enter a password; demo profiles live only until the app closes.',
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.email],
                            onFieldSubmitted: (_) => submit(),
                            decoration: const InputDecoration(
                              labelText: 'Demo email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (v) => !isValidDemoEmail(v ?? '')
                                ? 'Enter a valid email format' : null,
                          ),
                          const SizedBox(height: 19),
                          PrimaryButton(
                            label: 'Enter studio',
                            onPressed: submit,
                            icon: Icons.arrow_forward_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BackendLoginPage extends StatefulWidget {
  const BackendLoginPage({
    super.key,
    required this.onBack,
    required this.onSubmit,
  });

  final VoidCallback onBack;
  final Future<void> Function(String email, String password)? onSubmit;

  @override
  State<BackendLoginPage> createState() => _BackendLoginPageState();
}

class _BackendLoginPageState extends State<BackendLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || widget.onSubmit == null ||
        !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit!(_email.text, _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.onSubmit != null;
    return Scaffold(
      body: SafeArea(
        child: PageFrame(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 475),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Back to welcome',
                      onPressed: _busy ? null : widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const HotIceLogo(),
                  const SizedBox(height: 30),
                  Text('Sign in to HOTICE',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Your password is sent only to your configured HOTICE server over HTTPS.',
                  ),
                  const SizedBox(height: 20),
                  StudioPanel(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!configured)
                            const DemoNotice(
                              'Server sign-in is unavailable in this build. Configure the HOTICE API address to enable it. Guest demo remains available.',
                            ),
                          if (configured)
                            const Text(
                              'Sign-in is verified by the HOTICE server. The password is never saved on this device.',
                            ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (value) => !isValidDemoEmail(value ?? '')
                                ? 'Enter a valid email address.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: (value) => (value ?? '').isEmpty
                                ? 'Enter your password.'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          ],
                          const SizedBox(height: 19),
                          PrimaryButton(
                            label: _busy ? 'Signing in…' : 'Sign in',
                            onPressed: configured && !_busy ? _submit : null,
                            icon: Icons.login_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
