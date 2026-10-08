import 'package:flutter/material.dart';
import 'package:future_todo/l10n/app_localizations.dart';

/// Shows a dialog with one text field. Returns the trimmed text, or null when
/// cancelled or empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int maxLength = 255,
}) {
  final controller = TextEditingController(text: initial);
  final l = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('prompt-field'),
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('prompt-ok'),
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(l.save),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

/// Text field that commits its value on submit or when it loses focus, and
/// follows external changes while it is not being edited.
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    required this.value,
    required this.onCommit,
    super.key,
    this.decoration,
    this.maxLines = 1,
    this.maxLength,
    this.style,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final InputDecoration? decoration;
  final int? maxLines;
  final int? maxLength;
  final TextStyle? style;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_controller.text != widget.value) widget.onCommit(_controller.text);
  }

  @override
  void didUpdateWidget(CommitTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        style: widget.style,
        decoration: widget.decoration,
        onSubmitted: (_) => _commit(),
      );
}

/// Simple "message" snackbar helper.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
