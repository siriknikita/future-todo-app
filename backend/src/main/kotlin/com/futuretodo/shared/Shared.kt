package com.futuretodo.shared

import org.springframework.beans.factory.annotation.Autowired
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Component
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID

class ApiException(val status: HttpStatus, val code: String, message: String) : RuntimeException(message)

data class ErrorResponse(val code: String, val message: String)

@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(ApiException::class)
    fun handleApi(e: ApiException): ResponseEntity<ErrorResponse> =
        ResponseEntity.status(e.status).body(ErrorResponse(e.code, e.message ?: ""))

    @ExceptionHandler(HttpMessageNotReadableException::class)
    fun handleBadBody(): ResponseEntity<ErrorResponse> =
        ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ErrorResponse("BAD_REQUEST", "Malformed or incomplete request body"))

    @ExceptionHandler(MethodArgumentTypeMismatchException::class)
    fun handleBadParam(e: MethodArgumentTypeMismatchException): ResponseEntity<ErrorResponse> =
        ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ErrorResponse("BAD_REQUEST", "Invalid parameter ${e.name}"))
}

/** Account roles as stored in the database and carried in the access token. */
object Roles {
    const val USER = "USER"
    const val ADMIN = "ADMIN"
}

/** Identity of the caller, stored as the principal of the Spring Security authentication. */
data class AuthUser(val id: UUID, val role: String, val sessionId: UUID?) {
    fun isAdmin(): Boolean = role == Roles.ADMIN
}

object CurrentUser {
    fun get(): AuthUser {
        val principal = SecurityContextHolder.getContext().authentication?.principal
        if (principal is AuthUser) {
            return principal
        }
        throw ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Authentication required")
    }

    fun id(): UUID = get().id
}

/** Random secrets that travel in URLs and JSON: Base64url without padding, from a cryptographically strong generator. */
object SecureTokens {
    /** Refresh tokens: 256 bits. */
    const val REFRESH_TOKEN_BYTES = 32

    /** Single-use email verification and password reset tokens: 192 bits. */
    const val EMAIL_TOKEN_BYTES = 24

    /** List invitation links: 192 bits. */
    const val INVITATION_TOKEN_BYTES = 24

    private val random = SecureRandom()
    private val encoder = Base64.getUrlEncoder().withoutPadding()

    fun urlSafe(bytes: Int): String {
        val buffer = ByteArray(bytes)
        random.nextBytes(buffer)
        return encoder.encodeToString(buffer)
    }
}

/** One field edit: the new value plus the hybrid logical clock of the edit. */
data class FieldChange(val value: Any?, val hlc: String)

object Lww {
    /** Per-field last-write-wins: keep only the incoming fields whose clock is newer than the stored one. */
    fun accepted(existing: Map<String, String>, incoming: Map<String, FieldChange>): Map<String, FieldChange> =
        incoming.filter { (name, change) ->
            val current = existing[name]
            current == null || change.hlc > current
        }
}

/**
 * Hybrid logical clock of the server. Format: 15-digit millis, 5-digit counter, device id.
 * Plain string comparison orders the values correctly.
 */
@Component
class HlcClock(private val now: () -> Long) {
    @Autowired
    constructor() : this({ System.currentTimeMillis() })

    private var lastMillis = 0L
    private var counter = 0

    @Synchronized
    fun next(deviceId: String = "server"): String {
        val physical = now()
        if (physical > lastMillis) {
            lastMillis = physical
            counter = 0
        } else {
            counter++
        }
        return format(lastMillis, counter, deviceId)
    }

    companion object {
        fun format(millis: Long, counter: Int, deviceId: String): String = "%015d:%05d:%s".format(millis, counter, deviceId)
    }
}
