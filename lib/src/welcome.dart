import 'dart:convert';

import 'package:flutter/material.dart';
import 'account_api.dart';
import 'design.dart';
import 'state.dart';
import 'diagnostics.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onDemoStart;
  const WelcomePage({super.key, required this.onStart, required this.onDemoStart});

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
                          child: const Text('Sign in or create account'),
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
                                    label: const Text('Sign in or create account',
                                        style: TextStyle(color: Colors.white)),
                                  ),
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
  final AccountApi accountApi;
  final ValueChanged<AccountUser> onAuthenticated;
  const LoginPage({
    super.key,
    required this.onBack,
    required this.accountApi,
    required this.onAuthenticated,
  });
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool creatingAccount = false;
  bool busy = false;
  bool statusIsError = false;
  String? statusMessage;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !(formKey.currentState?.validate() ?? false)) return;
    setState(() { busy = true; statusMessage = null; statusIsError = false; });
    try {
      if (creatingAccount) {
        await widget.accountApi.register(email.text, password.text);
        if (!mounted) return;
        setState(() {
          creatingAccount = false;
          statusMessage = 'Check your inbox for the verification link. Verify your email, then sign in.';
          password.clear();
        });
      } else {
        final user = await widget.accountApi.signIn(email.text, password.text);
        if (mounted) widget.onAuthenticated(user);
      }
    } on AccountApiException catch (error) {
      if (mounted) setState(() { statusMessage = error.message; statusIsError = true; });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendVerification() async {
    if (busy) return;
    setState(() { busy = true; statusMessage = null; statusIsError = false; });
    try {
      await widget.accountApi.resendVerification(email.text);
      if (mounted) setState(() => statusMessage = 'If this account needs verification, a fresh link will be sent.');
    } on AccountApiException catch (error) {
      if (mounted) setState(() { statusMessage = error.message; statusIsError = true; });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestPasswordReset() async {
    if (!isValidDemoEmail(email.text)) {
      setState(() { statusMessage = 'Enter your account email first.'; statusIsError = true; });
      return;
    }
    if (busy) return;
    setState(() { busy = true; statusMessage = null; statusIsError = false; });
    try {
      await widget.accountApi.requestPasswordReset(email.text);
      if (mounted) setState(() => statusMessage = 'If this verified account exists, a password reset link will be sent.');
    } on AccountApiException catch (error) {
      if (mounted) setState(() { statusMessage = error.message; statusIsError = true; });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 56),
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
                      onPressed: busy ? null : widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const HotIceLogo(),
                  const SizedBox(height: 30),
                  Text(creatingAccount ? 'Create your HOTICE account' : 'Welcome to HOTICE',
                    style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  const Text('Use your secure HOTICE account. Projects stay on this device unless you choose cloud features.'),
                  const SizedBox(height: 20),
                  StudioPanel(
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!widget.accountApi.isConfigured)
                            const DemoNotice('Secure account sign-in is not configured in this build. You can still explore the clearly labeled guest demo.'),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: email,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (v) => !isValidDemoEmail(v ?? '')
                                ? 'Enter a valid email address' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: password,
                            enabled: !busy,
                            obscureText: true,
                            autofillHints: [creatingAccount ? AutofillHints.newPassword : AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => submit(),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: (value) {
                              final length = value == null ? 0 : utf8.encode(value).length;
                              if (creatingAccount && length < 12) return 'Use at least 12 bytes.';
                              if (length == 0) return 'Enter your password.';
                              if (length > 256) return 'Password is too long.';
                              return null;
                            },
                          ),
                          if (statusMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(statusMessage!, style: TextStyle(color: statusIsError ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary)),
                          ],
                          const SizedBox(height: 19),
                          PrimaryButton(
                            label: busy ? 'Please wait…' : creatingAccount ? 'Create account' : 'Sign in',
                            onPressed: busy || !widget.accountApi.isConfigured ? null : submit,
                            icon: creatingAccount ? Icons.person_add_alt_1 : Icons.login_rounded,
                          ),
                          TextButton(
                            onPressed: busy ? null : () => setState(() { creatingAccount = !creatingAccount; statusMessage = null; statusIsError = false; }),
                            child: Text(creatingAccount ? 'Already have an account? Sign in' : 'New to HOTICE? Create an account'),
                          ),
                          if (!creatingAccount) ...[
                            TextButton(onPressed: busy ? null : requestPasswordReset, child: const Text('Forgot password?')),
                            TextButton(onPressed: busy ? null : resendVerification, child: const Text('Resend verification email')),
                          ],
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
