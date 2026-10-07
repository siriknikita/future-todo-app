# future-todo-app
The most advanced future to-do application in the whole world that vibecoding have ever seen.

- [Architecture and tech stack](ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)

## Quickstart

Prerequisites: Docker, JDK 21, Flutter (stable).

```sh
cp .env.example .env          # local placeholder settings
docker compose up -d          # PostgreSQL, MinIO, Mailpit

cd backend && gradle bootRun               # API on http://localhost:8080 (no wrapper yet: run `gradle wrapper` once)

cd app && flutter create . --platforms web # once; keep the committed web/index.html and manifest.json
# also put sqlite3.wasm and drift_worker.js into app/web/ (see CLAUDE.md)
flutter pub get && dart run build_runner build --delete-conflicting-outputs --force-jit
flutter run -d chrome --web-port 8081 --dart-define=API_BASE_URL=http://localhost:8080
```

| Service | URL |
|---|---|
| Mailpit (caught emails) | http://localhost:8025 |
| MinIO console | http://localhost:9001 |
| PostgreSQL | localhost:5432 |

Tests and linters: see [CLAUDE.md](CLAUDE.md#commands). CI runs from `.github/workflows/` (`backend.yml`, `app.yml`).

