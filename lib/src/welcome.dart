import 'package:flutter/material.dart';
import 'design.dart';
import 'state.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback onStart;
  const WelcomePage({super.key, required this.onStart});

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
            builder: (context, constraints) => SingleChildScrollView(
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
                            width: constraints.maxWidth > 820
                                ? 450
                                : constraints.maxWidth - 50,
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
                                const Text('Create without limits.',
                                    style: TextStyle(
                                      fontSize: 49,
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
                                  label: 'Get started',
                                  onPressed: onStart,
                                ),
                                const SizedBox(height: 17),
                                const Text(
                                  'STUDIO UI PROTOTYPE • RENDERING COMING LATER',
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
                            width: constraints.maxWidth > 820
                                ? 450
                                : constraints.maxWidth - 50,
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
            ),
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
        color: Colors.white.withOpacity(.09),
        border: Border.all(color: Colors.white.withOpacity(.12)),
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
  final password = TextEditingController();
  bool register = false;
  bool hidePassword = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
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
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const HotIceLogo(),
                  const SizedBox(height: 30),
                  Text(
                    register ? 'Create a HOTICE account' : 'Welcome to HOTICE',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 20),
                  StudioPanel(
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const DemoNotice(
                            'Authentication is a UI demo, not a real login. Do not enter a real password.',
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (v) => !isValidDemoEmail(v ?? '')
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: password,
                            obscureText: hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Demo password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                    () => hidePassword = !hidePassword),
                                icon: Icon(hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: (v) => v == null || v.length < 6
                                ? 'Use at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 19),
                          PrimaryButton(
                            label: register ? 'Create demo account' : 'Enter studio',
                            onPressed: submit,
                            icon: Icons.login,
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => register = !register),
                            child: Text(register
                                ? 'Already registered? Sign in'
                                : 'New here? Create an account'),
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
