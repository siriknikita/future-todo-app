package com.futuretodo.accounts.internal

import com.futuretodo.accounts.UserDataContributor
import com.futuretodo.accounts.UserDeleted
import com.futuretodo.accounts.UserDirectory
import com.futuretodo.shared.ApiException
import com.fasterxml.jackson.databind.ObjectMapper
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.ApplicationEventPublisher
import org.springframework.http.HttpStatus
import org.springframework.mail.SimpleMailMessage
import org.springframework.mail.javamail.JavaMailSender
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm
import org.springframework.security.oauth2.jwt.JwtDecoder
import org.springframework.security.oauth2.jwt.JwtException
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder
import org.springframework.stereotype.Component
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

// ---------- DTOs ----------

data class RegisterRequest(val email: String, val password: String, val displayName: String? = null)

data class LoginRequest(val email: String, val password: String, val deviceName: String? = null, val platform: String? = null)

data class OAuthRequest(val idToken: String, val deviceName: String? = null, val platform: String? = null)

data class RefreshRequest(val refreshToken: String)

data class TokenRequest(val token: String)

data class EmailRequest(val email: String)

data class ResetPasswordRequest(val token: String, val newPassword: String)

data class ChangePasswordRequest(val currentPassword: String, val newPassword: String)

data class UpdateProfileRequest(val displayName: String? = null, val photoUrl: String? = null)

data class UserProfile(
    val id: UUID,
    val email: String,
    val displayName: String,
    val photoUrl: String?,
    val emailVerified: Boolean,
    val role: String,
    val createdAt: OffsetDateTime,
)

data class TokenPair(
    val accessToken: String,
    val refreshToken: String,
    val expiresIn: Long,
    val sessionId: UUID,
    val user: UserProfile,
)

data class SessionDto(
    val id: UUID,
    val deviceName: String?,
    val platform: String?,
    val createdAt: OffsetDateTime,
    val lastUsedAt: OffsetDateTime,
    val current: Boolean,
)

fun UserRecord.toProfile() = UserProfile(id, email, displayName, photoUrl, emailVerified, role, createdAt)

// ---------- Mail ----------

@Service
class MailService(
    private val sender: JavaMailSender,
    @Value("\${app.mail.from:no-reply@futuretodo.local}") private val from: String,
    @Value("\${app.frontend-url:http://localhost:8081}") private val frontendUrl: String,
) {
    private val log = LoggerFactory.getLogger(MailService::class.java)

    fun sendVerification(to: String, token: String) =
        send(to, "Confirm your Future Todo email", "Confirm your email: $frontendUrl/verify-email?token=$token")

    fun sendPasswordReset(to: String, token: String) =
        send(to, "Reset your Future Todo password", "Reset your password: $frontendUrl/reset-password?token=$token")

    private fun send(to: String, subject: String, text: String) {
        log.info("Sending mail to={} subject='{}' body='{}'", to, subject, text)
        try {
            val message = SimpleMailMessage()
            message.from = from
            message.setTo(to)
            message.subject = subject
            message.text = text
            sender.send(message)
        } catch (e: Exception) {
            log.warn("Could not send mail to {}: {}", to, e.message)
        }
    }
}

// ---------- OIDC ----------

data class OidcIdentity(val subject: String, val email: String?, val name: String?)

interface OidcVerifier {
    fun verify(provider: String, idToken: String): OidcIdentity
}

@Component
class NimbusOidcVerifier(
    @Value("\${app.oauth.google.client-id:}") googleClientId: String,
    @Value("\${app.oauth.apple.client-id:}") appleClientId: String,
    @Value("\${app.oauth.microsoft.client-id:}") microsoftClientId: String,
) : OidcVerifier {
    private class Provider(val jwksUri: String, val issuers: Set<String>, val clientId: String)

    private val providers = mapOf(
        "google" to Provider(
            "https://www.googleapis.com/oauth2/v3/certs",
            setOf("https://accounts.google.com", "accounts.google.com"),
            googleClientId,
        ),
        "apple" to Provider("https://appleid.apple.com/auth/keys", setOf("https://appleid.apple.com"), appleClientId),
        "microsoft" to Provider(
            "https://login.microsoftonline.com/common/discovery/v2.0/keys",
            emptySet(),
            microsoftClientId,
        ),
    )
    private val decoders = ConcurrentHashMap<String, JwtDecoder>()

    override fun verify(provider: String, idToken: String): OidcIdentity {
        val config = providers[provider] ?: throw ApiException(HttpStatus.BAD_REQUEST, "UNKNOWN_PROVIDER", "Unknown provider")
        if (config.clientId.isBlank()) {
            throw ApiException(HttpStatus.NOT_IMPLEMENTED, "OAUTH_NOT_CONFIGURED", "Provider $provider is not configured")
        }
        val decoder = decoders.computeIfAbsent(provider) {
            NimbusJwtDecoder.withJwkSetUri(config.jwksUri).jwsAlgorithm(SignatureAlgorithm.RS256).build()
        }
        val jwt = try {
            decoder.decode(idToken)
        } catch (e: JwtException) {
            throw ApiException(HttpStatus.UNAUTHORIZED, "INVALID_ID_TOKEN", "ID token is invalid")
        }
        val issuerOk = config.issuers.isEmpty() || config.issuers.contains(jwt.issuer?.toString())
        val audienceOk = jwt.audience?.contains(config.clientId) == true
        if (!issuerOk || !audienceOk) {
            throw ApiException(HttpStatus.UNAUTHORIZED, "INVALID_ID_TOKEN", "ID token issuer or audience mismatch")
        }
        return OidcIdentity(jwt.subject, jwt.getClaimAsString("email"), jwt.getClaimAsString("name"))
    }
}

// ---------- Sessions ----------

@Service
class SessionService(
    private val sessions: SessionRepository,
    private val users: UserRepository,
    private val jwt: JwtService,
    @Value("\${app.jwt.refresh-ttl-days:30}") private val refreshTtlDays: Long,
) {
    private val random = SecureRandom()

    fun open(user: UserRecord, deviceName: String?, platform: String?): TokenPair {
        val sessionId = UUID.randomUUID()
        val refreshToken = newRefreshToken()
        sessions.insert(sessionId, user.id, hash(refreshToken), deviceName, platform, expiry())
        users.touchLastSeen(user.id)
        return pair(user, sessionId, refreshToken)
    }

    @Transactional
    fun refresh(refreshToken: String): TokenPair {
        val session = sessions.findByTokenHash(hash(refreshToken))
            ?: throw ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "Refresh token is invalid")
        if (session.expiresAt.isBefore(OffsetDateTime.now())) {
            sessions.delete(session.id, session.userId)
            throw ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "Refresh token expired")
        }
        val user = users.findById(session.userId)
            ?: throw ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "Refresh token is invalid")
        if (user.blocked) {
            throw ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_BLOCKED", "Account is blocked")
        }
        val newToken = newRefreshToken()
        sessions.rotate(session.id, hash(newToken), expiry())
        users.touchLastSeen(user.id)
        return pair(user, session.id, newToken)
    }

    fun logout(refreshToken: String) {
        sessions.deleteByTokenHash(hash(refreshToken))
    }

    fun list(userId: UUID, currentSession: UUID?): List<SessionDto> =
        sessions.listForUser(userId).map {
            SessionDto(it.id, it.deviceName, it.platform, it.createdAt, it.lastUsedAt, it.id == currentSession)
        }

    fun end(userId: UUID, sessionId: UUID) {
        if (sessions.delete(sessionId, userId) == 0) {
            throw ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "Session not found")
        }
    }

    fun endAll(userId: UUID) = sessions.deleteAllForUser(userId)

    private fun pair(user: UserRecord, sessionId: UUID, refreshToken: String) =
        TokenPair(jwt.issue(user.id, user.role, sessionId), refreshToken, jwt.expiresInSeconds, sessionId, user.toProfile())

    private fun expiry(): OffsetDateTime = OffsetDateTime.now(ZoneOffset.UTC).plusDays(refreshTtlDays)

    private fun newRefreshToken(): String {
        val bytes = ByteArray(32)
        random.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    companion object {
        fun hash(token: String): String =
            MessageDigest.getInstance("SHA-256").digest(token.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}

// ---------- Auth ----------

@Service
class AuthService(
    private val users: UserRepository,
    private val emailTokens: EmailTokenRepository,
    private val sessions: SessionService,
    private val encoder: PasswordEncoder,
    private val mail: MailService,
    private val limiter: LoginRateLimiter,
    private val oidc: OidcVerifier,
) {
    private val random = SecureRandom()
    private val emailRegex = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")

    @Transactional
    fun register(request: RegisterRequest, clientKey: String): UserProfile {
        limiter.check("register:$clientKey")
        val email = request.email.trim().lowercase()
        if (!emailRegex.matches(email)) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_EMAIL", "Email is not valid")
        }
        validatePassword(request.password)
        if (users.findByEmail(email) != null) {
            throw ApiException(HttpStatus.CONFLICT, "EMAIL_TAKEN", "Email is already registered")
        }
        val name = request.displayName?.trim().takeUnless { it.isNullOrEmpty() } ?: email.substringBefore("@")
        val user = UserRecord(
            UUID.randomUUID(),
            email,
            encoder.encode(request.password),
            name,
            null,
            false,
            "USER",
            false,
            "{}",
            OffsetDateTime.now(ZoneOffset.UTC),
            null,
        )
        users.insert(user)
        sendVerification(user)
        return user.toProfile()
    }

    fun resendVerification(email: String) {
        val user = users.findByEmail(email.trim().lowercase())
        if (user != null && !user.emailVerified) {
            sendVerification(user)
        }
    }

    @Transactional
    fun verifyEmail(token: String) {
        val record = emailTokens.find(token, KIND_VERIFY)
        if (record == null || record.used || record.expiresAt.isBefore(OffsetDateTime.now())) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_TOKEN", "Token is invalid or expired")
        }
        users.markVerified(record.userId)
        emailTokens.markUsed(token)
    }

    fun login(request: LoginRequest, clientKey: String): TokenPair {
        val email = request.email.trim().lowercase()
        limiter.check("login:$clientKey:$email")
        val user = users.findByEmail(email)
        val hash = user?.passwordHash
        if (user == null || hash == null || !encoder.matches(request.password, hash)) {
            throw ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Wrong email or password")
        }
        if (!user.emailVerified) {
            throw ApiException(HttpStatus.FORBIDDEN, "EMAIL_NOT_VERIFIED", "Confirm your email first")
        }
        if (user.blocked) {
            throw ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_BLOCKED", "Account is blocked")
        }
        return sessions.open(user, request.deviceName, request.platform)
    }

    fun refresh(refreshToken: String): TokenPair = sessions.refresh(refreshToken)

    fun logout(refreshToken: String) = sessions.logout(refreshToken)

    fun forgotPassword(email: String, clientKey: String) {
        limiter.check("forgot:$clientKey")
        val user = users.findByEmail(email.trim().lowercase()) ?: return
        val token = newToken()
        emailTokens.insert(token, user.id, KIND_RESET, OffsetDateTime.now(ZoneOffset.UTC).plusHours(1))
        mail.sendPasswordReset(user.email, token)
    }

    @Transactional
    fun resetPassword(token: String, newPassword: String) {
        validatePassword(newPassword)
        val record = emailTokens.find(token, KIND_RESET)
        if (record == null || record.used || record.expiresAt.isBefore(OffsetDateTime.now())) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_TOKEN", "Token is invalid or expired")
        }
        users.updatePassword(record.userId, encoder.encode(newPassword))
        users.markVerified(record.userId)
        emailTokens.markUsed(token)
        sessions.endAll(record.userId)
    }

    @Transactional
    fun oauthLogin(provider: String, request: OAuthRequest): TokenPair {
        val identity = oidc.verify(provider, request.idToken)
        val email = identity.email?.trim()?.lowercase()
            ?: throw ApiException(HttpStatus.BAD_REQUEST, "EMAIL_MISSING", "Provider did not return an email")
        var user = users.findByOAuth(provider, identity.subject)
        if (user == null) {
            user = users.findByEmail(email)
            if (user != null) {
                users.linkOAuth(user.id, provider, identity.subject)
            } else {
                val created = UserRecord(
                    UUID.randomUUID(),
                    email,
                    null,
                    identity.name ?: email.substringBefore("@"),
                    null,
                    true,
                    "USER",
                    false,
                    "{}",
                    OffsetDateTime.now(ZoneOffset.UTC),
                    null,
                )
                users.insert(created, provider, identity.subject)
                user = created
            }
        }
        if (user.blocked) {
            throw ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_BLOCKED", "Account is blocked")
        }
        return sessions.open(user, request.deviceName, request.platform)
    }

    private fun sendVerification(user: UserRecord) {
        val token = newToken()
        emailTokens.insert(token, user.id, KIND_VERIFY, OffsetDateTime.now(ZoneOffset.UTC).plusDays(2))
        mail.sendVerification(user.email, token)
    }

    private fun newToken(): String {
        val bytes = ByteArray(24)
        random.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    companion object {
        const val KIND_VERIFY = "VERIFY"
        const val KIND_RESET = "RESET"

        fun validatePassword(password: String) {
            if (password.length < 8) {
                throw ApiException(HttpStatus.BAD_REQUEST, "WEAK_PASSWORD", "Password must have at least 8 characters")
            }
        }
    }
}

// ---------- Profile, export, delete, admin ----------

data class AdminUser(
    val id: UUID,
    val email: String,
    val displayName: String,
    val role: String,
    val emailVerified: Boolean,
    val blocked: Boolean,
    val createdAt: OffsetDateTime,
    val lastSeenAt: OffsetDateTime?,
)

data class UserPage(val items: List<AdminUser>, val total: Long, val page: Int, val size: Int)

data class AdminStats(val totalUsers: Long, val blockedUsers: Long, val activeLast7Days: Long, val platforms: Map<String, Long>)

@Service
class AccountService(
    private val users: UserRepository,
    private val sessions: SessionRepository,
    private val encoder: PasswordEncoder,
    private val events: ApplicationEventPublisher,
    private val contributors: List<UserDataContributor>,
    private val mapper: ObjectMapper,
) {
    fun profile(userId: UUID): UserProfile = load(userId).toProfile()

    fun updateProfile(userId: UUID, request: UpdateProfileRequest): UserProfile {
        val user = load(userId)
        val name = request.displayName?.trim()
        if (name != null && name.isEmpty()) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_NAME", "Name must not be empty")
        }
        val photo = request.photoUrl
        if (photo != null && photo.length > 2048) {
            throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_PHOTO", "Photo url is too long")
        }
        users.updateProfile(userId, name ?: user.displayName, photo ?: user.photoUrl)
        return load(userId).toProfile()
    }

    fun changePassword(userId: UUID, request: ChangePasswordRequest) {
        val user = load(userId)
        val hash = user.passwordHash
        if (hash == null || !encoder.matches(request.currentPassword, hash)) {
            throw ApiException(HttpStatus.BAD_REQUEST, "WRONG_PASSWORD", "Current password is wrong")
        }
        AuthService.validatePassword(request.newPassword)
        users.updatePassword(userId, encoder.encode(request.newPassword))
    }

    @Suppress("UNCHECKED_CAST")
    fun settings(userId: UUID): Map<String, Any?> = mapper.readValue(load(userId).settings, Map::class.java) as Map<String, Any?>

    fun putSettings(userId: UUID, settings: Map<String, Any?>): Map<String, Any?> {
        users.updateSettings(userId, mapper.writeValueAsString(settings))
        return settings(userId)
    }

    fun export(userId: UUID): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>()
        result["profile"] = load(userId).toProfile()
        result["settings"] = settings(userId)
        contributors.forEach { result[it.exportKey()] = it.exportData(userId) }
        return result
    }

    @Transactional
    fun delete(userId: UUID) {
        load(userId)
        events.publishEvent(UserDeleted(userId))
        users.delete(userId)
    }

    // Admin (FR-11)

    fun adminUsers(query: String?, page: Int, size: Int): UserPage {
        val safeSize = size.coerceIn(1, 100)
        val safePage = page.coerceAtLeast(0)
        val items = users.search(query, safeSize, safePage * safeSize).map {
            AdminUser(it.id, it.email, it.displayName, it.role, it.emailVerified, it.blocked, it.createdAt, it.lastSeenAt)
        }
        return UserPage(items, users.countSearch(query), safePage, safeSize)
    }

    @Transactional
    fun setBlocked(userId: UUID, blocked: Boolean) {
        load(userId)
        users.setBlocked(userId, blocked)
        if (blocked) {
            sessions.deleteAllForUser(userId)
        }
    }

    fun stats(): AdminStats = AdminStats(
        users.countAll(),
        users.countBlocked(),
        users.countActiveSince(OffsetDateTime.now(ZoneOffset.UTC).minusDays(7)),
        sessions.platformCounts(),
    )

    private fun load(userId: UUID): UserRecord =
        users.findById(userId) ?: throw ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "User not found")
}

@Service
class UserDirectoryService(private val users: UserRepository) : UserDirectory {
    override fun displayNames(ids: Collection<UUID>): Map<UUID, String> = users.displayNames(ids)
}

/** Creates the first administrator from configuration (app.admin.email / app.admin.password). */
@Component
class AdminBootstrap(
    private val users: UserRepository,
    private val encoder: PasswordEncoder,
    @Value("\${app.admin.email:}") private val email: String,
    @Value("\${app.admin.password:}") private val password: String,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        if (email.isBlank() || password.isBlank() || users.findByEmail(email.lowercase()) != null) {
            return
        }
        users.insert(
            UserRecord(
                UUID.randomUUID(),
                email.lowercase(),
                encoder.encode(password),
                "Administrator",
                null,
                true,
                "ADMIN",
                false,
                "{}",
                OffsetDateTime.now(ZoneOffset.UTC),
                null,
            ),
        )
    }
}
