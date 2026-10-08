# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Context: university lab project

This repo is a three-person team project for the Lviv Polytechnic course "Методології розробки програмного забезпечення" (Software Development Methodologies). The product is **Future Todo**. The team chose **Extreme Programming (XP)** as its methodology in Lab 1, and the code here is how the XP practices get demonstrated. Lab reports are written in Ukrainian and live outside this repo.

The course is a chain of labs that build on the same codebase:

| Lab | Goal | What the report must show |
|---|---|---|
| 1 (done) | Requirements spec (SRS) for Future Todo and justification for choosing XP. Roles set up in Jira | SRS, reasoning for the methodology choice, Jira board screenshots |
| **2 (current)** | Build the product as a team following XP, with **at least one unit, one integration, and one e2e test** | Source code, a test report, a log of the program running, Jira screenshots, and pros/cons of XP |
| 3 | Refactor the Lab 2 code. Each code flaw found becomes its own Jira task | Code before and after refactoring, the flaws and how they were fixed |
| 4 | CI/CD pipeline. CI: build, static analysis, and tests on every change. CD: build an artifact and deploy it to a test environment | Pipeline config, a diagram of its stages, one successful run and one run **stopped by failing tests**. Optional extra task: add the "Pentagon" testing model's L3/L5 levels and split the test levels across environments |

What this means for the work:
- Lab 3 needs the Lab 2 code in its original form. Keep that state recoverable from git (e.g. tag the end of Lab 2) and don't sneak refactors into Lab 2 that Lab 3 is meant to show.
- Lab 4 needs tests that can fail a pipeline run and a static-analysis step. Keep every test level and every linter runnable from the command line, without an IDE.
- Lab 2 must actually run and produce output for the report. A working vertical slice of the key requirements (marked О, "mandatory") is worth more than broad but unfinished coverage of the SRS.

## Current state

The stack is chosen. Infrastructure and tooling are in place (`docker-compose.yml`, `.github/workflows/`, Dockerfiles, `.env.example`, Dependabot for `github-actions`, `gradle`, `pub`, `docker`). Application code lives in `backend/` and `app/`; only the Flutter **web** client and the monolithic backend are in scope for now.

When code changes:
- Update `ARCHITECTURE.md` wherever the code differs from the plan.
- Keep the commands below in sync with `backend/build.gradle.kts` and `app/pubspec.yaml`.

## Commands

Local services (Postgres, MinIO, Mailpit): `cp .env.example .env`, then `docker compose up -d`. Stop with `docker compose down` (add `-v` to wipe data). Ports: Postgres 5432, MinIO 9000/9001 (console), Mailpit SMTP 1025 / UI 8025.

### Backend (`backend/`, run from that directory)

There is no Gradle wrapper yet: run `gradle wrapper` once (then use `./gradlew` instead of `gradle`). All test levels run under the single `test` task and are split by class name.

| Task | Command |
|---|---|
| Run the app (after `docker compose up -d`) | `gradle bootRun` (health: http://localhost:8080/actuator/health; OpenAPI: `/v3/api-docs`) |
| Lint | `gradle ktlintCheck detekt` (auto-format: `gradle ktlintFormat`) |
| Unit tests (JUnit 5 + MockK, plus `ModularityTest`) | `gradle test --tests "*AuthServiceTest" --tests "*JwtAndLimiterTest" --tests "*LwwTest" --tests "*HlcClockTest" --tests "*RecurrenceCalculatorTest" --tests "*EntitySpecsTest" --tests "*SearchAndSmartListTest" --tests "*ModularityTest"` |
| Integration tests (Testcontainers PostgreSQL, needs Docker) | `gradle test --tests "*IntegrationTest"` |
| E2E / API tests (HTTP level) | `gradle test --tests "*E2eTest"` |
| Everything | `gradle test` |
| Coverage gate (>= 80%) | `gradle koverHtmlReport koverVerify` (report: `build/reports/kover/html`) |
| Single test class / method | `gradle test --tests "com.futuretodo.FutureTodoE2eTest"` / `--tests "*SomeTest.someMethod"` |
| Jar / Docker image | `gradle bootJar` / `docker build -t future-todo-backend backend` |

When adding a test class, name it `*Test` (unit), `*IntegrationTest` or `*E2eTest`, and add new unit classes to the unit filter list in `.github/workflows/backend.yml`. The filter matches class names, not file names, so list every class in a file that holds several.

Config (env vars): `DB_URL`/`DB_USER`/`DB_PASSWORD` (defaults match `docker-compose.yml`), `MAIL_HOST`/`MAIL_PORT`, `JWT_SECRET`, `FRONTEND_URL`, `CORS_ORIGINS`, `ADMIN_EMAIL`/`ADMIN_PASSWORD`, `OAUTH_GOOGLE_CLIENT_ID`/`OAUTH_APPLE_CLIENT_ID`/`OAUTH_MICROSOFT_CLIENT_ID`.

### App (`app/`, run from that directory)

Use Flutter **3.38.5**, the version pinned in `.github/workflows/app.yml` and `app/Dockerfile` (newer releases add lints and deprecations that fail `flutter analyze --fatal-infos`). Bump all three together.

Only `web/index.html` and `web/manifest.json` are committed. Before the first run: `flutter create . --platforms web` (keep the committed web files; delete the generated `test/widget_test.dart`) and put `sqlite3.wasm` and `drift_worker.js` into `web/` (CI and the Dockerfile do this automatically). Drift tests use an in-memory SQLite and need system `libsqlite3` (`apt install libsqlite3-dev`).

| Task | Command |
|---|---|
| Install deps | `flutter pub get` |
| Generate code (Drift) | `dart run build_runner build --delete-conflicting-outputs --force-jit` |
| Lint | `dart format --set-exit-if-changed lib test` and `flutter analyze --fatal-infos` |
| Unit + widget tests with coverage | `flutter test --coverage` (report in `coverage/lcov.info`; CI requires >= 80%) |
| Single test file / test by name | `flutter test test/core/hlc_test.dart` / `flutter test --plain-name "some name"` |
| E2E on web (guest flow, no backend; needs chromedriver on port 4444) | `chromedriver --port=4444 &` then `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d web-server --browser-name=chrome --headless` |
| Run in Chrome against the backend | `flutter run -d chrome --web-port 8081 --dart-define=API_BASE_URL=http://localhost:8080` |
| Web build / Docker image | `flutter build web --release --dart-define=API_BASE_URL=...` / `docker build -t future-todo-app app` |

### CI (`.github/workflows/`)

`backend.yml` and `app.yml` are path-filtered and run on pushes to `main` and on pull requests. Each test level is its own job (`unit-tests`, `integration-tests`, `e2e-tests` for the backend; `unit-tests`, `e2e-web` for the app, which needs no backend), so a failing level stops the pipeline on its own job. The pipelines are CI only (build, lint, test, coverage); there is no deploy yet.

## Stack and architecture

**`ARCHITECTURE.md` is the source of truth.** It covers the stack, module layout, sync design, the Stage 2 plan, the testing strategy, and the reasons behind each choice. Summary:

- **Client:** one Flutter (Dart) codebase for Web, Windows, macOS, Linux, Android, and iOS. Riverpod, go_router, Drift (SQLite) as the offline local database.
- **Backend:** Kotlin + Spring Boot + **Spring Modulith** as a modular monolith. PostgreSQL with Flyway migrations. REST + JSON with an OpenAPI 3 spec generated by springdoc. WebSocket for real-time updates.
- **Tests:** JUnit 5, MockK, Testcontainers, and Kover on the backend; `flutter_test` and `integration_test` on the client. **CI:** GitHub Actions.
- **Planned layout:** `app/` (Flutter), `backend/` (Spring Boot), `api/openapi.json` (committed spec), and `docker-compose.yml` (Postgres, MinIO, Mailpit).

Rules that are easy to break. Requirement IDs are `FR-x.y` / `PR-n` from the Lab 1 SRS.
- **A backend module never touches another module's tables or internal packages.** Each module (`accounts`, `tasks`, `sharing`, `sync`, `notifications`, `files`) owns its own Postgres schema. Cross-module calls go through the other module's public top-level package or through application events. `ApplicationModules.verify()` must keep passing. This is what makes the Stage 2 split into microservices possible.
- **`api/openapi.json` is the public API contract.** Changing it means changing the API, which is versioned under `/api/v1` and must stay backward compatible. Stage 2 must leave it unchanged. The Flutter API client is generated from this file and never hand-written.
- **The client is offline-first.** The UI reads and writes only the local Drift database, and the network is used only by the sync component. Conflicts are resolved **per field, last write wins**, using HLC (hybrid logical clock) timestamps. Deletes are tombstones.
- **Reminders are scheduled locally on each device.** Server push is only for events caused by other users, such as a task being assigned to you.
- **Time zones:** "My Day" resets at 00:00 in the **user's local time**. Reminders follow the user's current time zone.
- **Auth:** Argon2 password hashing. JWT access tokens last 15 minutes; refresh tokens are rotated and stored hashed. Login is rate-limited with Bucket4j.
- **XP rules from the SRS:** TDD, **≥80% test coverage**, and the linters (detekt + ktlint for the backend, `very_good_analysis` for the client) must pass on every change.

## Workflow conventions (Jira project KAN)

Work is tracked in the Jira Scrum project `KAN`, where sprints are XP iterations. Stories are named after the SRS requirement they cover, e.g. `[FR-1.1] Реєстрація за email і паролем...`. Board columns follow the XP flow: In Spec → To Do → TDD (Writing Tests) → Coding → Refactoring → … Screenshots of the board go into every lab report, so development and testing tasks should appear there.

The full details are in `CONTRIBUTING.md`. None of these rules are enforced by CI.

- **Branches** start with the ticket key: `KAN-123-short-description`.
- **Commits** start with the key: `KAN-123 Add due date picker to task form`. Optional smart-commit suffixes: `#comment <text>`, `#time 1h 30m`, `#done` (or another KAN workflow transition name).
- **PR titles** use `KAN-123: Short description`. `main` only accepts squash merges, so the PR title becomes the commit message on `main`.
- **PR body** follows `.github/pull_request_template.md`: the `KAN-` key under **Jira**, plus **What**, **How to test**, and **Checklist**.
- Repo-wide chores with no ticket (the scaffolding commits so far) have used Conventional Commit prefixes such as `chore: ...`.
- Security issues go through GitHub private vulnerability reporting, not public issues. Blank issues are disabled, so new issues must use the bug or feature templates.
