import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'state.dart';
import 'design.dart';

export 'avatar_studio.dart' show AvatarsPage;

class CreditsPage extends StatefulWidget {
  final HotIceStore store;
  const CreditsPage({super.key, required this.store});
  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  int selectedUsd = minimumPurchaseUsd;
  String selectedPayment = 'Stripe';

  void preview() {
    final creditCount = selectedUsd * creditsPerUsd;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checkout preview'),
        content: Text(
          'Selected: US' + r'$' + selectedUsd.toString() +
          ' = ' + creditCount.toString() + ' HOTICE Credits.\n' +
          'Payment option: ' + selectedPayment + '.\n\n' +
          'This is a demo only. No payment is taken and no credits are issued.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            eyebrow: 'Studio wallet',
            title: 'HOTICE Credits',
            subtitle: 'Transparent pricing and flexible payment options.',
          ),
          const DemoNotice(
            'Payment options are previews. Stripe, PayPal, card processing and secure credit ledger are not connected.',
          ),
          const SizedBox(height: 18),
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1 HOTICE Credit = US' + r'$' + '0.01',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Minimum purchase: US' + r'$' + '10'),
                const SizedBox(height: 8),
                Text('Demo-only balance: ' +
                    widget.store.demoCredits.toString() + ' Credits'),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 13,
                  runSpacing: 13,
                  children: [
                    for (final price in [10, 20, 50])
                      SizedBox(
                        width: 195,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => setState(() => selectedUsd = price),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(19),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: selectedUsd == price
                                  ? Theme.of(context)
                                      .colorScheme.primary.withValues(alpha: .13)
                                  : Theme.of(context)
                                      .colorScheme.surfaceContainerHigh,
                              border: Border.all(
                                color: selectedUsd == price
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                                width: selectedUsd == price ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('US' + r'$' + price.toString(),
                                    style: Theme.of(context)
                                        .textTheme.headlineMedium),
                                const SizedBox(height: 8),
                                Text((price * creditsPerUsd).toString() +
                                    ' Credits'),
                                const SizedBox(height: 6),
                                Text(
                                  price == 10 ? 'MINIMUM PACK' : 'CREDIT PACK',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 19),
                Text('Payment method',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    for (final method in [
                      'Stripe', 'PayPal', 'Credit / debit card'
                    ])
                      ChoiceChip(
                        label: Text(method),
                        selected: selectedPayment == method,
                        onSelected: (_) =>
                            setState(() => selectedPayment = method),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Preview checkout',
                  icon: Icons.lock_outline,
                  onPressed: preview,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final HotIceStore store;
  const SettingsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle(
          eyebrow: 'Personalise your space',
          title: 'Appearance & settings',
          subtitle: 'Make HOTICE feel like your own professional studio.',
        ),
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Display mode',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      label: Text(mode.name.toUpperCase()),
                      selected: store.themeMode == mode,
                      onSelected: (_) => store.updateTheme(mode),
                    ),
                ],
              ),
              const SizedBox(height: 25),
              Text('Colour themes',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in StudioAccent.values)
                    ChoiceChip(
                      avatar: CircleAvatar(
                        radius: 8,
                        backgroundColor: option.color,
                      ),
                      label: Text(option.label),
                      selected: store.accent == option,
                      onSelected: (_) => store.updateAccent(option),
                    ),
                ],
              ),
              const SizedBox(height: 23),
              Text('Typography', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final option in StudioFont.values)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: store.font == option,
                      onSelected: (_) => store.updateFont(option),
                    ),
                ],
              ),
              const SizedBox(height: 21),
              const DemoNotice(
                'Theme preferences are held in memory. Persistence and cloud synchronisation come later.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        const StudioPanel(
          child: ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Security & privacy'),
            subtitle: Text(
                'Verified account sessions and privacy controls are on the roadmap.'),
          ),
        ),
      ],
    ),
  );
}

class AccountsPage extends StatefulWidget {
  final HotIceStore store;
  final Future<String?> Function()? onSignOut;
  final Future<Map<String, dynamic>> Function()? onExportAccount;
  final Future<Map<String, dynamic>> Function(String password, String confirmation)? onDeleteAccount;
  const AccountsPage({
    super.key,
    required this.store,
    this.onSignOut,
    this.onExportAccount,
    this.onDeleteAccount,
  });
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final email = TextEditingController();
  bool _accountActionBusy = false;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  void add() {
    if (!isValidDemoEmail(email.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid demo email address.')),
      );
      return;
    }
    widget.store.addAccount(email.text);
    email.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Demo profile selected.')),
    );
  }

  Future<void> signOut() async {
    String? warning;
    try {
      if (widget.onSignOut != null) {
        warning = await widget.onSignOut!();
      } else {
        widget.store.signOut();
      }
    } catch (_) {
      warning = 'Signed out on this device. Server revocation could not be confirmed.';
      widget.store.signOut();
    }
    if (warning != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(warning)),
      );
    }
  }

  Future<void> exportAccount() async {
    if (_accountActionBusy || widget.onExportAccount == null) return;
    setState(() => _accountActionBusy = true);
    try {
      final data = await widget.onExportAccount!();
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      final saved = await FilePicker.saveFile(
        fileName: 'hotice-account-export.json',
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: 'Save your HOTICE account export',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved == null
              ? 'Export canceled. Your account was not changed.'
              : 'Account export saved. Device-only projects and media bytes are not included.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not export account data. Your account was not changed.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _accountActionBusy = false);
    }
  }

  Future<void> deleteAccount() async {
    if (_accountActionBusy || widget.onDeleteAccount == null) return;
    final password = TextEditingController();
    final confirmation = TextEditingController();
    bool deleting = false;
    String? error;
    final removed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete HOTICE account?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This permanently deletes your server account, cloud projects, uploaded media records and job history. Device-local projects remain on this device.'),
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Current password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(
                    error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: deleting ? null : () async {
                if (confirmation.text != 'DELETE' || password.text.isEmpty) {
                  setDialogState(() => error = 'Type DELETE exactly and enter your current password.');
                  return;
                }
                setDialogState(() { deleting = true; error = null; });
                try {
                  await widget.onDeleteAccount!(password.text, confirmation.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (failure) {
                  setDialogState(() {
                    error = failure.toString().replaceFirst('Exception: ', '');
                    deleting = false;
                  });
                }
              },
              child: Text(deleting ? 'Deleting…' : 'Permanently delete'),
            ),
          ],
        ),
      ),
    );
    password.clear();
    confirmation.clear();
    password.dispose();
    confirmation.dispose();
    if (removed == true) {
      widget.store.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your HOTICE account was deleted. Device-only projects remain on this device.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle(
          eyebrow: 'Identity',
          title: 'Accounts',
          subtitle: 'Add and switch between studio profiles.',
        ),
        widget.store.backendAuthenticated
            ? const DemoNotice(
                'Signed in with the HOTICE server. Projects and media stay on this device; cloud sync is not connected.',
              )
            : const DemoNotice(
                'Guest profiles are local examples with separate device workspaces. They are not server accounts.',
              ),
        const SizedBox(height: 19),
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.store.backendAuthenticated ? 'HOTICE server account' : 'Your demo profiles',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (widget.store.backendAuthenticated)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.verified_user_outlined)),
                  title: Text(widget.store.selectedAccount),
                  subtitle: const Text('Authenticated by the HOTICE API'),
                ),
              if (widget.store.backendAuthenticated && widget.onExportAccount != null) ...[
                const Divider(height: 24),
                Text('Your server-held data', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('Device-only projects and media bytes are excluded. Keep a separate backup of local work.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _accountActionBusy ? null : exportAccount,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(_accountActionBusy ? 'Working…' : 'Export account data'),
                    ),
                    if (widget.onDeleteAccount != null)
                      TextButton.icon(
                        onPressed: _accountActionBusy ? null : deleteAccount,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete account'),
                      ),
                  ],
                ),
              ],
              if (!widget.store.backendAuthenticated)
                for (final profile in widget.store.accounts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(profile),
                  subtitle: Text(profile == widget.store.selectedAccount
                      ? 'Active profile'
                      : 'Tap to switch'),
                  trailing: Icon(profile == widget.store.selectedAccount
                      ? Icons.check_circle
                      : Icons.chevron_right),
                  onTap: () => widget.store.switchAccount(profile),
                ),
              if (!widget.store.backendAuthenticated) ...[
                const Divider(height: 28),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Add demo email',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'Add / switch demo profile',
                  icon: Icons.person_add_alt,
                  onPressed: add,
                ),
              ],
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
