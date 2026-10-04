package com.futuretodo.accounts.internal

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Repository
import java.time.OffsetDateTime
import java.util.UUID

data class UserRecord(
    val id: UUID,
    val email: String,
    val passwordHash: String?,
    val displayName: String,
    val photoUrl: String?,
    val emailVerified: Boolean,
    val role: String,
    val blocked: Boolean,
    val settings: String,
    val createdAt: OffsetDateTime,
    val lastSeenAt: OffsetDateTime?,
)

data class SessionRecord(
    val id: UUID,
    val userId: UUID,
    val deviceName: String?,
    val platform: String?,
    val createdAt: OffsetDateTime,
    val lastUsedAt: OffsetDateTime,
    val expiresAt: OffsetDateTime,
)

data class EmailTokenRecord(
    val token: String,
    val userId: UUID,
    val kind: String,
    val expiresAt: OffsetDateTime,
    val used: Boolean,
)

@Repository
class UserRepository(private val jdbc: JdbcTemplate) {
    private val mapper = RowMapper<UserRecord> { rs, _ ->
        UserRecord(
            id = rs.getObject("id", UUID::class.java),
            email = rs.getString("email"),
            passwordHash = rs.getString("password_hash"),
            displayName = rs.getString("display_name"),
            photoUrl = rs.getString("photo_url"),
            emailVerified = rs.getBoolean("email_verified"),
            role = rs.getString("role"),
            blocked = rs.getBoolean("blocked"),
            settings = rs.getString("settings"),
            createdAt = rs.getObject("created_at", OffsetDateTime::class.java),
            lastSeenAt = rs.getObject("last_seen_at", OffsetDateTime::class.java),
        )
    }

    fun insert(user: UserRecord, oauthProvider: String? = null, oauthSubject: String? = null) {
        jdbc.update(
            "INSERT INTO accounts.users (id, email, password_hash, display_name, photo_url, email_verified, role, " +
                "oauth_provider, oauth_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            user.id, user.email, user.passwordHash, user.displayName, user.photoUrl, user.emailVerified, user.role,
            oauthProvider, oauthSubject,
        )
    }

    fun findById(id: UUID): UserRecord? =
        jdbc.query("SELECT * FROM accounts.users WHERE id = ?", mapper, id).firstOrNull()

    fun findByEmail(email: String): UserRecord? =
        jdbc.query("SELECT * FROM accounts.users WHERE email = ?", mapper, email).firstOrNull()

    fun findByOAuth(provider: String, subject: String): UserRecord? =
        jdbc.query("SELECT * FROM accounts.users WHERE oauth_provider = ? AND oauth_subject = ?", mapper, provider, subject)
            .firstOrNull()

    fun linkOAuth(id: UUID, provider: String, subject: String) {
        jdbc.update(
            "UPDATE accounts.users SET oauth_provider = ?, oauth_subject = ?, email_verified = true WHERE id = ?",
            provider, subject, id,
        )
    }

    fun markVerified(id: UUID) {
        jdbc.update("UPDATE accounts.users SET email_verified = true WHERE id = ?", id)
    }

    fun updatePassword(id: UUID, hash: String) {
        jdbc.update("UPDATE accounts.users SET password_hash = ? WHERE id = ?", hash, id)
    }

    fun updateProfile(id: UUID, displayName: String, photoUrl: String?) {
        jdbc.update("UPDATE accounts.users SET display_name = ?, photo_url = ? WHERE id = ?", displayName, photoUrl, id)
    }

    fun updateSettings(id: UUID, settings: String) {
        jdbc.update("UPDATE accounts.users SET settings = ? WHERE id = ?", settings, id)
    }

    fun setBlocked(id: UUID, blocked: Boolean) {
        jdbc.update("UPDATE accounts.users SET blocked = ? WHERE id = ?", blocked, id)
    }

    fun touchLastSeen(id: UUID) {
        jdbc.update("UPDATE accounts.users SET last_seen_at = now() WHERE id = ?", id)
    }

    fun delete(id: UUID) {
        jdbc.update("DELETE FROM accounts.users WHERE id = ?", id)
    }

    fun search(query: String?, limit: Int, offset: Int): List<UserRecord> {
        val like = "%" + (query ?: "").lowercase() + "%"
        return jdbc.query(
            "SELECT * FROM accounts.users WHERE lower(email) LIKE ? OR lower(display_name) LIKE ? " +
                "ORDER BY created_at DESC LIMIT ? OFFSET ?",
            mapper, like, like, limit, offset,
        )
    }

    fun countSearch(query: String?): Long {
        val like = "%" + (query ?: "").lowercase() + "%"
        return jdbc.queryForObject(
            "SELECT count(*) FROM accounts.users WHERE lower(email) LIKE ? OR lower(display_name) LIKE ?",
            Long::class.javaObjectType, like, like,
        ) ?: 0L
    }

    fun countAll(): Long = jdbc.queryForObject("SELECT count(*) FROM accounts.users", Long::class.javaObjectType) ?: 0L

    fun countBlocked(): Long =
        jdbc.queryForObject("SELECT count(*) FROM accounts.users WHERE blocked", Long::class.javaObjectType) ?: 0L

    fun countActiveSince(since: OffsetDateTime): Long =
        jdbc.queryForObject(
            "SELECT count(*) FROM accounts.users WHERE last_seen_at >= ?",
            Long::class.javaObjectType, since,
        ) ?: 0L

    fun displayNames(ids: Collection<UUID>): Map<UUID, String> {
        if (ids.isEmpty()) {
            return emptyMap()
        }
        val placeholders = ids.joinToString(",") { "?" }
        val rows = jdbc.query(
            "SELECT id, display_name FROM accounts.users WHERE id IN ($placeholders)",
            RowMapper<Pair<UUID, String>> { rs, _ -> Pair(rs.getObject("id", UUID::class.java), rs.getString("display_name")) },
            *ids.toTypedArray(),
        )
        return rows.toMap()
    }
}

@Repository
class SessionRepository(private val jdbc: JdbcTemplate) {
    private val mapper = RowMapper<SessionRecord> { rs, _ ->
        SessionRecord(
            id = rs.getObject("id", UUID::class.java),
            userId = rs.getObject("user_id", UUID::class.java),
            deviceName = rs.getString("device_name"),
            platform = rs.getString("platform"),
            createdAt = rs.getObject("created_at", OffsetDateTime::class.java),
            lastUsedAt = rs.getObject("last_used_at", OffsetDateTime::class.java),
            expiresAt = rs.getObject("expires_at", OffsetDateTime::class.java),
        )
    }

    fun insert(id: UUID, userId: UUID, tokenHash: String, deviceName: String?, platform: String?, expiresAt: OffsetDateTime) {
        jdbc.update(
            "INSERT INTO accounts.sessions (id, user_id, token_hash, device_name, platform, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
            id, userId, tokenHash, deviceName, platform, expiresAt,
        )
    }

    fun findByTokenHash(hash: String): SessionRecord? =
        jdbc.query("SELECT * FROM accounts.sessions WHERE token_hash = ?", mapper, hash).firstOrNull()

    fun rotate(id: UUID, newHash: String, expiresAt: OffsetDateTime) {
        jdbc.update(
            "UPDATE accounts.sessions SET token_hash = ?, expires_at = ?, last_used_at = now() WHERE id = ?",
            newHash, expiresAt, id,
        )
    }

    fun listForUser(userId: UUID): List<SessionRecord> =
        jdbc.query("SELECT * FROM accounts.sessions WHERE user_id = ? AND expires_at > now() ORDER BY created_at DESC", mapper, userId)

    fun delete(id: UUID, userId: UUID): Int = jdbc.update("DELETE FROM accounts.sessions WHERE id = ? AND user_id = ?", id, userId)

    fun deleteByTokenHash(hash: String) {
        jdbc.update("DELETE FROM accounts.sessions WHERE token_hash = ?", hash)
    }

    fun deleteAllForUser(userId: UUID) {
        jdbc.update("DELETE FROM accounts.sessions WHERE user_id = ?", userId)
    }

    fun platformCounts(): Map<String, Long> {
        val rows = jdbc.query(
            "SELECT coalesce(platform, 'unknown') AS p, count(*) AS c FROM accounts.sessions GROUP BY 1",
            RowMapper<Pair<String, Long>> { rs, _ -> Pair(rs.getString("p"), rs.getLong("c")) },
        )
        return rows.toMap()
    }
}

@Repository
class EmailTokenRepository(private val jdbc: JdbcTemplate) {
    private val mapper = RowMapper<EmailTokenRecord> { rs, _ ->
        EmailTokenRecord(
            token = rs.getString("token"),
            userId = rs.getObject("user_id", UUID::class.java),
            kind = rs.getString("kind"),
            expiresAt = rs.getObject("expires_at", OffsetDateTime::class.java),
            used = rs.getBoolean("used"),
        )
    }

    fun insert(token: String, userId: UUID, kind: String, expiresAt: OffsetDateTime) {
        jdbc.update(
            "INSERT INTO accounts.email_tokens (token, user_id, kind, expires_at) VALUES (?, ?, ?, ?)",
            token, userId, kind, expiresAt,
        )
    }

    fun find(token: String, kind: String): EmailTokenRecord? =
        jdbc.query("SELECT * FROM accounts.email_tokens WHERE token = ? AND kind = ?", mapper, token, kind).firstOrNull()

    fun markUsed(token: String) {
        jdbc.update("UPDATE accounts.email_tokens SET used = true WHERE token = ?", token)
    }
}
