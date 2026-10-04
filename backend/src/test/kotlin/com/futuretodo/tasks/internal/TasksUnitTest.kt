package com.futuretodo.tasks.internal

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.time.LocalDate
import java.time.OffsetDateTime
import java.util.UUID

class RecurrenceCalculatorTest {
    @Test
    fun `daily adds the interval`() {
        assertEquals(LocalDate.of(2026, 10, 5), RecurrenceCalculator.next(LocalDate.of(2026, 10, 4), "DAILY", 1, null))
        assertEquals(LocalDate.of(2026, 10, 7), RecurrenceCalculator.next(LocalDate.of(2026, 10, 4), "DAILY", 3, null))
    }

    @Test
    fun `weekdays skips the weekend`() {
        // 2026-10-02 is a Friday
        assertEquals(LocalDate.of(2026, 10, 5), RecurrenceCalculator.next(LocalDate.of(2026, 10, 2), "WEEKDAYS", 1, null))
        assertEquals(LocalDate.of(2026, 10, 6), RecurrenceCalculator.next(LocalDate.of(2026, 10, 5), "WEEKDAYS", 1, null))
    }

    @Test
    fun `weekly with selected days picks the next selected day`() {
        // 2026-10-05 is a Monday
        val monday = LocalDate.of(2026, 10, 5)
        assertEquals(LocalDate.of(2026, 10, 7), RecurrenceCalculator.next(monday, "WEEKLY", 1, "MON,WED"))
        assertEquals(LocalDate.of(2026, 10, 12), RecurrenceCalculator.next(LocalDate.of(2026, 10, 7), "WEEKLY", 1, "MON,WED"))
    }

    @Test
    fun `weekly with interval two skips a week`() {
        val wednesday = LocalDate.of(2026, 10, 7)
        assertEquals(LocalDate.of(2026, 10, 19), RecurrenceCalculator.next(wednesday, "WEEKLY", 2, "MON,WED"))
    }

    @Test
    fun `weekly without days adds whole weeks`() {
        assertEquals(LocalDate.of(2026, 10, 11), RecurrenceCalculator.next(LocalDate.of(2026, 10, 4), "WEEKLY", 1, null))
    }

    @Test
    fun `monthly clamps to the end of a short month and yearly adds years`() {
        assertEquals(LocalDate.of(2026, 2, 28), RecurrenceCalculator.next(LocalDate.of(2026, 1, 31), "MONTHLY", 1, null))
        assertEquals(LocalDate.of(2027, 10, 4), RecurrenceCalculator.next(LocalDate.of(2026, 10, 4), "YEARLY", 1, null))
    }

    @Test
    fun `unknown type gives no next date and invalid interval counts as one`() {
        assertNull(RecurrenceCalculator.next(LocalDate.of(2026, 10, 4), "SOMETIMES", 1, null))
        assertEquals(LocalDate.of(2026, 10, 5), RecurrenceCalculator.next(LocalDate.of(2026, 10, 4), "DAILY", 0, null))
    }
}

class EntitySpecsTest {
    @Test
    fun `finds specs by type`() {
        assertEquals(EntitySpecs.TASK, EntitySpecs.byType("task"))
        assertNull(EntitySpecs.byType("unknown"))
    }

    @Test
    fun `converts values to column types`() {
        val fields = EntitySpecs.TASK.fields
        val id = UUID.randomUUID()

        assertEquals("Buy milk", EntitySpecs.convert(fields.getValue("title"), "Buy milk"))
        assertEquals("", EntitySpecs.convert(fields.getValue("note"), null))
        assertEquals(true, EntitySpecs.convert(fields.getValue("completed"), true))
        assertEquals(LocalDate.of(2026, 10, 4), EntitySpecs.convert(fields.getValue("dueDate"), "2026-10-04"))
        assertNull(EntitySpecs.convert(fields.getValue("dueDate"), null))
        val reminder = EntitySpecs.convert(fields.getValue("reminderAt"), "2026-10-04T10:00:00Z")
        assertEquals(OffsetDateTime.parse("2026-10-04T10:00:00Z"), reminder)
        assertEquals(id, EntitySpecs.convert(fields.getValue("assigneeId"), id.toString()))
        assertEquals(2, EntitySpecs.convert(fields.getValue("repeatInterval"), 2))
        assertEquals(1, EntitySpecs.convert(fields.getValue("repeatInterval"), null))
        assertEquals(1.5, EntitySpecs.convert(fields.getValue("position"), 1.5))
    }

    @Test
    fun `rejects values that do not fit`() {
        val fields = EntitySpecs.TASK.fields

        assertThrows<IllegalArgumentException> { EntitySpecs.convert(fields.getValue("title"), "x".repeat(256)) }
        assertThrows<IllegalArgumentException> { EntitySpecs.convert(fields.getValue("completed"), "yes") }
        assertThrows<IllegalArgumentException> { EntitySpecs.convert(fields.getValue("position"), "far") }
        assertThrows<IllegalArgumentException> { EntitySpecs.convert(fields.getValue("repeatInterval"), "two") }
        assertThrows<RuntimeException> { EntitySpecs.convert(fields.getValue("dueDate"), "not-a-date") }
    }
}

class SearchAndSmartListTest {
    @Test
    fun `search query turns every word into a prefix term`() {
        assertEquals("buy:* & milk:*", SearchQuery.toTsQuery("  buy   milk "))
        assertEquals("a:* & b:*", SearchQuery.toTsQuery("a' | b!"))
        assertNull(SearchQuery.toTsQuery("   !!! "))
    }

    @Test
    fun `planned buckets follow the client date`() {
        val today = LocalDate.of(2026, 10, 7) // Wednesday, week ends Sunday 2026-10-11

        assertEquals("overdue", SmartLists.bucketOf(LocalDate.of(2026, 10, 6), today))
        assertEquals("today", SmartLists.bucketOf(today, today))
        assertEquals("tomorrow", SmartLists.bucketOf(LocalDate.of(2026, 10, 8), today))
        assertEquals("thisWeek", SmartLists.bucketOf(LocalDate.of(2026, 10, 11), today))
        assertEquals("later", SmartLists.bucketOf(LocalDate.of(2026, 10, 12), today))
    }

    @Test
    fun `group returns all five buckets in order`() {
        val groups = SmartLists.group(emptyList(), LocalDate.of(2026, 10, 7))

        assertEquals(listOf("overdue", "today", "tomorrow", "thisWeek", "later"), groups.keys.toList())
    }
}
