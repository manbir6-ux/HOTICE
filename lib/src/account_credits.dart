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
  final String? authenticatedEmail;
  final Future<void> Function()? onSignOut;
  const AccountsPage({super.key, required this.store, this.authenticatedEmail, this.onSignOut});
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final email = TextEditingController();

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

  @override
  Widget build(BuildContext context) => PageFrame(
    child: widget.authenticatedEmail != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageTitle(
                eyebrow: 'HOTICE account',
                title: 'Your account',
                subtitle: 'This device is signed in to your HOTICE account.',
              ),
              StudioPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Signed in'),
                      subtitle: Text(widget.authenticatedEmail!),
                    ),
                    const Text('Projects and creative drafts remain local on this device. Cloud sync and paid generation require separate explicit controls.'),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out of HOTICE'),
                    ),
                  ],
                ),
              ),
            ],
          )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle(
          eyebrow: 'Identity',
          title: 'Accounts',
          subtitle: 'Add and switch between studio profiles.',
        ),
        const DemoNotice(
          'Profiles are local UI examples with separate in-memory projects and avatars; no real registration, identity verification or cloud storage exists yet.',
        ),
        const SizedBox(height: 19),
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your profiles',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
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
                label: 'Add / switch account',
                icon: Icons.person_add_alt,
                onPressed: add,
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: widget.store.signOut,
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
