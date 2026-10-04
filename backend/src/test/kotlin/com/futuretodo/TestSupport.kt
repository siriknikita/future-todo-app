package com.futuretodo

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.containers.PostgreSQLContainer
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.UUID

class KPostgres : PostgreSQLContainer<KPostgres>("postgres:16-alpine")

/** One PostgreSQL container shared by all integration and e2e tests of a test run. */
object SharedPostgres {
    val container: KPostgres by lazy { KPostgres().also { it.start() } }
}

class ApiResponse(val status: Int, val body: String, private val mapper: ObjectMapper) {
    fun json(): JsonNode = mapper.readTree(body)
}

class Api(private val baseUrl: String, private val mapper: ObjectMapper) {
    private val client = HttpClient.newHttpClient()

    fun send(method: String, path: String, token: String? = null, body: Any? = null): ApiResponse {
        val builder = HttpRequest.newBuilder(URI.create(baseUrl + path)).header("Content-Type", "application/json")
        if (token != null) {
            builder.header("Authorization", "Bearer $token")
        }
        val publisher = if (body == null) {
            HttpRequest.BodyPublishers.noBody()
        } else {
            HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body))
        }
        val response = client.send(builder.method(method, publisher).build(), HttpResponse.BodyHandlers.ofString())
        return ApiResponse(response.statusCode(), response.body(), mapper)
    }

    fun get(path: String, token: String? = null) = send("GET", path, token)

    fun post(path: String, token: String? = null, body: Any? = null) = send("POST", path, token, body)

    fun patch(path: String, token: String?, body: Any) = send("PATCH", path, token, body)

    fun delete(path: String, token: String? = null) = send("DELETE", path, token)
}

class TestUser(val email: String, val password: String, val accessToken: String, val refreshToken: String, val id: UUID)

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
abstract class IntegrationTestBase {
    @LocalServerPort
    protected var port: Int = 0

    @Autowired
    protected lateinit var jdbc: JdbcTemplate

    @Autowired
    protected lateinit var mapper: ObjectMapper

    protected val api: Api by lazy { Api("http://localhost:$port/api/v1", mapper) }

    /** Registers, confirms the email (token read from the database) and logs in a new user. */
    protected fun newUser(prefix: String = "user"): TestUser {
        val email = "$prefix-${UUID.randomUUID()}@test.com"
        val password = "secret-password"
        check(api.post("/auth/register", body = mapOf("email" to email, "password" to password, "displayName" to prefix)).status == 201)
        val token = jdbc.queryForObject(
            "SELECT t.token FROM accounts.email_tokens t JOIN accounts.users u ON u.id = t.user_id " +
                "WHERE u.email = ? AND t.kind = 'VERIFY'",
            String::class.java, email,
        )!!
        check(api.post("/auth/verify-email", body = mapOf("token" to token)).status == 204)
        val login = api.post("/auth/login", body = mapOf("email" to email, "password" to password, "platform" to "web"))
        check(login.status == 200)
        val json = login.json()
        return TestUser(
            email, password, json["accessToken"].asText(), json["refreshToken"].asText(),
            UUID.fromString(json["user"]["id"].asText()),
        )
    }

    companion object {
        @JvmStatic
        @DynamicPropertySource
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url") { SharedPostgres.container.jdbcUrl }
            registry.add("spring.datasource.username") { SharedPostgres.container.username }
            registry.add("spring.datasource.password") { SharedPostgres.container.password }
            registry.add("spring.mail.port") { "1" }
            registry.add("app.rate-limit.attempts-per-minute") { "1000" }
        }
    }
}
