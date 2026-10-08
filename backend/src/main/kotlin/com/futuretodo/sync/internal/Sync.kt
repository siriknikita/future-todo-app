package com.futuretodo.sync.internal

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.futuretodo.accounts.TokenVerifier
import com.futuretodo.accounts.UserDeleted
import com.futuretodo.shared.ApiException
import com.futuretodo.shared.CurrentUser
import com.futuretodo.shared.FieldChange
import com.futuretodo.shared.HlcClock
import com.futuretodo.sharing.ListAccess
import com.futuretodo.sharing.MembershipChanged
import com.futuretodo.sync.RealtimeNotifier
import com.futuretodo.tasks.EntityChanged
import com.futuretodo.tasks.IncomingChange
import com.futuretodo.tasks.SyncChangeApplier
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Configuration
import org.springframework.context.event.EventListener
import org.springframework.http.HttpStatus
import org.springframework.http.server.ServerHttpRequest
import org.springframework.http.server.ServerHttpResponse
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Component
import org.springframework.stereotype.Repository
import org.springframework.stereotype.Service
import org.springframework.transaction.support.TransactionSynchronization
import org.springframework.transaction.support.TransactionSynchronizationManager
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.socket.CloseStatus
import org.springframework.web.socket.TextMessage
import org.springframework.web.socket.WebSocketHandler
import org.springframework.web.socket.WebSocketSession
import org.springframework.web.socket.config.annotation.EnableWebSocket
import org.springframework.web.socket.config.annotation.WebSocketConfigurer
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator
import org.springframework.web.socket.handler.TextWebSocketHandler
import org.springframework.web.socket.server.HandshakeInterceptor
import org.springframework.web.util.UriComponentsBuilder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

// ---------- DTOs ----------

data class PushChange(val entityType: String, val entityId: String, val fields: Map<String, FieldChange>)

data class PushRequest(val deviceId: String? = null, val changes: List<PushChange>)

data class Rejected(val entityId: String, val code: String, val message: String)

data class PushResult(val applied: Int, val rejected: List<Rejected>, val serverHlc: String)

data class SyncChange(val seq: Long, val entityType: String, val entityId: UUID, val deleted: Boolean, val payload: JsonNode)

data class PullResult(val changes: List<SyncChange>, val nextSeq: Long, val hasMore: Boolean, val accessibleListIds: Set<UUID>)

// ---------- Change log ----------

@Repository
class ChangeLogRepository(private val jdbc: NamedParameterJdbcTemplate, private val json: ObjectMapper) {
    fun append(entityType: String, entityId: UUID, listId: UUID?, actorId: UUID, deleted: Boolean, payload: String): Long =
        jdbc.queryForObject(
            "INSERT INTO sync.changes (entity_type, entity_id, list_id, actor_id, deleted, payload) " +
                "VALUES (:type, :id, :list, :actor, :deleted, :payload) RETURNING seq",
            MapSqlParameterSource()
                .addValue("type", entityType)
                .addValue("id", entityId)
                .addValue("list", listId)
                .addValue("actor", actorId)
                .addValue("deleted", deleted)
                .addValue("payload", payload),
            Long::class.javaObjectType,
        ) ?: 0L

    fun pull(userId: UUID, lists: Collection<UUID>, since: Long, limit: Int): List<SyncChange> {
        val listClause = if (lists.isEmpty()) "" else " OR list_id IN (:lists)"
        val params = MapSqlParameterSource().addValue("since", since).addValue("user", userId).addValue("limit", limit)
        if (lists.isNotEmpty()) {
            params.addValue("lists", lists)
        }
        return jdbc.query(
            "SELECT seq, entity_type, entity_id, deleted, payload FROM sync.changes " +
                "WHERE seq > :since AND ((actor_id = :user AND list_id IS NULL)$listClause) ORDER BY seq LIMIT :limit",
            params,
            RowMapper<SyncChange> { rs, _ ->
                SyncChange(
                    rs.getLong("seq"),
                    rs.getString("entity_type"),
                    rs.getObject("entity_id", UUID::class.java),
                    rs.getBoolean("deleted"),
                    json.readTree(rs.getString("payload")),
                )
            },
        )
    }

    /** Re-emits the latest state of every entity of a list, so that a new member receives it with a normal pull. */
    fun replayList(listId: UUID): Int =
        jdbc.update(
            "INSERT INTO sync.changes (entity_type, entity_id, list_id, actor_id, deleted, payload) " +
                "SELECT entity_type, entity_id, list_id, actor_id, deleted, payload FROM (" +
                "SELECT DISTINCT ON (entity_type, entity_id) * FROM sync.changes ORDER BY entity_type, entity_id, seq DESC" +
                ") latest WHERE latest.list_id = :list ORDER BY latest.seq",
            mapOf("list" to listId),
        )

    fun deleteByActor(userId: UUID) {
        jdbc.update("DELETE FROM sync.changes WHERE actor_id = :user", mapOf("user" to userId))
    }

    fun maxSeq(): Long =
        jdbc.queryForObject("SELECT coalesce(max(seq), 0) FROM sync.changes", emptyMap<String, Any>(), Long::class.javaObjectType) ?: 0L
}

// ---------- Real-time hub (WebSocket) ----------

@Component
class RealtimeHub(private val json: ObjectMapper) : TextWebSocketHandler(), RealtimeNotifier {
    private class Connection(val userId: UUID, val session: WebSocketSession)

    private val log = LoggerFactory.getLogger(RealtimeHub::class.java)
    private val connections = ConcurrentHashMap<String, Connection>()

    override fun afterConnectionEstablished(session: WebSocketSession) {
        val userId = session.attributes["userId"] as? UUID
        if (userId == null) {
            session.close(CloseStatus.NOT_ACCEPTABLE)
            return
        }
        connections[session.id] = Connection(userId, ConcurrentWebSocketSessionDecorator(session, SEND_TIME_LIMIT_MS, BUFFER_LIMIT))
    }

    override fun afterConnectionClosed(session: WebSocketSession, status: CloseStatus) {
        connections.remove(session.id)
    }

    override fun handleTextMessage(session: WebSocketSession, message: TextMessage) {
        if (message.payload.trim() == "ping") {
            connections[session.id]?.session?.sendMessage(TextMessage("pong"))
        }
    }

    override fun notifyUsers(userIds: Collection<UUID>, type: String, data: Map<String, Any?>) {
        sendAfterCommit(userIds, json.writeValueAsString(data + ("type" to type)))
    }

    fun sendAfterCommit(userIds: Collection<UUID>, message: String) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(object : TransactionSynchronization {
                override fun afterCommit() {
                    broadcast(userIds, message)
                }
            })
        } else {
            broadcast(userIds, message)
        }
    }

    fun connectionCount(): Int = connections.size

    private fun broadcast(userIds: Collection<UUID>, message: String) {
        val targets = userIds.toSet()
        connections.values.filter { it.userId in targets }.forEach {
            try {
                it.session.sendMessage(TextMessage(message))
            } catch (e: Exception) {
                log.debug("Could not send to websocket session: {}", e.message)
            }
        }
    }

    companion object {
        const val SEND_TIME_LIMIT_MS = 5000
        const val BUFFER_LIMIT = 65536
    }
}

class TokenHandshakeInterceptor(private val verifier: TokenVerifier) : HandshakeInterceptor {
    override fun beforeHandshake(
        request: ServerHttpRequest,
        response: ServerHttpResponse,
        wsHandler: WebSocketHandler,
        attributes: MutableMap<String, Any>,
    ): Boolean {
        val token = UriComponentsBuilder
            .fromUri(request.uri)
            .build()
            .queryParams
            .getFirst("token") ?: return false
        val user = verifier.verify(token) ?: return false
        attributes["userId"] = user.id
        return true
    }

    override fun afterHandshake(
        request: ServerHttpRequest,
        response: ServerHttpResponse,
        wsHandler: WebSocketHandler,
        exception: Exception?,
    ) {
        // nothing to do after the handshake
    }
}

@Configuration
@EnableWebSocket
class WebSocketConfig(private val hub: RealtimeHub, private val verifier: TokenVerifier) : WebSocketConfigurer {
    override fun registerWebSocketHandlers(registry: WebSocketHandlerRegistry) {
        registry
            .addHandler(hub, "/api/v1/ws")
            .addInterceptors(TokenHandshakeInterceptor(verifier))
            .setAllowedOriginPatterns("*")
    }
}

// ---------- Recording changes published by other modules ----------

@Component
class ChangeRecorder(
    private val repo: ChangeLogRepository,
    private val access: ListAccess,
    private val hub: RealtimeHub,
    private val json: ObjectMapper,
) {
    @EventListener
    fun onEntityChanged(event: EntityChanged) {
        val seq = repo.append(
            event.entityType,
            event.entityId,
            event.listId,
            event.actorId,
            event.deleted,
            json.writeValueAsString(event.payload),
        )
        val audience = if (event.listId != null) access.memberIds(event.listId) else setOf(event.actorId)
        hub.sendAfterCommit(audience, changesMessage(seq))
    }

    @EventListener
    fun onMembershipChanged(event: MembershipChanged) {
        if (event.joined) {
            repo.replayList(event.listId)
        }
        hub.sendAfterCommit(setOf(event.userId), changesMessage(repo.maxSeq()))
    }

    @EventListener
    fun onUserDeleted(event: UserDeleted) {
        repo.deleteByActor(event.userId)
    }

    private fun changesMessage(seq: Long) = "{\"type\":\"changes\",\"seq\":$seq}"
}

// ---------- Push / pull ----------

@Service
class SyncService(
    private val applier: SyncChangeApplier,
    private val access: ListAccess,
    private val repo: ChangeLogRepository,
    private val hlc: HlcClock,
) {
    fun push(userId: UUID, request: PushRequest): PushResult {
        var applied = 0
        val rejected = mutableListOf<Rejected>()
        request.changes.sortedBy { order(it.entityType) }.forEach { change ->
            try {
                val id = try {
                    UUID.fromString(change.entityId)
                } catch (e: IllegalArgumentException) {
                    throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_ID", "entityId must be a UUID")
                }
                if (change.fields.values.any { it.hlc.isBlank() }) {
                    throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_HLC", "Every field needs an hlc")
                }
                applier.apply(userId, IncomingChange(change.entityType, id, change.fields))
                applied++
            } catch (e: ApiException) {
                rejected.add(Rejected(change.entityId, e.code, e.message ?: ""))
            }
        }
        return PushResult(applied, rejected, hlc.next(request.deviceId ?: "server"))
    }

    fun pull(userId: UUID, since: Long, limit: Int): PullResult {
        val max = limit.coerceIn(1, MAX_PAGE)
        val lists = access.accessibleListIds(userId)
        val rows = repo.pull(userId, lists, since, max + 1)
        val page = rows.take(max)
        return PullResult(page, page.lastOrNull()?.seq ?: since, rows.size > max, lists)
    }

    private fun order(entityType: String): Int =
        when (entityType) {
            "group" -> 0
            "list" -> 1
            "task" -> 2
            "step" -> 3
            else -> 4
        }

    companion object {
        const val MAX_PAGE = 1000
    }
}

@RestController
@RequestMapping("/api/v1/sync")
class SyncController(private val sync: SyncService) {
    @PostMapping("/push")
    fun push(
        @RequestBody request: PushRequest
    ): PushResult = sync.push(CurrentUser.id(), request)

    @GetMapping("/pull")
    fun pull(
        @RequestParam(defaultValue = "0") since: Long,
        @RequestParam(defaultValue = "500") limit: Int
    ): PullResult =
        sync.pull(CurrentUser.id(), since, limit)
}
