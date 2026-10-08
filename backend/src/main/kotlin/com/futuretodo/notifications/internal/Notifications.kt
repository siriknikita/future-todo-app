package com.futuretodo.notifications.internal

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import com.futuretodo.accounts.UserDeleted
import com.futuretodo.shared.CurrentUser
import com.futuretodo.sync.RealtimeNotifier
import com.futuretodo.tasks.TaskAssigned
import org.slf4j.LoggerFactory
import org.springframework.context.event.EventListener
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.OffsetDateTime
import java.util.UUID

data class NotificationDto(
    val id: UUID,
    val type: String,
    val title: String,
    val body: String,
    val data: Map<String, Any?>,
    val read: Boolean,
    val createdAt: OffsetDateTime,
)

data class NotificationPreferences(val assignment: Boolean = true, val reminders: Boolean = true, val emailDigest: Boolean = false)

@Service
class NotificationService(
    private val jdbc: JdbcTemplate,
    private val json: ObjectMapper,
    private val realtime: RealtimeNotifier,
) {
    private val log = LoggerFactory.getLogger(NotificationService::class.java)

    /** FR-6.3: tell a user that a task was assigned to them. */
    @EventListener
    fun onTaskAssigned(event: TaskAssigned) {
        if (!preferences(event.assigneeId).assignment) {
            return
        }
        val id = UUID.randomUUID()
        val data = mapOf(
            "taskId" to event.taskId.toString(),
            "listId" to event.listId.toString(),
            "assignerId" to event.assignerId.toString(),
        )
        jdbc.update(
            "INSERT INTO notifications.notifications (id, user_id, type, title, body, data) VALUES (?, ?, 'TASK_ASSIGNED', ?, ?, ?)",
            id,
            event.assigneeId,
            "Task assigned to you",
            event.taskTitle,
            json.writeValueAsString(data),
        )
        log.info("Push (stub, no FCM configured) to user {}: task '{}' assigned", event.assigneeId, event.taskTitle)
        realtime.notifyUsers(
            listOf(event.assigneeId),
            "notification",
            mapOf(
                "notificationId" to id.toString(),
                "notificationType" to "TASK_ASSIGNED",
                "title" to "Task assigned to you",
                "body" to event.taskTitle,
            ) + data,
        )
    }

    @EventListener
    fun onUserDeleted(event: UserDeleted) {
        jdbc.update("DELETE FROM notifications.notifications WHERE user_id = ?", event.userId)
        jdbc.update("DELETE FROM notifications.preferences WHERE user_id = ?", event.userId)
    }

    fun list(userId: UUID, unreadOnly: Boolean): List<NotificationDto> {
        val filter = if (unreadOnly) "AND NOT read" else ""
        return jdbc.query(
            "SELECT id, type, title, body, data, read, created_at FROM notifications.notifications " +
                "WHERE user_id = ? $filter ORDER BY created_at DESC LIMIT 100",
            RowMapper<NotificationDto> { rs, _ ->
                NotificationDto(
                    rs.getObject("id", UUID::class.java),
                    rs.getString("type"),
                    rs.getString("title"),
                    rs.getString("body"),
                    json.readValue(rs.getString("data")),
                    rs.getBoolean("read"),
                    rs.getObject("created_at", OffsetDateTime::class.java),
                )
            },
            userId,
        )
    }

    fun markRead(userId: UUID, id: UUID) {
        jdbc.update("UPDATE notifications.notifications SET read = true WHERE id = ? AND user_id = ?", id, userId)
    }

    fun preferences(userId: UUID): NotificationPreferences =
        jdbc
            .query(
                "SELECT assignment, reminders, email_digest FROM notifications.preferences WHERE user_id = ?",
                RowMapper<NotificationPreferences> { rs, _ ->
                    NotificationPreferences(rs.getBoolean("assignment"), rs.getBoolean("reminders"), rs.getBoolean("email_digest"))
                },
                userId,
            ).firstOrNull() ?: NotificationPreferences()

    fun savePreferences(userId: UUID, preferences: NotificationPreferences): NotificationPreferences {
        jdbc.update(
            "INSERT INTO notifications.preferences (user_id, assignment, reminders, email_digest) VALUES (?, ?, ?, ?) " +
                "ON CONFLICT (user_id) DO UPDATE SET assignment = EXCLUDED.assignment, reminders = EXCLUDED.reminders, " +
                "email_digest = EXCLUDED.email_digest",
            userId,
            preferences.assignment,
            preferences.reminders,
            preferences.emailDigest,
        )
        return preferences(userId)
    }
}

@RestController
@RequestMapping("/api/v1/notifications")
class NotificationController(private val notifications: NotificationService) {
    @GetMapping
    fun list(
        @RequestParam(defaultValue = "false") unreadOnly: Boolean
    ): List<NotificationDto> =
        notifications.list(CurrentUser.id(), unreadOnly)

    @PostMapping("/{id}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun markRead(
        @PathVariable id: UUID
    ) = notifications.markRead(CurrentUser.id(), id)

    @GetMapping("/preferences")
    fun preferences(): NotificationPreferences = notifications.preferences(CurrentUser.id())

    @PutMapping("/preferences")
    fun savePreferences(
        @RequestBody preferences: NotificationPreferences
    ): NotificationPreferences =
        notifications.savePreferences(CurrentUser.id(), preferences)
}
