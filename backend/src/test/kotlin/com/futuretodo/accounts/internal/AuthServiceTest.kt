package com.futuretodo.accounts.internal

import com.futuretodo.shared.ApiException
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.http.HttpStatus
import org.springframework.security.crypto.password.PasswordEncoder
import java.time.OffsetDateTime
import java.util.UUID

class AuthServiceTest {
    private val users = mockk<UserRepository>(relaxed = true)
    private val emailTokens = mockk<EmailTokenRepository>(relaxed = true)
    private val sessions = mockk<SessionService>(relaxed = true)
    private val encoder = mockk<PasswordEncoder>()
    private val mail = mockk<MailService>(relaxed = true)
    private val limiter = mockk<LoginRateLimiter>(relaxed = true)
    private val oidc = mockk<OidcVerifier>()
    private val service = AuthService(users, emailTokens, sessions, encoder, mail, limiter, oidc)

    private fun user(verified: Boolean = true, blocked: Boolean = false) = UserRecord(
        UUID.randomUUID(), "a@b.com", "hash", "Alice", null, verified, "USER", blocked, "{}", OffsetDateTime.now(), null,
    )

    @Test
    fun `register stores user and sends verification email`() {
        every { users.findByEmail("new@user.com") } returns null
        every { encoder.encode("password1") } returns "encoded"
        val saved = slot<UserRecord>()
        every { users.insert(capture(saved), any(), any()) } returns Unit

        val profile = service.register(RegisterRequest(" New@User.com ", "password1", null), "127.0.0.1")

        assertEquals("new@user.com", profile.email)
        assertEquals("new", profile.displayName)
        assertEquals(false, saved.captured.emailVerified)
        assertEquals("encoded", saved.captured.passwordHash)
        verify { mail.sendVerification("new@user.com", any()) }
    }

    @Test
    fun `register rejects duplicate email`() {
        every { users.findByEmail("a@b.com") } returns user()

        val e = assertThrows<ApiException> { service.register(RegisterRequest("a@b.com", "password1"), "ip") }

        assertEquals(HttpStatus.CONFLICT, e.status)
    }

    @Test
    fun `register rejects short password and bad email`() {
        val weak = assertThrows<ApiException> { service.register(RegisterRequest("a@b.com", "short"), "ip") }
        assertEquals("WEAK_PASSWORD", weak.code)
        val bad = assertThrows<ApiException> { service.register(RegisterRequest("not-an-email", "password1"), "ip") }
        assertEquals("INVALID_EMAIL", bad.code)
    }

    @Test
    fun `login fails with wrong password`() {
        every { users.findByEmail("a@b.com") } returns user()
        every { encoder.matches("bad", "hash") } returns false

        val e = assertThrows<ApiException> { service.login(LoginRequest("a@b.com", "bad"), "ip") }

        assertEquals(HttpStatus.UNAUTHORIZED, e.status)
    }

    @Test
    fun `login requires verified email and unblocked account`() {
        every { encoder.matches("pw", "hash") } returns true
        every { users.findByEmail("a@b.com") } returns user(verified = false)
        assertEquals("EMAIL_NOT_VERIFIED", assertThrows<ApiException> { service.login(LoginRequest("a@b.com", "pw"), "ip") }.code)

        every { users.findByEmail("a@b.com") } returns user(blocked = true)
        assertEquals("ACCOUNT_BLOCKED", assertThrows<ApiException> { service.login(LoginRequest("a@b.com", "pw"), "ip") }.code)
    }

    @Test
    fun `login opens a session for valid credentials`() {
        val record = user()
        val pair = mockk<TokenPair>()
        every { users.findByEmail("a@b.com") } returns record
        every { encoder.matches("pw", "hash") } returns true
        every { sessions.open(record, "phone", "android") } returns pair

        val result = service.login(LoginRequest("A@b.com", "pw", "phone", "android"), "ip")

        assertNotNull(result)
        verify { sessions.open(record, "phone", "android") }
    }

    @Test
    fun `verify email rejects unknown or used token`() {
        every { emailTokens.find("nope", "VERIFY") } returns null
        assertThrows<ApiException> { service.verifyEmail("nope") }

        val used = EmailTokenRecord("t", UUID.randomUUID(), "VERIFY", OffsetDateTime.now().plusDays(1), true)
        every { emailTokens.find("t", "VERIFY") } returns used
        assertThrows<ApiException> { service.verifyEmail("t") }
    }

    @Test
    fun `verify email marks user verified`() {
        val record = EmailTokenRecord("t", UUID.randomUUID(), "VERIFY", OffsetDateTime.now().plusDays(1), false)
        every { emailTokens.find("t", "VERIFY") } returns record

        service.verifyEmail("t")

        verify { users.markVerified(record.userId) }
        verify { emailTokens.markUsed("t") }
    }

    @Test
    fun `forgot password sends mail only when user exists`() {
        every { users.findByEmail("none@x.com") } returns null
        service.forgotPassword("none@x.com", "ip")
        verify(exactly = 0) { mail.sendPasswordReset(any(), any()) }

        every { users.findByEmail("a@b.com") } returns user()
        service.forgotPassword("a@b.com", "ip")
        verify { mail.sendPasswordReset("a@b.com", any()) }
    }

    @Test
    fun `reset password changes password and ends sessions`() {
        val record = EmailTokenRecord("r", UUID.randomUUID(), "RESET", OffsetDateTime.now().plusHours(1), false)
        every { emailTokens.find("r", "RESET") } returns record
        every { encoder.encode("newpassword") } returns "newhash"

        service.resetPassword("r", "newpassword")

        verify { users.updatePassword(record.userId, "newhash") }
        verify { sessions.endAll(record.userId) }
    }
}
