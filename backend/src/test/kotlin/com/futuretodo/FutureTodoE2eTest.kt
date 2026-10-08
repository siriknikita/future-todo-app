package com.futuretodo

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.net.http.WebSocket
import java.util.UUID
import java.util.concurrent.CompletionStage
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * End-to-end (API acceptance) tests: real HTTP against the running application and a real PostgreSQL.
 * The same tests must keep passing in Stage 2 when they are pointed at the API gateway.
 */
class FutureTodoE2eTest : IntegrationTestBase() {
    private fun createList(user: TestUser, name: String = "Home"): String {
        val response = api.post("/lists", user.accessToken, mapOf("name" to name, "icon" to "🏠"))
        assertEquals(201, response.status)
        return response.json()["id"].asText()
    }

    private fun createTask(user: TestUser, listId: String, title: String, extra: Map<String, Any?> = emptyMap()): String {
        val response = api.post("/lists/$listId/tasks", user.accessToken, mapOf("title" to title) + extra)
        assertEquals(201, response.status)
        return response.json()["id"].asText()
    }

    @Test
    fun `registration requires email confirmation before login`() {
        val email = "e2e-${UUID.randomUUID()}@test.com"

        assertEquals(201, api.post("/auth/register", body = mapOf("email" to email, "password" to "secret-password")).status)
        assertEquals(409, api.post("/auth/register", body = mapOf("email" to email, "password" to "secret-password")).status)
        val early = api.post("/auth/login", body = mapOf("email" to email, "password" to "secret-password"))
        assertEquals(403, early.status)
        assertEquals("EMAIL_NOT_VERIFIED", early.json()["code"].asText())

        val token = jdbc.queryForObject(
            "SELECT t.token FROM accounts.email_tokens t JOIN accounts.users u ON u.id = t.user_id WHERE u.email = ?",
            String::class.java,
            email,
        )
        assertEquals(204, api.post("/auth/verify-email", body = mapOf("token" to token)).status)
        assertEquals(400, api.post("/auth/verify-email", body = mapOf("token" to token)).status)

        val login = api.post("/auth/login", body = mapOf("email" to email, "password" to "secret-password", "deviceName" to "Chrome"))
        assertEquals(200, login.status)
        assertEquals(900, login.json()["expiresIn"].asInt())
        assertEquals(401, api.post("/auth/login", body = mapOf("email" to email, "password" to "wrong-password")).status)
    }

    @Test
    fun `api rejects anonymous calls and bad tokens`() {
        assertEquals(401, api.get("/lists").status)
        assertEquals(401, api.get("/me", "garbage").status)
        assertEquals(403, api.get("/admin/users", newUser().accessToken).status)
    }

    @Test
    fun `refresh tokens are rotated and old ones stop working`() {
        val user = newUser()

        val refreshed = api.post("/auth/refresh", body = mapOf("refreshToken" to user.refreshToken))
        assertEquals(200, refreshed.status)
        val newRefresh = refreshed.json()["refreshToken"].asText()
        assertNotEquals(user.refreshToken, newRefresh)

        assertEquals(401, api.post("/auth/refresh", body = mapOf("refreshToken" to user.refreshToken)).status)
        assertEquals(200, api.post("/auth/refresh", body = mapOf("refreshToken" to newRefresh)).status)
    }

    @Test
    fun `password reset by email token ends all sessions`() {
        val user = newUser()
        assertEquals(202, api.post("/auth/forgot-password", body = mapOf("email" to user.email)).status)
        val token = jdbc.queryForObject(
            "SELECT t.token FROM accounts.email_tokens t JOIN accounts.users u ON u.id = t.user_id " +
                "WHERE u.email = ? AND t.kind = 'RESET'",
            String::class.java,
            user.email,
        )

        assertEquals(204, api.post("/auth/reset-password", body = mapOf("token" to token, "newPassword" to "brand-new-password")).status)

        assertEquals(401, api.post("/auth/refresh", body = mapOf("refreshToken" to user.refreshToken)).status)
        assertEquals(200, api.post("/auth/login", body = mapOf("email" to user.email, "password" to "brand-new-password")).status)
    }

    @Test
    fun `profile can be changed and sessions listed and ended`() {
        val user = newUser()

        val updated = api.patch("/me", user.accessToken, mapOf("displayName" to "New Name", "photoUrl" to "https://img/x.png"))
        assertEquals("New Name", updated.json()["displayName"].asText())
        val good = mapOf("currentPassword" to user.password, "newPassword" to "another-password")
        assertEquals(204, api.post("/me/password", user.accessToken, good).status)
        val bad = mapOf("currentPassword" to "nope", "newPassword" to "another-password")
        assertEquals(400, api.post("/me/password", user.accessToken, bad).status)
        assertEquals(200, api.send("PUT", "/me/settings", user.accessToken, mapOf("theme" to "dark", "language" to "uk")).status)
        assertEquals("dark", api.get("/me/settings", user.accessToken).json()["theme"].asText())

        val sessions = api.get("/me/sessions", user.accessToken).json()
        assertEquals(1, sessions.size())
        assertTrue(sessions[0]["current"].asBoolean())
        assertEquals(204, api.delete("/me/sessions", user.accessToken).status)
        assertEquals(0, api.get("/me/sessions", user.accessToken).json().size())
    }

    @Test
    fun `user creates lists groups tasks and steps and uses smart lists and search`() {
        val user = newUser()
        val listId = createList(user, "Groceries")
        val taskId = createTask(user, listId, "Buy oat milk", mapOf("dueDate" to "2026-10-04", "note" to "the barista kind"))

        val patched = api.patch("/tasks/$taskId", user.accessToken, mapOf("important" to true, "myDayDate" to "2026-10-04"))
        assertTrue(patched.json()["important"].asBoolean())
        val step = api.post("/tasks/$taskId/steps", user.accessToken, mapOf("title" to "Go to the shop"))
        assertEquals(201, step.status)
        assertEquals(200, api.patch("/steps/${step.json()["id"].asText()}", user.accessToken, mapOf("completed" to true)).status)

        val tasks = api.get("/lists/$listId/tasks?sort=alphabetical", user.accessToken).json()
        assertEquals(1, tasks.size())
        assertEquals("Go to the shop", tasks[0]["steps"][0]["title"].asText())
        assertEquals(taskId, api.get("/smart-lists/important", user.accessToken).json()["tasks"][0]["id"].asText())
        assertEquals(taskId, api.get("/smart-lists/my-day?today=2026-10-04", user.accessToken).json()["tasks"][0]["id"].asText())
        assertEquals(0, api.get("/smart-lists/my-day?today=2026-10-05", user.accessToken).json()["tasks"].size())
        val planned = api.get("/smart-lists/planned?today=2026-10-04", user.accessToken).json()
        assertEquals(taskId, planned["groups"]["today"][0]["id"].asText())
        assertEquals(0, planned["groups"]["overdue"].size())
        assertEquals(1, api.get("/smart-lists/planned?today=2026-10-06", user.accessToken).json()["groups"]["overdue"].size())
        assertEquals(taskId, api.get("/search?q=oat%20mil", user.accessToken).json()[0]["id"].asText())
        assertEquals(taskId, api.get("/search?q=barista", user.accessToken).json()[0]["id"].asText())
        assertEquals(0, api.get("/search?q=zzzzqq", user.accessToken).json().size())

        // complete, hide completed, then undo a delete
        assertEquals(200, api.patch("/tasks/$taskId", user.accessToken, mapOf("completed" to true)).status)
        assertEquals(0, api.get("/lists/$listId/tasks?showCompleted=false", user.accessToken).json().size())
        assertEquals(taskId, api.get("/smart-lists/completed", user.accessToken).json()["tasks"][0]["id"].asText())
        assertEquals(204, api.delete("/tasks/$taskId", user.accessToken).status)
        assertEquals(404, api.get("/tasks/$taskId", user.accessToken).status)
        assertEquals(200, api.patch("/tasks/$taskId", user.accessToken, mapOf("deleted" to false)).status)
        assertEquals(200, api.get("/tasks/$taskId", user.accessToken).status)
    }

    @Test
    fun `lists can be grouped reordered renamed and deleted`() {
        val user = newUser()
        val group = api.post("/list-groups", user.accessToken, mapOf("name" to "Work"))
        assertEquals(201, group.status)
        val groupId = group.json()["id"].asText()
        val listId = createList(user, "Projects")
        val other = createList(user, "Misc")

        val moved = api.patch("/lists/$listId", user.accessToken, mapOf("groupId" to groupId, "name" to "Projects 2", "position" to 5.0))
        assertEquals(groupId, moved.json()["groupId"].asText())
        assertEquals(200, api.patch("/lists/$other", user.accessToken, mapOf("position" to 1.0)).status)
        assertEquals(other, api.get("/lists", user.accessToken).json()[0]["id"].asText())

        assertEquals(204, api.delete("/list-groups/$groupId", user.accessToken).status)
        assertTrue(api.get("/lists/$listId", user.accessToken).json()["groupId"].isNull)
        assertEquals(204, api.delete("/lists/$listId", user.accessToken).status)
        assertEquals(404, api.get("/lists/$listId", user.accessToken).status)
        assertEquals(400, api.post("/lists", user.accessToken, mapOf("icon" to "x")).status)
    }

    @Test
    fun `sharing flow invite join members assign notify and leave`() {
        val owner = newUser("owner")
        val guest = newUser("guest")
        val listId = createList(owner, "Trip")
        val taskId = createTask(owner, listId, "Book hotel")

        assertEquals(404, api.get("/lists/$listId", guest.accessToken).status)
        assertEquals(404, api.post("/lists/$listId/invitations", guest.accessToken).status)
        val invitation = api.post("/lists/$listId/invitations", owner.accessToken).json()["token"].asText()
        assertEquals(200, api.post("/invitations/$invitation/accept", guest.accessToken).status)

        assertEquals(2, api.get("/lists/$listId/members", guest.accessToken).json().size())
        assertEquals(listId, api.get("/lists", guest.accessToken).json()[0]["id"].asText())
        assertEquals(200, api.get("/tasks/$taskId", guest.accessToken).status)

        // the owner assigns the task to the guest: it shows up in "assigned to me" and the guest gets a notification
        assertEquals(200, api.patch("/tasks/$taskId", owner.accessToken, mapOf("assigneeId" to guest.id.toString())).status)
        val assigned = api.get("/smart-lists/assigned-to-me", guest.accessToken).json()["tasks"]
        assertEquals(taskId, assigned[0]["id"].asText())
        val notifications = api.get("/notifications", guest.accessToken).json()
        assertEquals("TASK_ASSIGNED", notifications[0]["type"].asText())
        assertEquals(204, api.post("/notifications/${notifications[0]["id"].asText()}/read", guest.accessToken).status)
        assertEquals(0, api.get("/notifications?unreadOnly=true", guest.accessToken).json().size())
        assertEquals(400, api.patch("/tasks/$taskId", owner.accessToken, mapOf("assigneeId" to UUID.randomUUID().toString())).status)

        // members cannot change list properties or remove others
        assertEquals(403, api.patch("/lists/$listId", guest.accessToken, mapOf("name" to "Hijacked")).status)
        assertEquals(400, api.delete("/lists/$listId/members/${owner.id}", guest.accessToken).status)

        // revoked link no longer works for new people, the guest can leave
        val third = newUser("third")
        assertEquals(204, api.delete("/lists/$listId/invitations", owner.accessToken).status)
        assertEquals(404, api.post("/invitations/$invitation/accept", third.accessToken).status)
        assertEquals(204, api.delete("/lists/$listId/members/${guest.id}", guest.accessToken).status)
        assertEquals(404, api.get("/lists/$listId", guest.accessToken).status)
    }

    @Test
    fun `offline sync over http push pull and websocket notification within five seconds`() {
        val owner = newUser("syncowner")
        val guest = newUser("syncguest")
        val listId = UUID.randomUUID().toString()
        val taskId = UUID.randomUUID().toString()
        fun field(value: Any?, hlc: String) = mapOf("value" to value, "hlc" to hlc)

        val push = api.post(
            "/sync/push",
            owner.accessToken,
            mapOf(
                "deviceId" to "web-1",
                "changes" to listOf(
                    mapOf("entityType" to "list", "entityId" to listId, "fields" to mapOf("name" to field("Offline", "100:00000:web-1"))),
                    mapOf(
                        "entityType" to "task",
                        "entityId" to taskId,
                        "fields" to mapOf(
                            "listId" to field(listId, "100:00000:web-1"),
                            "title" to field("Made offline", "100:00000:web-1"),
                        ),
                    ),
                ),
            ),
        )
        assertEquals(200, push.status)
        assertEquals(2, push.json()["applied"].asInt())
        val invitation = api.post("/lists/$listId/invitations", owner.accessToken).json()["token"].asText()

        val received = LinkedBlockingQueue<String>()
        val socket = HttpClient
            .newHttpClient()
            .newWebSocketBuilder()
            .buildAsync(
                URI.create("ws://localhost:$port/api/v1/ws?token=${guest.accessToken}"),
                object : WebSocket.Listener {
                    override fun onOpen(webSocket: WebSocket) {
                        webSocket.request(1)
                    }

                    override fun onText(webSocket: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                        received.add(data.toString())
                        webSocket.request(1)
                        return null
                    }
                },
            ).join()
        Thread.sleep(500)

        api.post("/invitations/$invitation/accept", guest.accessToken)
        api.post(
            "/sync/push",
            owner.accessToken,
            mapOf(
                "changes" to listOf(
                    mapOf("entityType" to "task", "entityId" to taskId, "fields" to mapOf("important" to field(true, "200:00000:web-1"))),
                ),
            ),
        )

        val message = received.poll(5, TimeUnit.SECONDS)
        assertNotNull(message)
        assertTrue(message!!.contains("\"changes\""))
        socket.sendClose(WebSocket.NORMAL_CLOSURE, "done")

        val pull = api.get("/sync/pull?since=0", guest.accessToken).json()
        val taskChanges = pull["changes"].filter { it["entityId"].asText() == taskId }
        assertTrue(taskChanges.isNotEmpty())
        assertTrue(taskChanges.last()["payload"]["important"].asBoolean())
        assertEquals("Made offline", taskChanges.last()["payload"]["title"].asText())
        assertFalse(pull["hasMore"].asBoolean())
    }

    @Test
    fun `websocket rejects connections without a valid token`() {
        val failed = try {
            HttpClient
                .newHttpClient()
                .newWebSocketBuilder()
                .buildAsync(URI.create("ws://localhost:$port/api/v1/ws?token=bad"), object : WebSocket.Listener {})
                .join()
            false
        } catch (e: Exception) {
            true
        }

        assertTrue(failed)
    }

    @Test
    fun `admin can list block and unblock users and sees statistics`() {
        val victim = newUser("victim")
        // promote a freshly registered user to admin directly in the database (there is no API for it)
        val admin = newUser("admin")
        jdbc.update("UPDATE accounts.users SET role = 'ADMIN' WHERE id = ?", admin.id)
        val adminLogin = api.post("/auth/login", body = mapOf("email" to admin.email, "password" to admin.password))
        val token = adminLogin.json()["accessToken"].asText()

        val users = api.get("/admin/users?query=victim", token).json()
        assertTrue(users["total"].asInt() >= 1)
        assertEquals(204, api.post("/admin/users/${victim.id}/block", token).status)
        assertEquals(403, api.post("/auth/login", body = mapOf("email" to victim.email, "password" to victim.password)).status)
        assertEquals(204, api.post("/admin/users/${victim.id}/unblock", token).status)
        assertEquals(200, api.post("/auth/login", body = mapOf("email" to victim.email, "password" to victim.password)).status)

        val stats = api.get("/admin/stats", token).json()
        assertTrue(stats["totalUsers"].asInt() >= 2)
        assertTrue(stats["platforms"].has("web"))
    }

    @Test
    fun `account export contains data and deletion removes everything`() {
        val user = newUser("leaver")
        val listId = createList(user, "To export")
        createTask(user, listId, "Exported task")

        val export = api.get("/me/export", user.accessToken).json()
        assertEquals(user.email, export["profile"]["email"].asText())
        assertEquals("Exported task", export["tasks"]["tasks"][0]["title"].asText())

        assertEquals(204, api.delete("/me", user.accessToken).status)

        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM tasks.lists WHERE owner_id = ?", Int::class.java, user.id))
        assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM sharing.list_members WHERE user_id = ?", Int::class.java, user.id))
        assertEquals(401, api.post("/auth/refresh", body = mapOf("refreshToken" to user.refreshToken)).status)
        assertEquals(401, api.post("/auth/login", body = mapOf("email" to user.email, "password" to user.password)).status)
    }

    @Test
    fun `openapi documentation and health are public`() {
        val client = HttpClient.newHttpClient()
        val docs = client.send(
            HttpRequest.newBuilder(URI.create("http://localhost:$port/v3/api-docs")).GET().build(),
            HttpResponse.BodyHandlers.ofString(),
        )
        val health = client.send(
            HttpRequest.newBuilder(URI.create("http://localhost:$port/actuator/health")).GET().build(),
            HttpResponse.BodyHandlers.ofString(),
        )

        assertEquals(200, docs.statusCode())
        assertTrue(docs.body().contains("/api/v1/sync/push"))
        assertEquals(200, health.statusCode())
    }
}
