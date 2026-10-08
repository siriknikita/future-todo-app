# Build context: backend/   (docker build -t future-todo-backend backend)

# ---- Build stage ----
FROM gradle:8-jdk21 AS build
WORKDIR /workspace
COPY . .
# Tests run in CI, not during the image build.
RUN gradle bootJar -x test --no-daemon

# ---- Runtime stage ----
FROM eclipse-temurin:25-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
# bootJar also leaves a *-plain.jar next to the executable jar; copy only the latter.
COPY --from=build /workspace/build/libs/future-todo-backend-0.1.0.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
