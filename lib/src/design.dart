import 'package:flutter/material.dart';

class HotIceDesign {
  static ThemeData theme(Brightness brightness, Color seed) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF0A0D16) : const Color(0xFFF5F7FB),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -.9,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1B2030) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class HotIceLogo extends StatelessWidget {
  final bool compact;
  const HotIceLogo({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 32 : 38,
          height: compact ? 32 : 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: const LinearGradient(
              colors: [Color(0xFF42D1EF), Color(0xFF9A69FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text(
          'HOTICE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: compact ? 20 : 23,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class StudioPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF151A29) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark ? Colors.white.withOpacity(.075) : const Color(0xFFE4E8F2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? .14 : .04),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PageFrame extends StatelessWidget {
  final Widget child;
  const PageFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: child,
        ),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  const PageTitle({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 10),
        Text(title, style: theme.textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(subtitle, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 26),
      ],
    );
  }
}

class DemoNotice extends StatelessWidget {
  final String message;
  const DemoNotice(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class FilmPreview extends StatelessWidget {
  final String title;
  const FilmPreview({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF152C4B),
              Color(0xFF49336D),
              Color(0xFFB05370),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -25,
              top: -55,
              child: Icon(
                Icons.blur_circular,
                size: 210,
                color: Colors.white.withOpacity(.13),
              ),
            ),
            const Center(
              child: Icon(Icons.play_circle_outline_rounded,
                  size: 67, color: Colors.white),
            ),
            Positioned(
              left: 20,
              bottom: 20,
              right: 20,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
