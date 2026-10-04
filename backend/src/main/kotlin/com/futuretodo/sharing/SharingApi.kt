package com.futuretodo.sharing

import java.util.UUID

enum class ListRole { OWNER, MEMBER }

/** Published when a user joins or leaves a shared list. */
data class MembershipChanged(val listId: UUID, val userId: UUID, val joined: Boolean)

/** The only way other modules learn who may access a list. */
interface ListAccess {
    fun registerOwner(listId: UUID, ownerId: UUID)

    fun roleOf(listId: UUID, userId: UUID): ListRole?

    fun accessibleListIds(userId: UUID): Set<UUID>

    fun memberIds(listId: UUID): Set<UUID>
}
