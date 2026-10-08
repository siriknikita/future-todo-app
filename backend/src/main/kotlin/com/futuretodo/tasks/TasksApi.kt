package com.futuretodo.tasks

import com.futuretodo.shared.FieldChange
import java.util.UUID

/** One entity edit coming from a client (entityType is group, list, task or step). */
data class IncomingChange(val entityType: String, val id: UUID, val fields: Map<String, FieldChange>)

/** Implemented by the tasks module: applies a change with per-field last-write-wins. Used by sync. */
interface SyncChangeApplier {
    fun apply(userId: UUID, change: IncomingChange)
}

/** Published after an entity changed. The payload is the full entity state (JSON serializable). */
data class EntityChanged(
    val entityType: String,
    val entityId: UUID,
    val listId: UUID?,
    val actorId: UUID,
    val deleted: Boolean,
    val payload: Any,
)

data class TaskAssigned(
    val taskId: UUID,
    val listId: UUID,
    val taskTitle: String,
    val assigneeId: UUID,
    val assignerId: UUID,
)
