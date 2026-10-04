package com.futuretodo.accounts.internal

import com.futuretodo.shared.ApiException
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.http.HttpStatus
import java.util.UUID

class JwtAndLimiterTest {
    private val secret = "unit-test-secret-unit-test-secret-1234"

    @Test
    fun `issued token is verified and carries user, role and session`() {
        val jwt = JwtService(secret, 15)
        val userId = UUID.randomUUID()
        val sessionId = UUID.randomUUID()

        val user = jwt.verify(jwt.issue(userId, "ADMIN", sessionId))

        assertEquals(userId, user?.id)
        assertEquals("ADMIN", user?.role)
        assertEquals(sessionId, user?.sessionId)
        assertEquals(900L, jwt.expiresInSeconds)
    }

    @Test
    fun `garbage and foreign tokens are rejected`() {
        val jwt = JwtService(secret, 15)
        val other = JwtService("another-secret-another-secret-another-1", 15)

        assertNull(jwt.verify("not-a-token"))
        assertNull(jwt.verify(other.issue(UUID.randomUUID(), "USER", UUID.randomUUID())))
    }

    @Test
    fun `expired token is rejected`() {
        val jwt = JwtService(secret, -1)

        assertNull(jwt.verify(jwt.issue(UUID.randomUUID(), "USER", UUID.randomUUID())))
    }

    @Test
    fun `limiter blocks after the configured number of attempts`() {
        val limiter = LoginRateLimiter(3)

        repeat(3) { limiter.check("k") }
        val e = assertThrows<ApiException> { limiter.check("k") }

        assertEquals(HttpStatus.TOO_MANY_REQUESTS, e.status)
        limiter.check("other-key")
    }

    @Test
    fun `refresh token hash is stable and not the token`() {
        assertEquals(SessionService.hash("abc"), SessionService.hash("abc"))
        assertEquals(64, SessionService.hash("abc").length)
    }
}
