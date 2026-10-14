package com.futuretodo.accounts.internal

import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.read.ListAppender
import io.mockk.Runs
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.slot
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertDoesNotThrow
import org.slf4j.LoggerFactory
import org.springframework.mail.MailSendException
import org.springframework.mail.SimpleMailMessage
import org.springframework.mail.javamail.JavaMailSender

class MailServiceTest {
    private val sender = mockk<JavaMailSender>()
    private val service = MailService(sender, "no-reply@futuretodo.test", "http://app.test")
    private val logger = LoggerFactory.getLogger(MailService::class.java) as Logger
    private val logs = ListAppender<ILoggingEvent>()

    @BeforeEach
    fun captureLogs() {
        logs.start()
        logger.addAppender(logs)
    }

    @AfterEach
    fun releaseLogs() {
        logger.detachAppender(logs)
    }

    @Test
    fun `sends the verification link without writing the token to the log`() {
        val sent = slot<SimpleMailMessage>()
        every { sender.send(capture(sent)) } just Runs

        service.sendVerification("a@b.com", "secret-token")

        assertEquals("no-reply@futuretodo.test", sent.captured.from)
        assertEquals(listOf("a@b.com"), sent.captured.to?.toList())
        assertTrue(sent.captured.text!!.contains("http://app.test/verify-email?token=secret-token"))
        assertTrue(logs.list.isNotEmpty())
        assertFalse(logs.list.any { it.formattedMessage.contains("secret-token") })
    }

    @Test
    fun `a failing mail server does not break the caller and the cause is logged`() {
        every { sender.send(any<SimpleMailMessage>()) } throws MailSendException("connection refused")

        assertDoesNotThrow { service.sendPasswordReset("a@b.com", "secret-token") }

        val warning = logs.list.single { it.level.toString() == "WARN" }
        assertNotNull(warning.throwableProxy)
        assertFalse(logs.list.any { it.formattedMessage.contains("secret-token") })
    }
}
