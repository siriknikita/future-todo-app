package com.futuretodo.sharing.internal

import com.futuretodo.accounts.UserDataContributor
import com.futuretodo.accounts.UserDeleted
import com.futuretodo.accounts.UserDirectory
import com.futuretodo.shared.ApiException
import com.futuretodo.shared.CurrentUser
import com.futuretodo.sharing.ListAccess
import com.futuretodo.sharing.ListRole
import com.futuretodo.sharing.MembershipChanged
import org.springframework.context.ApplicationEventPublisher
import org.springframework.context.event.EventListener
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Component
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.security.SecureRandom
import java.time.OffsetDateTime
import java.util.Base64
import java.util.UUID

data class MemberDto(val userId: UUID, val displayName: String, val role: String, val joinedAt: OffsetDateTime)

data class InvitationDto(val token: String, val listId: UUID, val createdAt: OffsetDateTime)

data class JoinResult(val listId: UUID)

@Service
class SharingService(
    private val jdbc: JdbcTemplate,
    private val directory: UserDirectory,
    private val events: ApplicationEventPublisher,
) : ListAccess {
    private val random = SecureRandom()

    // ---- ListAccess (public API for other modules) ----

    override fun registerOwner(listId: UUID, ownerId: UUID) {
        jdbc.update(
            "INSERT INTO sharing.list_members (list_id, user_id, role) VALUES (?, ?, 'OWNER') ON CONFLICT DO NOTHING",
            listId, ownerId,
        )
    }

    override fun roleOf(listId: UUID, userId: UUID): ListRole? =
        jdbc.queryForList(
            "SELECT role FROM sharing.list_members WHERE list_id = ? AND user_id = ?",
            String::class.java, listId, userId,
        ).firstOrNull()?.let { ListRole.valueOf(it) }

    override fun accessibleListIds(userId: UUID): Set<UUID> =
        jdbc.queryForList("SELECT list_id FROM sharing.list_members WHERE user_id = ?", UUID::class.java, userId).toSet()

    override fun memberIds(listId: UUID): Set<UUID> =
        jdbc.queryForList("SELECT user_id FROM sharing.list_members WHERE list_id = ?", UUID::class.java, listId).toSet()

    // ---- invitations (FR-5.1, FR-5.2) ----

    fun createInvitation(listId: UUID, userId: UUID): InvitationDto {
        requireOwner(listId, userId)
        val bytes = ByteArray(24)
        random.nextBytes(bytes)
        val token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        jdbc.update("INSERT INTO sharing.invitations (token, list_id, created_by) VALUES (?, ?, ?)", token, listId, userId)
        return InvitationDto(token, listId, OffsetDateTime.now())
    }

    fun revokeInvitations(listId: UUID, userId: UUID) {
        requireOwner(listId, userId)
        jdbc.update("UPDATE sharing.invitations SET revoked = true WHERE list_id = ? AND NOT revoked", listId)
    }

    @Transactional
    fun accept(token: String, userId: UUID): JoinResult {
        val listId = jdbc.queryForList(
            "SELECT list_id FROM sharing.invitations WHERE token = ? AND NOT revoked",
            UUID::class.java, token,
        ).firstOrNull() ?: throw ApiException(HttpStatus.NOT_FOUND, "INVITATION_INVALID", "Invitation is invalid or was revoked")
        if (roleOf(listId, userId) == null) {
            jdbc.update("INSERT INTO sharing.list_members (list_id, user_id, role) VALUES (?, ?, 'MEMBER')", listId, userId)
            events.publishEvent(MembershipChanged(listId, userId, true))
        }
        return JoinResult(listId)
    }

    // ---- members (FR-5.3, FR-5.5) ----

    fun members(listId: UUID, userId: UUID): List<MemberDto> {
        if (roleOf(listId, userId) == null) {
            throw ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "List not found")
        }
        val rows = jdbc.query(
            "SELECT user_id, role, joined_at FROM sharing.list_members WHERE list_id = ? ORDER BY joined_at",
            RowMapper<Triple<UUID, String, OffsetDateTime>> { rs, _ ->
                Triple(
                    rs.getObject("user_id", UUID::class.java),
                    rs.getString("role"),
                    rs.getObject("joined_at", OffsetDateTime::class.java),
                )
            },
            listId,
        )
        val names = directory.displayNames(rows.map { it.first })
        return rows.map { MemberDto(it.first, names[it.first] ?: "?", it.second, it.third) }
    }

    @Transactional
    fun removeMember(listId: UUID, targetId: UUID, userId: UUID) {
        val callerRole = roleOf(listId, userId) ?: throw ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "List not found")
        val targetRole = roleOf(listId, targetId) ?: throw ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "Member not found")
        if (targetRole == ListRole.OWNER) {
            throw ApiException(HttpStatus.BAD_REQUEST, "OWNER_CANNOT_LEAVE", "The owner cannot leave or be removed")
        }
        if (targetId != userId && callerRole != ListRole.OWNER) {
            throw ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only the owner can remove members")
        }
        jdbc.update("DELETE FROM sharing.list_members WHERE list_id = ? AND user_id = ?", listId, targetId)
        events.publishEvent(MembershipChanged(listId, targetId, false))
    }

    // ---- account deletion ----

    fun removeUser(userId: UUID) {
        val owned = jdbc.queryForList(
            "SELECT list_id FROM sharing.list_members WHERE user_id = ? AND role = 'OWNER'",
            UUID::class.java, userId,
        )
        owned.forEach {
            jdbc.update("DELETE FROM sharing.list_members WHERE list_id = ?", it)
            jdbc.update("DELETE FROM sharing.invitations WHERE list_id = ?", it)
        }
        jdbc.update("DELETE FROM sharing.list_members WHERE user_id = ?", userId)
        jdbc.update("DELETE FROM sharing.invitations WHERE created_by = ?", userId)
    }

    fun membershipsOf(userId: UUID): List<Map<String, Any?>> =
        jdbc.queryForList("SELECT list_id, role, joined_at FROM sharing.list_members WHERE user_id = ?", userId)

    private fun requireOwner(listId: UUID, userId: UUID) {
        when (roleOf(listId, userId)) {
            null -> throw ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "List not found")
            ListRole.MEMBER -> throw ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only the owner can do this")
            ListRole.OWNER -> Unit
        }
    }
}

@RestController
@RequestMapping("/api/v1")
class SharingController(private val sharing: SharingService) {
    @PostMapping("/lists/{listId}/invitations")
    @ResponseStatus(HttpStatus.CREATED)
    fun invite(@PathVariable listId: UUID): InvitationDto = sharing.createInvitation(listId, CurrentUser.id())

    @DeleteMapping("/lists/{listId}/invitations")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun revoke(@PathVariable listId: UUID) = sharing.revokeInvitations(listId, CurrentUser.id())

    @PostMapping("/invitations/{token}/accept")
    fun accept(@PathVariable token: String): JoinResult = sharing.accept(token, CurrentUser.id())

    @GetMapping("/lists/{listId}/members")
    fun members(@PathVariable listId: UUID): List<MemberDto> = sharing.members(listId, CurrentUser.id())

    @DeleteMapping("/lists/{listId}/members/{userId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun remove(@PathVariable listId: UUID, @PathVariable userId: UUID) = sharing.removeMember(listId, userId, CurrentUser.id())
}

@Component
class SharingAccountListener(private val sharing: SharingService) {
    @EventListener
    fun onUserDeleted(event: UserDeleted) {
        sharing.removeUser(event.userId)
    }
}

@Component
class SharingDataContributor(private val sharing: SharingService) : UserDataContributor {
    override fun exportKey(): String = "memberships"

    override fun exportData(userId: UUID): Any = sharing.membershipsOf(userId)
}
