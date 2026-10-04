package com.futuretodo.sync

import java.util.UUID

/** Pushes a JSON message to the open WebSocket connections of the given users (after the current transaction commits). */
interface RealtimeNotifier {
    fun notifyUsers(userIds: Collection<UUID>, type: String, data: Map<String, Any?>)
}
