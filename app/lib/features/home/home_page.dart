import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/features/sidebar/sidebar.dart';
import 'package:future_todo/features/tasks/task_area.dart';
import 'package:future_todo/features/tasks/task_details.dart';
import 'package:future_todo/features/tasks/task_tile.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';

/// Three-pane layout: sidebar of lists, task area, details panel.
/// Narrow screens use a drawer and show details as a separate page.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final selectedTask = ref.watch(selectedTaskIdProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 700) {
          return Scaffold(
            appBar: AppBar(title: Text(l.appTitle)),
            drawer: Drawer(
              child: Sidebar(
                onSelected: () {
                  Navigator.of(context).maybePop();
                },
              ),
            ),
            body: const TaskArea(),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 280, child: Sidebar()),
              const VerticalDivider(width: 1),
              const Expanded(child: TaskArea()),
              if (width >= wideBreakpoint) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 360,
                  child: selectedTask == null
                      ? Center(child: Text(l.selectTaskHint))
                      : TaskDetails(taskId: selectedTask),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
