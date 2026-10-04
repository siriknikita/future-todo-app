# Build context: app/   (docker build -t future-todo-app app)

# ---- Build stage: Flutter web ----
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .
# Platform files and Drift web assets are not committed yet: generate/fetch them
# without overwriting the committed web/index.html and web/manifest.json.
ARG API_BASE_URL=""
RUN cp web/index.html web/manifest.json /tmp/ \
    && flutter create . --platforms web --project-name future_todo --org com.futuretodo \
    && cp /tmp/index.html /tmp/manifest.json web/ \
    && rm -f test/widget_test.dart \
    && ( [ -f web/sqlite3.wasm ] || curl -fsSL -o web/sqlite3.wasm https://github.com/simolus3/sqlite3.dart/releases/latest/download/sqlite3.wasm ) \
    && ( [ -f web/drift_worker.js ] || curl -fsSL -o web/drift_worker.js https://github.com/simolus3/drift/releases/latest/download/drift_worker.js )
RUN flutter pub get \
    && dart run build_runner build --delete-conflicting-outputs \
    && flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL

# ---- Runtime stage: nginx ----
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
