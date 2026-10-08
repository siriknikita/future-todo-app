package com.futuretodo.tasks.internal

import com.fasterxml.jackson.annotation.JsonInclude
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.util.UUID

data class GroupDto(
    val id: UUID,
    val ownerId: UUID,
    val name: String,
    val position: Double,
    val deleted: Boolean,
    val createdAt: OffsetDateTime,
    val clocks: Map<String, String>,
)

data class ListDto(
    val id: UUID,
    val ownerId: UUID,
    val groupId: UUID?,
    val name: String,
    val icon: String?,
    val theme: String?,
    val position: Double,
    val deleted: Boolean,
    val createdAt: OffsetDateTime,
    val clocks: Map<String, String>,
)

data class StepDto(
    val id: UUID,
    val taskId: UUID,
    val title: String,
    val completed: Boolean,
    val position: Double,
    val deleted: Boolean,
    val createdAt: OffsetDateTime,
    val clocks: Map<String, String>,
)

data class TaskDto(
    val id: UUID,
    val listId: UUID,
    val title: String,
    val note: String,
    val completed: Boolean,
    val completedAt: OffsetDateTime?,
    val important: Boolean,
    val dueDate: LocalDate?,
    val reminderAt: OffsetDateTime?,
    val repeatType: String?,
    val repeatInterval: Int,
    val repeatDays: String?,
    val myDayDate: LocalDate?,
    val assigneeId: UUID?,
    val position: Double,
    val createdAt: OffsetDateTime,
    val deleted: Boolean,
    val clocks: Map<String, String>,
    @get:JsonInclude(JsonInclude.Include.NON_NULL) val steps: List<StepDto>? = null,
)

data class SmartListResponse(val type: String, val tasks: List<TaskDto>, val groups: Map<String, List<TaskDto>>? = null)

enum class Kind { TEXT, BOOL, DOUBLE, INT, REF, DATE, INSTANT }

data class FieldSpec(val column: String, val kind: Kind, val notNull: Boolean = false, val maxLength: Int? = null)

class EntitySpec(val type: String, val table: String, val fields: Map<String, FieldSpec>)

/** Whitelist of the synced fields of every entity: API field name to database column. */
object EntitySpecs {
    private val deleted = "deleted" to FieldSpec("deleted", Kind.BOOL, true)
    private val position = "position" to FieldSpec("position", Kind.DOUBLE, true)

    val GROUP = EntitySpec(
        "group",
        "tasks.list_groups",
        mapOf("name" to FieldSpec("name", Kind.TEXT, true, 255), position, deleted),
    )
    val LIST = EntitySpec(
        "list",
        "tasks.lists",
        mapOf(
            "name" to FieldSpec("name", Kind.TEXT, true, 255),
            "icon" to FieldSpec("icon", Kind.TEXT, false, 64),
            "theme" to FieldSpec("theme", Kind.TEXT, false, 64),
            "groupId" to FieldSpec("group_id", Kind.REF),
            position,
            deleted,
        ),
    )
    val TASK = EntitySpec(
        "task",
        "tasks.tasks",
        mapOf(
            "listId" to FieldSpec("list_id", Kind.REF, true),
            "title" to FieldSpec("title", Kind.TEXT, true, 255),
            "note" to FieldSpec("note", Kind.TEXT, true),
            "completed" to FieldSpec("completed", Kind.BOOL, true),
            "completedAt" to FieldSpec("completed_at", Kind.INSTANT),
            "important" to FieldSpec("important", Kind.BOOL, true),
            "dueDate" to FieldSpec("due_date", Kind.DATE),
            "reminderAt" to FieldSpec("reminder_at", Kind.INSTANT),
            "repeatType" to FieldSpec("repeat_type", Kind.TEXT, false, 32),
            "repeatInterval" to FieldSpec("repeat_interval", Kind.INT, true),
            "repeatDays" to FieldSpec("repeat_days", Kind.TEXT, false, 64),
            "myDayDate" to FieldSpec("my_day_date", Kind.DATE),
            "assigneeId" to FieldSpec("assignee_id", Kind.REF),
            position,
            deleted,
        ),
    )
    val STEP = EntitySpec(
        "step",
        "tasks.steps",
        mapOf(
            "taskId" to FieldSpec("task_id", Kind.REF, true),
            "title" to FieldSpec("title", Kind.TEXT, true, 255),
            "completed" to FieldSpec("completed", Kind.BOOL, true),
            position,
            deleted,
        ),
    )

    private val all = listOf(GROUP, LIST, TASK, STEP)

    fun byType(type: String): EntitySpec? = all.firstOrNull { it.type == type }

    /** Converts a JSON value to the type of the database column; throws IllegalArgumentException when it does not fit. */
    fun convert(spec: FieldSpec, value: Any?): Any? =
        when (spec.kind) {
            Kind.TEXT -> convertText(spec, value)
            Kind.BOOL -> when (value) {
                null -> false
                is Boolean -> value
                else -> throw IllegalArgumentException("boolean expected")
            }
            Kind.DOUBLE -> when (value) {
                null -> 0.0
                is Number -> value.toDouble()
                else -> throw IllegalArgumentException("number expected")
            }
            Kind.INT -> when (value) {
                null -> 1
                is Number -> value.toInt()
                else -> throw IllegalArgumentException("integer expected")
            }
            Kind.REF -> value?.let { UUID.fromString(it.toString()) }
            Kind.DATE -> value?.let { LocalDate.parse(it.toString()) }
            Kind.INSTANT -> value?.let { OffsetDateTime.parse(it.toString()) }
        }

    private fun convertText(spec: FieldSpec, value: Any?): String? {
        val text = value?.toString() ?: return if (spec.notNull) "" else null
        if (spec.maxLength != null && text.length > spec.maxLength) {
            throw IllegalArgumentException("text too long")
        }
        return text
    }
}

/** Next occurrence of a repeating task (FR-3.6). */
object RecurrenceCalculator {
    fun next(base: LocalDate, type: String, interval: Int, days: String?): LocalDate? {
        val n = if (interval < 1) 1 else interval
        return when (type) {
            "DAILY" -> base.plusDays(n.toLong())
            "WEEKDAYS" -> nextWeekday(base)
            "WEEKLY" -> nextWeekly(base, n, days)
            "MONTHLY" -> base.plusMonths(n.toLong())
            "YEARLY" -> base.plusYears(n.toLong())
            else -> null
        }
    }

    private fun nextWeekday(base: LocalDate): LocalDate {
        var date = base.plusDays(1)
        while (date.dayOfWeek == DayOfWeek.SATURDAY || date.dayOfWeek == DayOfWeek.SUNDAY) {
            date = date.plusDays(1)
        }
        return date
    }

    private fun nextWeekly(base: LocalDate, interval: Int, days: String?): LocalDate {
        val selected = parseDays(days)
        if (selected.isEmpty()) {
            return base.plusWeeks(interval.toLong())
        }
        val startOfWeek = base.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        var date = base.plusDays(1)
        repeat(7 * interval + 7) {
            val weeks = ChronoUnit.WEEKS.between(startOfWeek, date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)))
            if (date.dayOfWeek in selected && weeks % interval == 0L) {
                return date
            }
            date = date.plusDays(1)
        }
        return base.plusWeeks(interval.toLong())
    }

    private fun parseDays(days: String?): Set<DayOfWeek> {
        if (days.isNullOrBlank()) {
            return emptySet()
        }
        return days
            .split(",")
            .map { it.trim().uppercase() }
            .filter { it.length >= 3 }
            .mapNotNull { token -> DayOfWeek.values().firstOrNull { it.name.startsWith(token) } }
            .toSet()
    }
}

/** Builds the PostgreSQL tsquery for a user-typed search string: every word is a prefix match. */
object SearchQuery {
    fun toTsQuery(text: String): String? {
        val words = text
            .split(Regex("\\s+"))
            .map { word -> word.filter { it.isLetterOrDigit() } }
            .filter { it.isNotEmpty() }
        if (words.isEmpty()) {
            return null
        }
        return words.joinToString(" & ") { "$it:*" }
    }
}
