package com.futuretodo.accounts.internal

import com.futuretodo.shared.CurrentUser
import jakarta.servlet.http.HttpServletRequest
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.util.UUID

@RestController
@RequestMapping("/api/v1/auth")
class AuthController(private val auth: AuthService) {
    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    fun register(@RequestBody request: RegisterRequest, http: HttpServletRequest): UserProfile =
        auth.register(request, http.remoteAddr)

    @PostMapping("/verify-email")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun verifyEmail(@RequestBody request: TokenRequest) = auth.verifyEmail(request.token)

    @PostMapping("/resend-verification")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun resend(@RequestBody request: EmailRequest) = auth.resendVerification(request.email)

    @PostMapping("/login")
    fun login(@RequestBody request: LoginRequest, http: HttpServletRequest): TokenPair = auth.login(request, http.remoteAddr)

    @PostMapping("/refresh")
    fun refresh(@RequestBody request: RefreshRequest): TokenPair = auth.refresh(request.refreshToken)

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun logout(@RequestBody request: RefreshRequest) = auth.logout(request.refreshToken)

    @PostMapping("/forgot-password")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun forgot(@RequestBody request: EmailRequest, http: HttpServletRequest) = auth.forgotPassword(request.email, http.remoteAddr)

    @PostMapping("/reset-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun reset(@RequestBody request: ResetPasswordRequest) = auth.resetPassword(request.token, request.newPassword)

    @PostMapping("/oauth/{provider}")
    fun oauth(@PathVariable provider: String, @RequestBody request: OAuthRequest): TokenPair = auth.oauthLogin(provider, request)
}

@RestController
@RequestMapping("/api/v1/me")
class MeController(private val accounts: AccountService, private val sessions: SessionService) {
    @GetMapping
    fun me(): UserProfile = accounts.profile(CurrentUser.id())

    @PatchMapping
    fun update(@RequestBody request: UpdateProfileRequest): UserProfile = accounts.updateProfile(CurrentUser.id(), request)

    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun delete() = accounts.delete(CurrentUser.id())

    @PostMapping("/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun changePassword(@RequestBody request: ChangePasswordRequest) = accounts.changePassword(CurrentUser.id(), request)

    @GetMapping("/settings")
    fun settings(): Map<String, Any?> = accounts.settings(CurrentUser.id())

    @PutMapping("/settings")
    fun putSettings(@RequestBody settings: Map<String, Any?>): Map<String, Any?> = accounts.putSettings(CurrentUser.id(), settings)

    @GetMapping("/sessions")
    fun listSessions(): List<SessionDto> {
        val user = CurrentUser.get()
        return sessions.list(user.id, user.sessionId)
    }

    @DeleteMapping("/sessions")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun endAll() = sessions.endAll(CurrentUser.id())

    @DeleteMapping("/sessions/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun end(@PathVariable id: UUID) = sessions.end(CurrentUser.id(), id)

    @GetMapping("/export")
    fun export(): Map<String, Any?> = accounts.export(CurrentUser.id())
}

@RestController
@RequestMapping("/api/v1/admin")
class AdminController(private val accounts: AccountService) {
    @GetMapping("/users")
    fun users(
        @RequestParam(required = false) query: String?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int,
    ): UserPage = accounts.adminUsers(query, page, size)

    @PostMapping("/users/{id}/block")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun block(@PathVariable id: UUID) = accounts.setBlocked(id, true)

    @PostMapping("/users/{id}/unblock")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun unblock(@PathVariable id: UUID) = accounts.setBlocked(id, false)

    @GetMapping("/stats")
    fun stats(): AdminStats = accounts.stats()
}
