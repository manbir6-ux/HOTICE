import 'package:flutter/material.dart';
import 'design.dart';
import 'state.dart';

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
                                TextButton.icon(
                                  onPressed: onStart,
                                  icon: const Icon(Icons.alternate_email),
                                  label: const Text('Continue with a demo email',
                                      style: TextStyle(color: Colors.white)),
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
