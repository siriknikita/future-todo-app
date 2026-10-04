package com.futuretodo.tasks.internal

import com.futuretodo.shared.ApiException
import com.futuretodo.shared.FieldChange
import com.futuretodo.shared.HlcClock
import com.futuretodo.shared.Lww
import com.futuretodo.sharing.ListAccess
import com.futuretodo.sharing.ListRole
import com.futuretodo.tasks.EntityChanged
import com.futuretodo.tasks.IncomingChange
import com.futuretodo.tasks.SyncChangeApplier
import com.futuretodo.tasks.TaskAssigned
import org.springframework.context.ApplicationEventPublisher
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * The write engine of the tasks module. REST controllers and the sync module both write through [apply]:
 * every field carries an HLC, the larger HLC wins per field, deletion is the field "deleted".
 */
@Service
class ChangeService(
    private val repo: TaskRepository,
    private val access: ListAccess,
    private val events: ApplicationEventPublisher,
    private val hlc: HlcClock,
) : SyncChangeApplier {
    @Transactional
    override fun apply(userId: UUID, change: IncomingChange) {
        val spec = EntitySpecs.byType(change.entityType)
            ?: throw ApiException(HttpStatus.BAD_REQUEST, "UNKNOWN_ENTITY", "Unknown entity type ${change.entityType}")
        val fields = change.fields.filterKeys { it in spec.fields }
        val existingClocks = repo.clocks(spec, change.id)
        val created = existingClocks == null
        val before = if (spec === EntitySpecs.TASK && !created) repo.findTask(change.id) else null

        authorize(userId, spec, change.id, fields, created)
        if (created) {
            create(userId, spec, change.id, fields)
        }
        val accepted = Lww.accepted(existingClocks ?: emptyMap(), fields)
        if (accepted.isNotEmpty()) {
            write(spec, change.id, existingClocks ?: emptyMap(), accepted)
        }
        if (created || accepted.isNotEmpty()) {
            afterApply(userId, spec, change.id, accepted, before)
        }
    }

    // ---- authorization ----

    private fun authorize(userId: UUID, spec: EntitySpec, id: UUID, fields: Map<String, FieldChange>, exists: Boolean) {
        when (spec.type) {
            "group" -> if (exists && repo.findGroup(id)?.ownerId != userId) throw notFound("Group")
            "list" -> if (exists) {
                when (access.roleOf(id, userId)) {
                    null -> throw notFound("List")
                    ListRole.MEMBER -> throw ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only the owner can change the list")
                    ListRole.OWNER -> Unit
                }
            }
            "task" -> authorizeTask(userId, id, fields, !exists)
            "step" -> {
                val taskId = if (exists) repo.taskIdOfStep(id) else uuid(fields["taskId"]?.value, "taskId")
                val listId = taskId?.let { repo.listIdOfTask(it) } ?: throw notFound("Task")
                requireAccess(userId, listId)
            }
        }
    }

    private fun authorizeTask(userId: UUID, id: UUID, fields: Map<String, FieldChange>, isNew: Boolean) {
        val currentList = if (isNew) null else repo.listIdOfTask(id)
        val newListValue = fields["listId"]?.value
        val targetList = if (newListValue != null) uuid(newListValue, "listId") else currentList
        if (targetList == null) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_FIELD", "listId is required")
        }
        if (currentList != null) {
            requireAccess(userId, currentList)
        }
        if (targetList != currentList) {
            requireAccess(userId, targetList)
            if (repo.findList(targetList)?.deleted != false) {
                throw notFound("List")
            }
        }
        val assignee = fields["assigneeId"]?.value
        if (assignee != null && access.roleOf(targetList, uuid(assignee, "assigneeId")) == null) {
            throw ApiException(HttpStatus.BAD_REQUEST, "ASSIGNEE_NOT_MEMBER", "Assignee is not a member of the list")
        }
    }

    private fun requireAccess(userId: UUID, listId: UUID) {
        if (access.roleOf(listId, userId) == null) {
            throw notFound("List")
        }
    }

    private fun notFound(what: String) = ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "$what not found")

    private fun uuid(value: Any?, field: String): UUID =
        try {
            UUID.fromString(value.toString())
        } catch (e: IllegalArgumentException) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_FIELD", "Invalid value for $field")
        }

    // ---- create / update ----

    private fun create(userId: UUID, spec: EntitySpec, id: UUID, fields: Map<String, FieldChange>) {
        when (spec.type) {
            "group" -> repo.insertGroup(id, userId)
            "list" -> {
                repo.insertList(id, userId)
                access.registerOwner(id, userId)
            }
            "task" -> repo.insertTask(id, uuid(fields["listId"]?.value, "listId"))
            else -> repo.insertStep(id, uuid(fields["taskId"]?.value, "taskId"))
        }
    }

    private fun write(spec: EntitySpec, id: UUID, clocks: Map<String, String>, accepted: Map<String, FieldChange>) {
        val values = linkedMapOf<String, Any?>()
        accepted.forEach { (name, change) ->
            val field = spec.fields.getValue(name)
            val converted = try {
                EntitySpecs.convert(field, change.value)
            } catch (e: RuntimeException) {
                throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_FIELD", "Invalid value for $name")
            }
            values[field.column] = converted
        }
        repo.update(spec, id, values, clocks + accepted.mapValues { it.value.hlc })
    }

    // ---- side effects ----

    private fun afterApply(userId: UUID, spec: EntitySpec, id: UUID, accepted: Map<String, FieldChange>, before: TaskDto?) {
        val payload: Any
        val listId: UUID?
        val deleted: Boolean
        when (spec.type) {
            "group" -> {
                val group = repo.findGroup(id)!!
                payload = group
                listId = null
                deleted = group.deleted
            }
            "list" -> {
                val list = repo.findList(id)!!
                payload = list
                listId = id
                deleted = list.deleted
            }
            "task" -> {
                val task = repo.findTask(id)!!
                payload = task
                listId = task.listId
                deleted = task.deleted
                taskSideEffects(userId, task, before, accepted)
            }
            else -> {
                val step = repo.findStep(id)!!
                payload = step
                listId = repo.listIdOfTask(step.taskId)
                deleted = step.deleted
            }
        }
        events.publishEvent(EntityChanged(spec.type, id, listId, userId, deleted, payload))
    }

    private fun taskSideEffects(userId: UUID, task: TaskDto, before: TaskDto?, accepted: Map<String, FieldChange>) {
        val assignee = task.assigneeId
        if (accepted.containsKey("assigneeId") && assignee != null && assignee != userId && assignee != before?.assigneeId) {
            events.publishEvent(TaskAssigned(task.id, task.listId, task.title, assignee, userId))
        }
        if (before != null && accepted.containsKey("completed") && task.completed && !before.completed && task.repeatType != null) {
            spawnNextOccurrence(userId, task)
        }
    }

    /** FR-3.6: completing a repeating task creates the next occurrence. */
    private fun spawnNextOccurrence(userId: UUID, task: TaskDto) {
        val base = task.dueDate ?: LocalDate.now(ZoneOffset.UTC)
        val next = RecurrenceCalculator.next(base, task.repeatType!!, task.repeatInterval, task.repeatDays) ?: return
        val shift = ChronoUnit.DAYS.between(base, next)
        val newId = UUID.randomUUID()
        val stamp = hlc.next()
        val taskClocks = listOf(
            "listId", "title", "note", "important", "dueDate", "reminderAt", "repeatType", "repeatInterval", "repeatDays",
            "assigneeId", "position",
        ).associateWith { stamp }
        repo.insertTaskCopy(newId, task, next, task.reminderAt?.plusDays(shift), taskClocks)
        events.publishEvent(EntityChanged("task", newId, task.listId, userId, false, repo.findTask(newId)!!))
        repo.stepsOfTask(task.id).forEach { step ->
            val stepId = UUID.randomUUID()
            repo.insertStepCopy(stepId, newId, step, listOf("title", "position").associateWith { stamp })
            events.publishEvent(EntityChanged("step", stepId, task.listId, userId, false, repo.findStep(stepId)!!))
        }
    }

    // ---- REST helper ----

    /** Writes a REST request body as one change stamped with a fresh server clock. */
    @Transactional
    fun writeRest(userId: UUID, spec: EntitySpec, id: UUID, body: Map<String, Any?>) {
        val stamp = hlc.next()
        val fields = body.filterKeys { it in spec.fields }.mapValues { FieldChange(it.value, stamp) }
        apply(userId, IncomingChange(spec.type, id, fields))
    }

    fun nowUtc(): OffsetDateTime = OffsetDateTime.now(ZoneOffset.UTC)
}
