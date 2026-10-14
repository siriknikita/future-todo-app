package com.futuretodo.accounts.internal

import com.futuretodo.shared.ApiException
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.http.HttpStatus
import java.time.OffsetDateTime
import java.util.UUID

class SessionServiceTest {
    private val sessions = mockk<SessionRepository>(relaxed = true)
    private val users = mockk<UserRepository>(relaxed = true)
    private val jwt = mockk<JwtService>(relaxed = true)
    private val service = SessionService(sessions, users, jwt, 30)

    private fun sessionOf(user: UserRecord): SessionRecord {
        val now = OffsetDateTime.now()
        return SessionRecord(UUID.randomUUID(), user.id, "phone", "android", now, now, now.plusDays(1))
    }

    @Test
    fun `refresh rotates the token of an active session`() {
        val user = UserRecord.newUser("a@b.com", "hash", "Alice", emailVerified = true)
        val session = sessionOf(user)
        every { sessions.findByTokenHash(SessionService.hash("refresh-token")) } returns session
        every { users.findById(user.id) } returns user

        val pair = service.refresh("refresh-token")

        assertEquals(session.id, pair.sessionId)
        verify { sessions.rotate(session.id, SessionService.hash(pair.refreshToken), any()) }
    }

    @Test
    fun `refresh rejects a blocked account and keeps the old token`() {
        val user = UserRecord.newUser("a@b.com", "hash", "Alice", emailVerified = true).copy(blocked = true)
        every { sessions.findByTokenHash(SessionService.hash("refresh-token")) } returns sessionOf(user)
        every { users.findById(user.id) } returns user

        val e = assertThrows<ApiException> { service.refresh("refresh-token") }

        assertEquals(HttpStatus.FORBIDDEN, e.status)
        assertEquals("ACCOUNT_BLOCKED", e.code)
        assertEquals("Account is blocked", e.message)
        verify(exactly = 0) { sessions.rotate(any(), any(), any()) }
    }
}
