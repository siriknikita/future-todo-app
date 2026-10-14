package com.futuretodo.accounts.internal

import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.springframework.boot.ApplicationArguments
import org.springframework.security.crypto.password.PasswordEncoder

class AdminBootstrapTest {
    private val users = mockk<UserRepository>(relaxed = true)
    private val encoder = mockk<PasswordEncoder>()
    private val args = mockk<ApplicationArguments>()

    @Test
    fun `creates the configured administrator`() {
        every { users.findByEmail("admin@futuretodo.test") } returns null
        every { encoder.encode("admin-password") } returns "encoded"
        val saved = slot<UserRecord>()
        every { users.insert(capture(saved), any(), any()) } returns Unit

        AdminBootstrap(users, encoder, "Admin@FutureTodo.test", "admin-password").run(args)

        val admin = saved.captured
        assertEquals("admin@futuretodo.test", admin.email)
        assertEquals("encoded", admin.passwordHash)
        assertEquals("Administrator", admin.displayName)
        assertNull(admin.photoUrl)
        assertTrue(admin.emailVerified)
        assertEquals("ADMIN", admin.role)
        assertFalse(admin.blocked)
        assertEquals("{}", admin.settings)
        assertNull(admin.lastSeenAt)
    }

    @Test
    fun `does nothing without configuration or when the administrator exists`() {
        AdminBootstrap(users, encoder, "", "admin-password").run(args)
        AdminBootstrap(users, encoder, "admin@futuretodo.test", "").run(args)
        every { users.findByEmail("admin@futuretodo.test") } returns mockk()
        AdminBootstrap(users, encoder, "admin@futuretodo.test", "admin-password").run(args)

        verify(exactly = 0) { users.insert(any(), any(), any()) }
    }
}
