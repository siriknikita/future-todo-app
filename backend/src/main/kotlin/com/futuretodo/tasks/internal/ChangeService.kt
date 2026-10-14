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
    private val guard: TaskAccessGuard,
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

        authorize(userId, spec, change.id, fields, exists = !created)
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
        when (spec) {
            EntitySpecs.GROUP -> if (exists && repo.findGroup(id)?.ownerId != userId) throw notFound("Group")
            EntitySpecs.LIST -> if (exists) {
                when (access.roleOf(id, userId)) {
                    null -> throw notFound("List")
                    ListRole.MEMBER -> throw ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only the owner can change the list")
                    ListRole.OWNER -> Unit
                }
            }
            EntitySpecs.TASK -> authorizeTask(userId, id, fields, !exists)
            EntitySpecs.STEP -> {
                val taskId = if (exists) repo.taskIdOfStep(id) else uuid(fields["taskId"]?.value, "taskId")
                val listId = taskId?.let { repo.listIdOfTask(it) } ?: throw notFound("Task")
                guard.requireMember(listId, userId)
            }
            else -> unsupported(spec)
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
            guard.requireMember(currentList, userId)
        }
        if (targetList != currentList) {
            guard.requireMember(targetList, userId)
            if (repo.findList(targetList)?.deleted != false) {
                throw notFound("List")
            }
        }
        val assignee = fields["assigneeId"]?.value
        if (assignee != null && access.roleOf(targetList, uuid(assignee, "assigneeId")) == null) {
            throw ApiException(HttpStatus.BAD_REQUEST, "ASSIGNEE_NOT_MEMBER", "Assignee is not a member of the list")
        }
    }

    /** Every spec of [EntitySpecs] has its own branch; reaching this is a programming error, not a bad request. */
    private fun unsupported(spec: EntitySpec): Nothing = error("Entity type ${spec.type} is not handled by ChangeService")

    private fun uuid(value: Any?, field: String): UUID =
        try {
            UUID.fromString(value.toString())
        } catch (e: IllegalArgumentException) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_FIELD", "Invalid value for $field")
        }

    // ---- create / update ----

    private fun create(userId: UUID, spec: EntitySpec, id: UUID, fields: Map<String, FieldChange>) {
        when (spec) {
            EntitySpecs.GROUP -> repo.insertGroup(id, userId)
            EntitySpecs.LIST -> {
                repo.insertList(id, userId)
                access.registerOwner(id, userId)
            }
            EntitySpecs.TASK -> repo.insertTask(id, uuid(fields["listId"]?.value, "listId"))
            EntitySpecs.STEP -> repo.insertStep(id, uuid(fields["taskId"]?.value, "taskId"))
            else -> unsupported(spec)
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
        val snapshot = snapshot(spec, id)
        val payload = snapshot.payload
        if (payload is TaskDto) {
            taskSideEffects(userId, payload, before, accepted)
        }
        events.publishEvent(EntityChanged(spec.type, id, snapshot.listId, userId, snapshot.deleted, payload))
    }

    /** The stored row after a change, with the list it belongs to (for fan-out) and its tombstone flag. */
    private class EntitySnapshot(val payload: Any, val listId: UUID?, val deleted: Boolean)

    private fun snapshot(spec: EntitySpec, id: UUID): EntitySnapshot =
        when (spec) {
            EntitySpecs.GROUP -> repo.findGroup(id)!!.let { EntitySnapshot(it, null, it.deleted) }
            EntitySpecs.LIST -> repo.findList(id)!!.let { EntitySnapshot(it, id, it.deleted) }
            EntitySpecs.TASK -> repo.findTask(id)!!.let { EntitySnapshot(it, it.listId, it.deleted) }
            EntitySpecs.STEP -> repo.findStep(id)!!.let { EntitySnapshot(it, repo.listIdOfTask(it.taskId), it.deleted) }
            else -> unsupported(spec)
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
        val taskClocks = EntitySpecs.TASK_OCCURRENCE_FIELDS.associateWith { stamp }
        repo.insertTaskCopy(newId, task, next, task.reminderAt?.plusDays(shift), taskClocks)
        events.publishEvent(EntityChanged(EntitySpecs.TASK.type, newId, task.listId, userId, false, repo.findTask(newId)!!))
        repo.stepsOfTask(task.id).forEach { step ->
            val stepId = UUID.randomUUID()
            repo.insertStepCopy(stepId, newId, step, EntitySpecs.STEP_OCCURRENCE_FIELDS.associateWith { stamp })
            events.publishEvent(EntityChanged(EntitySpecs.STEP.type, stepId, task.listId, userId, false, repo.findStep(stepId)!!))
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
