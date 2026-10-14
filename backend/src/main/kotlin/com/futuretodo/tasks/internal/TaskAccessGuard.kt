package com.futuretodo.tasks.internal

import com.futuretodo.shared.ApiException
import com.futuretodo.sharing.ListAccess
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import java.util.UUID

/** Anything the caller may not see is reported as missing, so its existence is not leaked. */
fun notFound(what: String) = ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "$what not found")

/** List visibility rules shared by the REST controllers and the change engine of the tasks module. */
@Component
class TaskAccessGuard(private val repo: TaskRepository, private val access: ListAccess) {
    /** True when [userId] is the owner or a member of the list. */
    fun isMember(listId: UUID, userId: UUID): Boolean = access.roleOf(listId, userId) != null

    /** Throws 404 "List not found" unless [userId] is the owner or a member of the list. */
    fun requireMember(listId: UUID, userId: UUID) {
        if (!isMember(listId, userId)) {
            throw notFound("List")
        }
    }

    /** The list, when it exists, is not deleted and [userId] has access to it; 404 "List not found" otherwise. */
    fun visibleList(id: UUID, userId: UUID): ListDto {
        val list = repo.findList(id)
        if (list == null || list.deleted || !isMember(id, userId)) {
            throw notFound("List")
        }
        return list
    }
}
