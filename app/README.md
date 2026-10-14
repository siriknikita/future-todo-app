# Future Todo client

The Flutter client of Future Todo. Only the **web** target is in scope for now.

The client is offline-first: the UI reads and writes only the local Drift (SQLite) database, and a background sync component exchanges changes with the backend (`../backend`). State is managed with Riverpod, routing with go_router, and the lints come from `very_good_analysis`.

- `lib/core/`: date helpers, the hybrid logical clock, and last-write-wins merging
- `lib/data/`: Drift database, repository, sync, and the remote API client
- `lib/domain/`: smart lists, sorting, search, and recurrence rules
- `lib/features/`: screens and widgets
- `test/`: unit and widget tests; `integration_test/`: the web e2e test

Generated files (`*.g.dart`, `lib/l10n/app_localizations*.dart`), the platform files from `flutter create`, and the Drift web assets (`web/sqlite3.wasm`, `web/drift_worker.js`) are not committed.

Setup, build, lint and test commands are in [`../CLAUDE.md`](../CLAUDE.md). The design and the reasons behind it are in [`../ARCHITECTURE.md`](../ARCHITECTURE.md).
