import 'package:flutter/material.dart';

/// Opens a text-editing dialog whose controller belongs to its own State.
/// It remains mounted during the closing route animation, so callers can
/// immediately update projects or navigate after Navigator.pop completes.
/// The dialog's State.dispose is the sole owner of controller disposal.
Future<String?> showHotIceTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String initialValue = '',
  int maxLength = 500,
  int minLines = 1,
  int maxLines = 1,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<String>(
    context: context,
    builder: (_) => _HotIceTextDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
    ),
  );
  final result = await navigator.push<String>(route);
  assert(() {
    debugPrint('HOTICE dialog returned a value: ${result != null}');
    return true;
  }());
  return result;
}

class _HotIceTextDialog extends StatefulWidget {
  const _HotIceTextDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.initialValue,
    required this.maxLength,
    required this.minLines,
    required this.maxLines,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String initialValue;
  final int maxLength;
  final int minLines;
  final int maxLines;

  @override
  State<_HotIceTextDialog> createState() => _HotIceTextDialogState();
}

class _HotIceTextDialogState extends State<_HotIceTextDialog> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    FocusScope.of(context).unfocus();
    assert(() { debugPrint('HOTICE dialog save tapped'); return true; }());
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _text,
          autofocus: true,
          maxLength: widget.maxLength,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textCapitalization: widget.minLines == 1
              ? TextCapitalization.sentences
              : TextCapitalization.none,
          textInputAction:
              widget.maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
          onSubmitted: widget.maxLines == 1 ? (_) => _save() : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: widget.label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _text.text.trim().isEmpty ? null : _save,
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}
