import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';

Future<void> showSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _SettingsDialog(),
    );

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return AlertDialog(
      title: Text(l.settings),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.theme, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              key: const Key('theme-selector'),
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(l.themeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(l.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(l.themeDark),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => notifier.setThemeMode(s.first),
            ),
            const SizedBox(height: 24),
            Text(l.language, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const Key('language-selector'),
              segments: [
                ButtonSegment(value: '', label: Text(l.languageSystem)),
                const ButtonSegment(value: 'uk', label: Text('Українська')),
                const ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {settings.languageCode ?? ''},
              onSelectionChanged: (s) =>
                  notifier.setLanguage(s.first.isEmpty ? null : s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
