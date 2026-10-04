package com.futuretodo.shared

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LwwTest {
    @Test
    fun `newer clock wins per field and older is dropped`() {
        val existing = mapOf("title" to "001:00000:a", "note" to "005:00000:a")
        val incoming = mapOf(
            "title" to FieldChange("new title", "002:00000:b"),
            "note" to FieldChange("old note", "003:00000:b"),
            "important" to FieldChange(true, "001:00000:b"),
        )

        val accepted = Lww.accepted(existing, incoming)

        assertEquals(setOf("title", "important"), accepted.keys)
    }

    @Test
    fun `equal clock is not applied twice`() {
        val accepted = Lww.accepted(mapOf("title" to "001:00000:a"), mapOf("title" to FieldChange("x", "001:00000:a")))

        assertTrue(accepted.isEmpty())
    }
}

class HlcClockTest {
    @Test
    fun `clock values increase even when the wall clock stands still`() {
        val clock = HlcClock { 1_000L }

        val first = clock.next()
        val second = clock.next()

        assertTrue(second > first)
        assertEquals("000000000001000:00000:server", first)
        assertEquals("000000000001000:00001:server", second)
    }

    @Test
    fun `clock does not go back when the wall clock does`() {
        val times = ArrayDeque(listOf(2_000L, 1_000L))
        val clock = HlcClock { times.removeFirst() }

        val first = clock.next("dev")
        val second = clock.next("dev")

        assertTrue(second > first)
    }
}
