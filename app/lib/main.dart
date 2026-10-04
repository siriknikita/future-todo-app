import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:future_todo/app.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens the local database. On web this needs `sqlite3.wasm` and
/// `drift_worker.js` next to `index.html`.
AppDatabase openAppDatabase({String name = 'future_todo'}) => AppDatabase(
      driftDatabase(
        name: name,
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );

Future<void> main() async {
  usePathUrlStrategy(); // links like /join/<token> and /verify-email?token=...
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final db = openAppDatabase();
  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const FutureTodoApp(),
    ),
  );
}
