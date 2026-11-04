package com.futuretodo.global

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.util.UUID

/**
 * Addresses of a deployed Future Todo environment. Nothing here starts the application:
 * the tests talk to whatever `deploy/docker-compose.yml` (or any other deployment) is running.
 * Override with `-PbaseUrl=... -PmailpitUrl=... -PwebUrl=...` on the Gradle command line.
 */
object DeployedStack {
    val baseUrl: String = System.getProperty("baseUrl", "http://localhost:8080").trimEnd('/')
    val mailpitUrl: String = System.getProperty("mailpitUrl", "http://localhost:8025").trimEnd('/')
    val webUrl: String = System.getProperty("webUrl", "http://localhost:8081").trimEnd('/')

    val mapper = jacksonObjectMapper()
    val http: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build()
    val api = Http("$baseUrl/api/v1")
}

class Reply(val status: Int, val body: String, val headers: Map<String, List<String>>) {
    fun json(): JsonNode = DeployedStack.mapper.readTree(body)

    fun header(name: String): String? = headers.entries
        .firstOrNull { it.key.equals(name, ignoreCase = true) }
        ?.value
        ?.firstOrNull()
}

class Http(private val root: String) {
    fun send(method: String, path: String, token: String? = null, body: Any? = null, headers: Map<String, String> = emptyMap()): Reply {
        val builder = HttpRequest.newBuilder(URI.create(root + path)).timeout(Duration.ofSeconds(15))
        if (body != null) builder.header("Content-Type", "application/json")
        if (token != null) builder.header("Authorization", "Bearer $token")
        headers.forEach { (k, v) -> builder.header(k, v) }
        val publisher = if (body == null) {
            HttpRequest.BodyPublishers.noBody()
        } else {
            HttpRequest.BodyPublishers.ofString(DeployedStack.mapper.writeValueAsString(body))
        }
        val response = DeployedStack.http.send(builder.method(method, publisher).build(), HttpResponse.BodyHandlers.ofString())
        return Reply(response.statusCode(), response.body(), response.headers().map())
    }

    fun get(path: String, token: String? = null) = send("GET", path, token)

    fun post(path: String, token: String? = null, body: Any? = null) = send("POST", path, token, body)

    fun patch(path: String, token: String?, body: Any) = send("PATCH", path, token, body)

    fun delete(path: String, token: String?) = send("DELETE", path, token)
}

/** Reads the mail the deployed backend sent over real SMTP from Mailpit's HTTP API. */
object Mailbox {
    private val mailpit = Http("${DeployedStack.mailpitUrl}/api/v1")

    /** Waits for the newest message sent to [email] and returns its plain-text body. */
    fun latestTextTo(email: String, timeout: Duration = Duration.ofSeconds(20)): String {
        val query = URLEncoder.encode("to:\"$email\"", Charsets.UTF_8)
        val deadline = System.nanoTime() + timeout.toNanos()
        while (System.nanoTime() < deadline) {
            val messages = mailpit.get("/search?query=$query").json()["messages"]
            if (messages != null && messages.size() > 0) {
                val id = messages[0]["ID"].asText()
                return mailpit.get("/message/$id").json()["Text"].asText()
            }
            Thread.sleep(POLL_MILLIS)
        }
        error("No email to $email arrived in Mailpit within $timeout")
    }

    /** Extracts the `token` query parameter from the first link in [text] that contains [path]. */
    fun tokenFromLink(text: String, path: String): String =
        Regex("""${Regex.escape(path)}\?token=([A-Za-z0-9_\-]+)""").find(text)?.groupValues?.get(1)
            ?: error("No $path link in email:\n$text")

    private const val POLL_MILLIS = 250L
}

class Account(val email: String, val password: String, val accessToken: String, val userId: String)

/** Registers through the API, confirms the address with the link from the real email, and signs in. */
fun registerConfirmedAccount(prefix: String = "global"): Account {
    val email = "$prefix-${UUID.randomUUID()}@global.test"
    val password = "global-secret-password"
    val api = DeployedStack.api
    val registered = api.post("/auth/register", body = mapOf("email" to email, "password" to password, "displayName" to prefix))
    check(registered.status == 201) { "Register failed: ${registered.status} ${registered.body}" }
    val token = Mailbox.tokenFromLink(Mailbox.latestTextTo(email), "/verify-email")
    val verified = api.post("/auth/verify-email", body = mapOf("token" to token))
    check(verified.status == 204) { "Email confirmation failed: ${verified.status} ${verified.body}" }
    return signIn(email, password)
}

fun signIn(email: String, password: String, device: String = "global-test"): Account {
    val login = DeployedStack.api.post("/auth/login", body = mapOf("email" to email, "password" to password, "deviceName" to device))
    check(login.status == 200) { "Login failed: ${login.status} ${login.body}" }
    val json = login.json()
    return Account(email, password, json["accessToken"].asText(), json["user"]["id"].asText())
}
