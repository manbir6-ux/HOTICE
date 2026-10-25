import 'package:flutter/material.dart';

const int creditsPerUsd = 100;
const int minimumPurchaseUsd = 10;

class HotProject {
  final String id;
  final String title;
  final DateTime createdAt;
  const HotProject(this.id, this.title, this.createdAt);
}

class StudioAvatar {
  final String name;
  final String style;
  const StudioAvatar(this.name, this.style);
}

class GenerationDraft {
  final String project;
  final String prompt;
  final String model;
  final String aspectRatio;
  final int durationSeconds;
  final DateTime createdAt;
  const GenerationDraft({
    required this.project,
    required this.prompt,
    required this.model,
    required this.aspectRatio,
    required this.durationSeconds,
    required this.createdAt,
  });
}

enum StudioAccent {
  electric('Electric', Color(0xFF8F72FF)),
  ocean('Ocean', Color(0xFF2CB9C7)),
  ember('Ember', Color(0xFFF47A6C)),
  glacier('Glacier', Color(0xFF589CF7)),
  moss('Moss', Color(0xFF65B986));

  const StudioAccent(this.label, this.color);
  final String label;
  final Color color;
}

class HotIceStore extends ChangeNotifier {
  bool signedIn = false;
  ThemeMode themeMode = ThemeMode.dark;
  StudioAccent accent = StudioAccent.electric;
  String selectedAccount = 'creator@hotice.demo';
  final List<String> accounts = ['creator@hotice.demo'];

  // Mock display balance; never represents purchased or redeemable funds.
  int demoCredits = 1000;
  final List<HotProject> projects = [
    HotProject('demo-film', 'Untitled cinematic film',
        DateTime(2026, 10, 25)),
    HotProject('demo-social', 'Social teaser',
        DateTime(2026, 10, 24)),
  ];
  final List<StudioAvatar> avatars = [
    StudioAvatar('Nova', 'Cinematic'),
  ];
  final List<GenerationDraft> drafts = [];

  void signInDemo(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (!accounts.contains(normalized)) accounts.add(normalized);
    selectedAccount = normalized;
    signedIn = true;
    notifyListeners();
  }

  void signOut() {
    signedIn = false;
    notifyListeners();
  }

  void addAccount(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (!accounts.contains(normalized)) accounts.add(normalized);
    selectedAccount = normalized;
    notifyListeners();
  }

  void switchAccount(String email) {
    if (!accounts.contains(email)) return;
    selectedAccount = email;
    notifyListeners();
  }

  String addProject(String title) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    projects.insert(0, HotProject(id, title.trim(), DateTime.now()));
    notifyListeners();
    return id;
  }

  void addAvatar(String name, String style) {
    avatars.insert(0, StudioAvatar(name.trim(), style));
    notifyListeners();
  }

  void queueDraft(GenerationDraft draft) {
    drafts.insert(0, draft);
    notifyListeners();
  }

  void updateTheme(ThemeMode value) {
    themeMode = value;
    notifyListeners();
  }

  void updateAccent(StudioAccent value) {
    accent = value;
    notifyListeners();
  }
}
