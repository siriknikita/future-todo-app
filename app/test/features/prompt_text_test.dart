import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/l10n/app_localizations.dart';

/// Opens [promptText] from a button and reports what it returned.
Future<List<String?>> pumpPrompt(
  WidgetTester tester, {
  String initial = '',
  int? maxLength,
}) async {
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            maxLength == null
                ? await promptText(context, title: 'Name', initial: initial)
                : await promptText(
                    context,
                    title: 'Name',
                    initial: initial,
                    maxLength: maxLength,
                  ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('returns the trimmed text from the save button', (tester) async {
    final results = await pumpPrompt(tester, initial: 'Old');
    expect(find.text('Old'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('prompt-field')), '  New  ');
    await tester.tap(find.byKey(const Key('prompt-ok')));
    await tester.pumpAndSettle();

    expect(results, ['New']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('submitting from the keyboard also returns the text',
      (tester) async {
    final results = await pumpPrompt(tester);

    await tester.enterText(find.byKey(const Key('prompt-field')), ' Home ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results, ['Home']);
  });

  testWidgets('cancel and empty text return null', (tester) async {
    final results = await pumpPrompt(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt-field')), '   ');
    await tester.tap(find.byKey(const Key('prompt-ok')));
    await tester.pumpAndSettle();

    expect(results, [null, null]);
  });

  testWidgets('input is limited to maxLength', (tester) async {
    final results = await pumpPrompt(tester, maxLength: 3);

    await tester.enterText(find.byKey(const Key('prompt-field')), 'abcdef');
    await tester.tap(find.byKey(const Key('prompt-ok')));
    await tester.pumpAndSettle();

    expect(results, ['abc']);
  });
}
