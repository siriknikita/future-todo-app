package com.futuretodo.global

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.URI
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.net.http.WebSocket
import java.util.UUID
import java.util.concurrent.CompletionStage
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Level L3 of the "Pentagon" testing model: global integration tests.
 *
 * Unlike the `*IntegrationTest` / `*E2eTest` classes (level L2, the application runs inside the
 * test JVM against a Testcontainers database), these tests start nothing. They call the
 * already deployed Docker images over the network: backend container -> PostgreSQL container,
 * backend -> Mailpit over SMTP, nginx serving the web client, WebSocket push. They check the
 * whole chain from an HTTP client to the final storage, with the configuration of the environment.
 *
 * Run against a deployment: `gradle globalIntegrationTest -PbaseUrl=http://localhost:8080`.
 */
class DeployedStackGlobalTest {
    private val api = DeployedStack.api

    @Test
    fun `deployed backend is healthy, connected to its database and serves the API contract`() {
        val health = Http(DeployedStack.baseUrl).get("/actuator/health")
        assertEquals(200, health.status)
        assertEquals("UP", health.json()["status"].asText())

        val docs = Http(DeployedStack.baseUrl).get("/v3/api-docs")
        assertEquals(200, docs.status)
        val paths = docs.json()["paths"]
        listOf("/api/v1/auth/register", "/api/v1/lists", "/api/v1/sync/push", "/api/v1/sync/pull").forEach {
            assertTrue(paths.has(it), "API contract is missing $it")
        }
    }

    @Test
    fun `registration email goes out over SMTP and its link confirms the account`() {
        val email = "mail-${UUID.randomUUID()}@global.test"
        val password = "global-secret-password"

        assertEquals(201, api.post("/auth/register", body = mapOf("email" to email, "password" to password)).status)
        assertEquals(403, api.post("/auth/login", body = mapOf("email" to email, "password" to password)).status)

        val mail = Mailbox.latestTextTo(email)
        assertTrue(mail.contains("${DeployedStack.webUrl}/verify-email?token="), "Link must point to the deployed web client:\n$mail")
        val token = Mailbox.tokenFromLink(mail, "/verify-email")
        assertEquals(204, api.post("/auth/verify-email", body = mapOf("token" to token)).status)

        val account = signIn(email, password)
        val me = api.get("/me", account.accessToken)
        assertEquals(200, me.status)
        assertEquals(email, me.json()["email"].asText())
    }

    @Test
    fun `lists and tasks written through the API are stored and read back`() {
        val user = registerConfirmedAccount("crud")

        val list = api.post("/lists", user.accessToken, mapOf("name" to "Deployed list", "icon" to "🧪"))
        assertEquals(201, list.status)
        val listId = list.json()["id"].asText()
        val task = api.post("/lists/$listId/tasks", user.accessToken, mapOf("title" to "Check the test environment"))
        assertEquals(201, task.status)
        val taskId = task.json()["id"].asText()

        val done = api.patch("/tasks/$taskId", user.accessToken, mapOf("completed" to true, "important" to true))
        assertEquals(200, done.status)

        // A new session (another device) reads what the first one stored.
        val again = signIn(user.email, user.password, "second-device")
        val tasks = api.get("/lists/$listId/tasks", again.accessToken).json()
        assertEquals(1, tasks.size())
        assertEquals("Check the test environment", tasks[0]["title"].asText())
        assertTrue(tasks[0]["completed"].asBoolean())
        assertTrue(tasks[0]["important"].asBoolean())

        assertEquals(204, api.delete("/tasks/$taskId", again.accessToken).status)
        assertEquals(0, api.get("/lists/$listId/tasks", user.accessToken).json().size())
        assertEquals(404, api.get("/lists/$listId", registerConfirmedAccount("stranger").accessToken).status)
    }

    @Test
    fun `offline changes pushed by one device reach another device over sync and websocket`() {
        val user = registerConfirmedAccount("sync")
        val laptop = signIn(user.email, user.password, "laptop")
        val listId = UUID.randomUUID().toString()
        val taskId = UUID.randomUUID().toString()
        val phoneClock = "100:00000:phone"
        fun field(value: Any?) = mapOf("value" to value, "hlc" to phoneClock)

        val received = LinkedBlockingQueue<String>()
        val wsUrl = DeployedStack.baseUrl.replaceFirst("http", "ws") + "/api/v1/ws?token=${laptop.accessToken}"
        val socket = DeployedStack.http
            .newWebSocketBuilder()
            .buildAsync(URI.create(wsUrl), Collector(received))
            .join()
        try {
            Thread.sleep(WS_SETTLE_MILLIS)

            val push = api.post(
                "/sync/push",
                user.accessToken,
                mapOf(
                    "deviceId" to "phone",
                    "changes" to listOf(
                        mapOf("entityType" to "list", "entityId" to listId, "fields" to mapOf("name" to field("Synced"))),
                        mapOf(
                            "entityType" to "task",
                            "entityId" to taskId,
                            "fields" to mapOf("listId" to field(listId), "title" to field("Written offline")),
                        ),
                    ),
                ),
            )
            assertEquals(200, push.status)
            assertEquals(2, push.json()["applied"].asInt())

            assertNotNull(received.poll(WS_WAIT_SECONDS, TimeUnit.SECONDS), "The other device got no WebSocket notification")
        } finally {
            socket.sendClose(WebSocket.NORMAL_CLOSURE, "done")
        }

        val pull = api.get("/sync/pull?since=0", laptop.accessToken).json()
        val task = requireNotNull(pull["changes"]?.lastOrNull { it["entityId"].asText() == taskId }) {
            "Pull has no change for task $taskId: $pull"
        }
        assertEquals("Written offline", task["payload"]["title"].asText())
        assertFalse(pull["hasMore"].asBoolean())
    }

    @Test
    fun `backend accepts the deployed web client origin and rejects foreign origins`() {
        fun preflight(origin: String) = api.send(
            "OPTIONS",
            "/lists",
            headers = mapOf(
                "Origin" to origin,
                "Access-Control-Request-Method" to "POST",
                "Access-Control-Request-Headers" to "authorization,content-type",
            ),
        )

        val own = preflight(DeployedStack.webUrl)
        assertEquals(200, own.status)
        assertEquals(DeployedStack.webUrl, own.header("Access-Control-Allow-Origin"))
        assertEquals(403, preflight("https://evil.example").status)
    }

    @Test
    fun `nginx serves the web client build with wasm assets and SPA routes`() {
        fun get(path: String) = DeployedStack.http.send(
            HttpRequest.newBuilder(URI.create(DeployedStack.webUrl + path)).GET().build(),
            HttpResponse.BodyHandlers.ofString(),
        )

        val index = get("/")
        assertEquals(200, index.statusCode())
        assertTrue(index.body().contains("flutter_bootstrap.js"))
        // go_router deep link from the confirmation email must resolve to the app, not a 404.
        assertEquals(200, get("/verify-email?token=abc").statusCode())
        val wasm = get("/sqlite3.wasm")
        assertEquals(200, wasm.statusCode())
        assertEquals("application/wasm", wasm.headers().firstValue("Content-Type").orElse(""))
    }

    private class Collector(private val sink: LinkedBlockingQueue<String>) : WebSocket.Listener {
        override fun onOpen(webSocket: WebSocket) {
            webSocket.request(1)
        }

        override fun onText(webSocket: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
            sink.add(data.toString())
            webSocket.request(1)
            return null
        }
    }

    private companion object {
        const val WS_SETTLE_MILLIS = 500L
        const val WS_WAIT_SECONDS = 10L
    }
}
