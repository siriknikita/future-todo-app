package com.futuretodo.accounts

import com.futuretodo.shared.AuthUser
import java.util.UUID

/** Published (synchronously) after the account is deleted. Other modules remove their data for this user. */
data class UserDeleted(val userId: UUID)

/** Lets other modules show user names without touching the accounts schema. */
interface UserDirectory {
    fun displayNames(ids: Collection<UUID>): Map<UUID, String>
}

/** Verifies access tokens (used by the WebSocket handshake). */
interface TokenVerifier {
    fun verify(token: String): AuthUser?
}

/** Modules implement this to add their data to the account export (FR-1.6). */
interface UserDataContributor {
    fun exportKey(): String

    fun exportData(userId: UUID): Any
}
