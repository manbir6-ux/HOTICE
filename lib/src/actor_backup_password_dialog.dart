import 'package:flutter/material.dart';

/// Keep passphrases out of Actor metadata, scene drafts and diagnostics.
/// A modal owns its temporary TextEditingControllers and disposes them.
Future<String?> requestActorBackupPassword(
  BuildContext context, {
  required bool creatingBackup,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ActorBackupPasswordDialog(creatingBackup: creatingBackup),
);

class _ActorBackupPasswordDialog extends StatefulWidget {
  const _ActorBackupPasswordDialog({required this.creatingBackup});
  final bool creatingBackup;

  @override
  State<_ActorBackupPasswordDialog> createState() =>
      _ActorBackupPasswordDialogState();
}

class _ActorBackupPasswordDialogState
    extends State<_ActorBackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  bool _visible = false;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _confirm() {
    final passphrase = _password.text;
    if (widget.creatingBackup &&
        (passphrase.length < 12 || passphrase.length > 256)) {
      setState(() => _error =
          'Choose a password between 12 and 256 characters.');
      return;
    }
    if (passphrase.isEmpty) {
      setState(() => _error = 'Enter your Actor backup password.');
      return;
    }
    if (widget.creatingBackup && passphrase != _confirmation.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(passphrase);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creatingBackup
        ? 'Encrypt Actor backup'
        : 'Unlock Actor backup'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.creatingBackup
                ? 'HOTICE encrypts the exported face photos with this '
                    'password. Store it safely: HOTICE cannot recover '
                    'a lost password.'
                : 'Enter the password used when this Actor backup was '
                    'created. It never leaves your device.'),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: !_visible,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 256,
              decoration: const InputDecoration(
                labelText: 'Backup password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) {
                if (!widget.creatingBackup) _confirm();
              },
            ),
            if (widget.creatingBackup) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _confirmation,
                obscureText: !_visible,
                enableSuggestions: false,
                autocorrect: false,
                maxLength: 256,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
                onSubmitted: (_) => _confirm(),
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show password'),
              dense: true,
              value: _visible,
              onChanged: (value) =>
                  setState(() => _visible = value ?? false),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _confirm,
        child: Text(widget.creatingBackup
            ? 'Encrypt backup'
            : 'Unlock'),
      ),
    ],
  );
}
