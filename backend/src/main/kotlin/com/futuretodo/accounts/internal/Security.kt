package com.futuretodo.accounts.internal

import com.futuretodo.accounts.TokenVerifier
import com.futuretodo.shared.ApiException
import com.futuretodo.shared.AuthUser
import io.github.bucket4j.Bandwidth
import io.github.bucket4j.Bucket
import io.jsonwebtoken.JwtException
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.security.Keys
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.HttpStatusEntryPoint
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter
import org.springframework.stereotype.Component
import org.springframework.stereotype.Service
import org.springframework.web.cors.CorsConfiguration
import org.springframework.web.cors.CorsConfigurationSource
import org.springframework.web.cors.UrlBasedCorsConfigurationSource
import org.springframework.web.filter.OncePerRequestFilter
import java.time.Duration
import java.time.Instant
import java.util.Date
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.SecretKey

/** Issues and verifies the 15 minute HS256 access tokens. */
@Service
class JwtService(
    @Value("\${app.jwt.secret}") secret: String,
    @Value("\${app.jwt.access-ttl-minutes:15}") private val ttlMinutes: Long,
) : TokenVerifier {
    private val key: SecretKey = Keys.hmacShaKeyFor(secret.toByteArray())

    val expiresInSeconds: Long
        get() = ttlMinutes * 60

    fun issue(userId: UUID, role: String, sessionId: UUID): String {
        val now = Instant.now()
        return Jwts
            .builder()
            .subject(userId.toString())
            .claim("role", role)
            .claim("sid", sessionId.toString())
            .issuedAt(Date.from(now))
            .expiration(Date.from(now.plusSeconds(ttlMinutes * 60)))
            .signWith(key)
            .compact()
    }

    override fun verify(token: String): AuthUser? =
        try {
            val claims = Jwts
                .parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .payload
            AuthUser(
                UUID.fromString(claims.subject),
                claims.get("role", String::class.java),
                claims.get("sid", String::class.java)?.let { UUID.fromString(it) },
            )
        } catch (e: JwtException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        }
}

/** Bucket4j rate limiter for login and other sensitive endpoints. */
@Component
class LoginRateLimiter(
    @Value("\${app.rate-limit.attempts-per-minute:10}") private val perMinute: Long
) {
    private val buckets = ConcurrentHashMap<String, Bucket>()

    fun check(key: String) {
        val bucket = buckets.computeIfAbsent(key) {
            Bucket
                .builder()
                .addLimit(
                    Bandwidth
                        .builder()
                        .capacity(perMinute)
                        .refillIntervally(perMinute, Duration.ofMinutes(1))
                        .build()
                ).build()
        }
        if (!bucket.tryConsume(1)) {
            throw ApiException(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED", "Too many attempts, try again later")
        }
    }
}

class JwtAuthFilter(private val verifier: TokenVerifier) : OncePerRequestFilter() {
    override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, filterChain: FilterChain) {
        val header = request.getHeader("Authorization")
        if (header != null && header.startsWith("Bearer ")) {
            val user = verifier.verify(header.substring(7))
            if (user != null) {
                val authentication = UsernamePasswordAuthenticationToken(
                    user,
                    null,
                    listOf(SimpleGrantedAuthority("ROLE_" + user.role)),
                )
                SecurityContextHolder.getContext().authentication = authentication
            }
        }
        filterChain.doFilter(request, response)
    }
}

@Configuration
@EnableWebSecurity
class SecurityConfig(
    @Value("\${app.cors.allowed-origins:*}") private val origins: String
) {
    @Bean
    fun passwordEncoder(): PasswordEncoder = Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8()

    @Bean
    fun filterChain(http: HttpSecurity, jwtService: JwtService): SecurityFilterChain {
        http
            .csrf { it.disable() }
            .cors { it.configurationSource(corsConfigurationSource()) }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .exceptionHandling { it.authenticationEntryPoint(HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)) }
            .authorizeHttpRequests {
                it
                    .requestMatchers(
                        "/api/v1/auth/**",
                        "/api/v1/ws",
                        "/api/v1/ws/**",
                        "/v3/api-docs/**",
                        "/swagger-ui/**",
                        "/swagger-ui.html",
                        "/actuator/health/**",
                        "/actuator/health",
                        // Error dispatches carry no JWT (the filter runs once per request), so a 403
                        // forwarded to /error would otherwise turn into a 401.
                        "/error",
                    ).permitAll()
                    .requestMatchers("/api/v1/admin/**")
                    .hasRole("ADMIN")
                    .anyRequest()
                    .authenticated()
            }.addFilterBefore(JwtAuthFilter(jwtService), UsernamePasswordAuthenticationFilter::class.java)
        return http.build()
    }

    private fun corsConfigurationSource(): CorsConfigurationSource {
        val config = CorsConfiguration()
        config.allowedOriginPatterns = origins.split(",").map { it.trim() }
        config.allowedMethods = listOf("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
        config.allowedHeaders = listOf("*")
        val source = UrlBasedCorsConfigurationSource()
        source.registerCorsConfiguration("/**", config)
        return source
    }
}
