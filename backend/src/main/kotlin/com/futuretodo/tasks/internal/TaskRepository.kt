package com.futuretodo.tasks.internal

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import java.time.LocalDate
import java.time.OffsetDateTime
import java.util.UUID

private const val TASK_COLS = "t.id, t.list_id, t.title, t.note, t.completed, t.completed_at, t.important, t.due_date, " +
    "t.reminder_at, t.repeat_type, t.repeat_interval, t.repeat_days, t.my_day_date, t.assignee_id, t.position, " +
    "t.created_at, t.deleted, t.clocks"

@Repository
class TaskRepository(private val jdbc: NamedParameterJdbcTemplate, private val json: ObjectMapper) {
    private fun clocksOf(text: String): Map<String, String> = json.readValue(text)

    private val groupMapper = RowMapper<GroupDto> { rs, _ ->
        GroupDto(
            rs.getObject("id", UUID::class.java),
            rs.getObject("owner_id", UUID::class.java),
            rs.getString("name"),
            rs.getDouble("position"),
            rs.getBoolean("deleted"),
            rs.getObject("created_at", OffsetDateTime::class.java),
            clocksOf(rs.getString("clocks")),
        )
    }

    private val listMapper = RowMapper<ListDto> { rs, _ ->
        ListDto(
            rs.getObject("id", UUID::class.java),
            rs.getObject("owner_id", UUID::class.java),
            rs.getObject("group_id", UUID::class.java),
            rs.getString("name"),
            rs.getString("icon"),
            rs.getString("theme"),
            rs.getDouble("position"),
            rs.getBoolean("deleted"),
            rs.getObject("created_at", OffsetDateTime::class.java),
            clocksOf(rs.getString("clocks")),
        )
    }

    private val stepMapper = RowMapper<StepDto> { rs, _ ->
        StepDto(
            rs.getObject("id", UUID::class.java),
            rs.getObject("task_id", UUID::class.java),
            rs.getString("title"),
            rs.getBoolean("completed"),
            rs.getDouble("position"),
            rs.getBoolean("deleted"),
            rs.getObject("created_at", OffsetDateTime::class.java),
            clocksOf(rs.getString("clocks")),
        )
    }

    private val taskMapper = RowMapper<TaskDto> { rs, _ ->
        TaskDto(
            id = rs.getObject("id", UUID::class.java),
            listId = rs.getObject("list_id", UUID::class.java),
            title = rs.getString("title"),
            note = rs.getString("note"),
            completed = rs.getBoolean("completed"),
            completedAt = rs.getObject("completed_at", OffsetDateTime::class.java),
            important = rs.getBoolean("important"),
            dueDate = rs.getObject("due_date", LocalDate::class.java),
            reminderAt = rs.getObject("reminder_at", OffsetDateTime::class.java),
            repeatType = rs.getString("repeat_type"),
            repeatInterval = rs.getInt("repeat_interval"),
            repeatDays = rs.getString("repeat_days"),
            myDayDate = rs.getObject("my_day_date", LocalDate::class.java),
            assigneeId = rs.getObject("assignee_id", UUID::class.java),
            position = rs.getDouble("position"),
            createdAt = rs.getObject("created_at", OffsetDateTime::class.java),
            deleted = rs.getBoolean("deleted"),
            clocks = clocksOf(rs.getString("clocks")),
        )
    }

    // ---- generic helpers used by the change engine ----

    /** Returns the stored field clocks, or null when the row does not exist. Locks the row. */
    fun clocks(spec: EntitySpec, id: UUID): Map<String, String>? =
        jdbc
            .query("SELECT clocks FROM ${spec.table} WHERE id = :id FOR UPDATE", mapOf("id" to id)) { rs, _ ->
                clocksOf(rs.getString("clocks"))
            }.firstOrNull()

    fun update(spec: EntitySpec, id: UUID, values: Map<String, Any?>, clocks: Map<String, String>) {
        val params = MapSqlParameterSource().addValue("id", id)
        val sets = mutableListOf<String>()
        values.forEach { (column, value) ->
            sets.add("$column = :$column")
            params.addValue(column, value)
        }
        sets.add("clocks = :clocks")
        params.addValue("clocks", json.writeValueAsString(clocks))
        jdbc.update("UPDATE ${spec.table} SET ${sets.joinToString(", ")} WHERE id = :id", params)
    }

    fun insertGroup(id: UUID, ownerId: UUID) {
        jdbc.update("INSERT INTO tasks.list_groups (id, owner_id) VALUES (:id, :owner)", mapOf("id" to id, "owner" to ownerId))
    }

    fun insertList(id: UUID, ownerId: UUID) {
        jdbc.update("INSERT INTO tasks.lists (id, owner_id) VALUES (:id, :owner)", mapOf("id" to id, "owner" to ownerId))
    }

    fun insertTask(id: UUID, listId: UUID) {
        jdbc.update("INSERT INTO tasks.tasks (id, list_id) VALUES (:id, :list)", mapOf("id" to id, "list" to listId))
    }

    fun insertStep(id: UUID, taskId: UUID) {
        jdbc.update("INSERT INTO tasks.steps (id, task_id) VALUES (:id, :task)", mapOf("id" to id, "task" to taskId))
    }

    fun insertTaskCopy(id: UUID, source: TaskDto, dueDate: LocalDate, reminderAt: OffsetDateTime?, clocks: Map<String, String>) {
        jdbc.update(
            "INSERT INTO tasks.tasks (id, list_id, title, note, important, due_date, reminder_at, repeat_type, repeat_interval, " +
                "repeat_days, assignee_id, position, clocks) VALUES (:id, :list, :title, :note, :important, :due, :reminder, " +
                ":type, :interval, :days, :assignee, :position, :clocks)",
            MapSqlParameterSource()
                .addValue("id", id)
                .addValue("list", source.listId)
                .addValue("title", source.title)
                .addValue("note", source.note)
                .addValue("important", source.important)
                .addValue("due", dueDate)
                .addValue("reminder", reminderAt)
                .addValue("type", source.repeatType)
                .addValue("interval", source.repeatInterval)
                .addValue("days", source.repeatDays)
                .addValue("assignee", source.assigneeId)
                .addValue("position", source.position)
                .addValue("clocks", json.writeValueAsString(clocks)),
        )
    }

    fun insertStepCopy(id: UUID, taskId: UUID, source: StepDto, clocks: Map<String, String>) {
        jdbc.update(
            "INSERT INTO tasks.steps (id, task_id, title, position, clocks) VALUES (:id, :task, :title, :position, :clocks)",
            mapOf(
                "id" to id,
                "task" to taskId,
                "title" to source.title,
                "position" to source.position,
                "clocks" to json.writeValueAsString(clocks),
            ),
        )
    }

    // ---- finders ----

    fun findGroup(id: UUID): GroupDto? =
        jdbc.query("SELECT * FROM tasks.list_groups WHERE id = :id", mapOf("id" to id), groupMapper).firstOrNull()

    fun findList(id: UUID): ListDto? = jdbc.query("SELECT * FROM tasks.lists WHERE id = :id", mapOf("id" to id), listMapper).firstOrNull()

    fun findStep(id: UUID): StepDto? = jdbc.query("SELECT * FROM tasks.steps WHERE id = :id", mapOf("id" to id), stepMapper).firstOrNull()

    fun findTask(id: UUID): TaskDto? =
        jdbc.query("SELECT $TASK_COLS FROM tasks.tasks t WHERE t.id = :id", mapOf("id" to id), taskMapper).firstOrNull()

    fun groupsOf(ownerId: UUID): List<GroupDto> =
        jdbc.query(
            "SELECT * FROM tasks.list_groups WHERE owner_id = :owner AND NOT deleted ORDER BY position, created_at",
            mapOf("owner" to ownerId),
            groupMapper,
        )

    fun listsByIds(ids: Collection<UUID>): List<ListDto> {
        if (ids.isEmpty()) {
            return emptyList()
        }
        return jdbc.query(
            "SELECT * FROM tasks.lists WHERE id IN (:ids) AND NOT deleted ORDER BY position, created_at",
            mapOf("ids" to ids),
            listMapper,
        )
    }

    fun listsInGroup(groupId: UUID, ownerId: UUID): List<ListDto> =
        jdbc.query(
            "SELECT * FROM tasks.lists WHERE group_id = :group AND owner_id = :owner AND NOT deleted",
            mapOf("group" to groupId, "owner" to ownerId),
            listMapper,
        )

    fun listIdOfTask(taskId: UUID): UUID? =
        jdbc
            .query("SELECT list_id FROM tasks.tasks WHERE id = :id", mapOf("id" to taskId)) { rs, _ ->
                rs.getObject("list_id", UUID::class.java)
            }.firstOrNull()

    fun taskIdOfStep(stepId: UUID): UUID? =
        jdbc
            .query("SELECT task_id FROM tasks.steps WHERE id = :id", mapOf("id" to stepId)) { rs, _ ->
                rs.getObject("task_id", UUID::class.java)
            }.firstOrNull()

    fun stepsOfTask(taskId: UUID): List<StepDto> =
        jdbc.query(
            "SELECT * FROM tasks.steps WHERE task_id = :task AND NOT deleted ORDER BY position, created_at",
            mapOf("task" to taskId),
            stepMapper,
        )

    fun withSteps(tasks: List<TaskDto>): List<TaskDto> {
        if (tasks.isEmpty()) {
            return tasks
        }
        val steps = jdbc
            .query(
                "SELECT * FROM tasks.steps WHERE task_id IN (:ids) AND NOT deleted ORDER BY position, created_at",
                mapOf("ids" to tasks.map { it.id }),
                stepMapper,
            ).groupBy { it.taskId }
        return tasks.map { it.copy(steps = steps[it.id] ?: emptyList()) }
    }

    fun tasksOfList(listId: UUID, showCompleted: Boolean, sort: String, descending: Boolean): List<TaskDto> {
        val dir = if (descending) "DESC" else "ASC"
        val order = when (sort) {
            "importance" -> "CASE WHEN t.important THEN 0 ELSE 1 END $dir, t.created_at"
            "dueDate" -> "t.due_date $dir NULLS LAST, t.created_at"
            "alphabetical" -> "lower(t.title) $dir"
            "createdAt" -> "t.created_at $dir"
            else -> "t.position $dir, t.created_at"
        }
        val completedFilter = if (showCompleted) "" else "AND NOT t.completed"
        return jdbc.query(
            "SELECT $TASK_COLS FROM tasks.tasks t WHERE t.list_id = :list AND NOT t.deleted $completedFilter ORDER BY $order",
            mapOf("list" to listId),
            taskMapper,
        )
    }

    /** Tasks of the given lists (lists must not be deleted) that match a constant SQL condition. */
    fun smart(listIds: Collection<UUID>, condition: String, params: Map<String, Any?>, order: String): List<TaskDto> {
        if (listIds.isEmpty()) {
            return emptyList()
        }
        val source = MapSqlParameterSource(params).addValue("lists", listIds)
        return jdbc.query(
            "SELECT $TASK_COLS FROM tasks.tasks t JOIN tasks.lists l ON l.id = t.list_id " +
                "WHERE t.list_id IN (:lists) AND NOT t.deleted AND NOT l.deleted AND ($condition) ORDER BY $order",
            source,
            taskMapper,
        )
    }

    fun search(listIds: Collection<UUID>, tsQuery: String, includeCompleted: Boolean): List<TaskDto> {
        if (listIds.isEmpty()) {
            return emptyList()
        }
        val completedFilter = if (includeCompleted) "" else "AND NOT t.completed"
        val source = MapSqlParameterSource("q", tsQuery).addValue("lists", listIds)
        return jdbc.query(
            "SELECT $TASK_COLS FROM tasks.tasks t JOIN tasks.lists l ON l.id = t.list_id " +
                "WHERE t.list_id IN (:lists) AND NOT t.deleted AND NOT l.deleted $completedFilter " +
                "AND (to_tsvector('simple', t.title || ' ' || t.note) @@ to_tsquery('simple', :q) " +
                "OR EXISTS (SELECT 1 FROM tasks.steps s WHERE s.task_id = t.id AND NOT s.deleted " +
                "AND to_tsvector('simple', s.title) @@ to_tsquery('simple', :q))) " +
                "ORDER BY t.created_at DESC LIMIT 100",
            source,
            taskMapper,
        )
    }

    // ---- export and account deletion ----

    fun exportFor(ownerId: UUID): Map<String, Any> {
        val params = mapOf("owner" to ownerId)
        val groups = jdbc.query("SELECT * FROM tasks.list_groups WHERE owner_id = :owner AND NOT deleted", params, groupMapper)
        val lists = jdbc.query("SELECT * FROM tasks.lists WHERE owner_id = :owner AND NOT deleted", params, listMapper)
        val tasks = jdbc.query(
            "SELECT $TASK_COLS FROM tasks.tasks t JOIN tasks.lists l ON l.id = t.list_id " +
                "WHERE l.owner_id = :owner AND NOT l.deleted AND NOT t.deleted",
            params,
            taskMapper,
        )
        val steps = jdbc.query(
            "SELECT s.* FROM tasks.steps s JOIN tasks.tasks t ON t.id = s.task_id JOIN tasks.lists l ON l.id = t.list_id " +
                "WHERE l.owner_id = :owner AND NOT l.deleted AND NOT t.deleted AND NOT s.deleted",
            params,
            stepMapper,
        )
        return mapOf("groups" to groups, "lists" to lists, "tasks" to tasks, "steps" to steps)
    }

    fun deleteAllOf(userId: UUID) {
        val params = mapOf("user" to userId)
        jdbc.update("UPDATE tasks.tasks SET assignee_id = NULL WHERE assignee_id = :user", params)
        jdbc.update("DELETE FROM tasks.lists WHERE owner_id = :user", params)
        jdbc.update("DELETE FROM tasks.list_groups WHERE owner_id = :user", params)
    }
}
