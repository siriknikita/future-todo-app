package com.futuretodo.sync.internal

import com.futuretodo.IntegrationTestBase
import com.futuretodo.shared.FieldChange
import com.futuretodo.sharing.internal.SharingService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import java.util.UUID

/** Integration tests: sync push/pull through the tasks and sharing modules against PostgreSQL. */
class SyncIntegrationTest : IntegrationTestBase() {
    @Autowired
    lateinit var sync: SyncService

    @Autowired
    lateinit var sharing: SharingService

    private fun change(type: String, id: UUID, hlc: String, vararg fields: Pair<String, Any?>) =
        PushChange(type, id.toString(), fields.associate { it.first to FieldChange(it.second, hlc) })

    @Test
    fun `offline changes are pushed and pulled with a cursor`() {
        val user = UUID.randomUUID()
        val listId = UUID.randomUUID()
        val taskId = UUID.randomUUID()

        val result = sync.push(
            user,
            PushRequest(
                "dev1",
                listOf(
                    // the task comes first on purpose: the server orders lists before tasks
                    change("task", taskId, "100:00000:dev1", "listId" to listId.toString(), "title" to "Offline task"),
                    change("list", listId, "100:00000:dev1", "name" to "Offline list"),
                ),
            ),
        )

        assertEquals(2, result.applied)
        assertTrue(result.rejected.isEmpty())
        val first = sync.pull(user, 0, 500)
        assertEquals(listOf("list", "task"), first.changes.map { it.entityType })
        assertEquals("Offline task", first.changes[1].payload["title"].asText())
        assertEquals("100:00000:dev1", first.changes[1].payload["clocks"]["title"].asText())
        assertTrue(first.accessibleListIds.contains(listId))
        assertFalse(first.hasMore)

        val second = sync.pull(user, first.nextSeq, 500)
        assertTrue(second.changes.isEmpty())
    }

    @Test
    fun `conflicting pushes from two devices resolve per field`() {
        val user = UUID.randomUUID()
        val listId = UUID.randomUUID()
        val taskId = UUID.randomUUID()
        sync.push(
            user,
            PushRequest(
                "dev1",
                listOf(
                    change("list", listId, "100:00000:dev1", "name" to "L"),
                    change("task", taskId, "100:00000:dev1", "listId" to listId.toString(), "title" to "T"),
                ),
            ),
        )

        sync.push(user, PushRequest("dev2", listOf(change("task", taskId, "300:00000:dev2", "title" to "From dev2", "important" to true))))
        sync.push(user, PushRequest("dev1", listOf(change("task", taskId, "200:00000:dev1", "title" to "From dev1", "note" to "n1"))))

        val last = sync.pull(user, 0, 500).changes.last { it.entityId == taskId }.payload
        assertEquals("From dev2", last["title"].asText())
        assertTrue(last["important"].asBoolean())
        assertEquals("n1", last["note"].asText())
    }

    @Test
    fun `invalid changes are rejected without blocking the others`() {
        val user = UUID.randomUUID()
        val listId = UUID.randomUUID()

        val result = sync.push(
            user,
            PushRequest(
                null,
                listOf(
                    change("list", listId, "100:00000:d", "name" to "Fine"),
                    PushChange("task", "not-a-uuid", mapOf("title" to FieldChange("x", "1"))),
                    change("nonsense", UUID.randomUUID(), "100:00000:d", "a" to "b"),
                    change("task", UUID.randomUUID(), "100:00000:d", "listId" to UUID.randomUUID().toString(), "title" to "Orphan"),
                ),
            ),
        )

        assertEquals(1, result.applied)
        assertEquals(setOf("INVALID_ID", "UNKNOWN_ENTITY", "NOT_FOUND"), result.rejected.map { it.code }.toSet())
    }

    @Test
    fun `a member who joins later receives the existing state of the shared list`() {
        val owner = UUID.randomUUID()
        val guest = UUID.randomUUID()
        val listId = UUID.randomUUID()
        val taskId = UUID.randomUUID()
        sync.push(
            owner,
            PushRequest(
                "d",
                listOf(
                    change("list", listId, "100:00000:d", "name" to "Shared"),
                    change("task", taskId, "100:00000:d", "listId" to listId.toString(), "title" to "Shared task"),
                ),
            ),
        )
        assertTrue(sync.pull(guest, 0, 500).changes.isEmpty())

        val invitation = sharing.createInvitation(listId, owner)
        sharing.accept(invitation.token, guest)

        val pulled = sync.pull(guest, 0, 500)
        assertEquals(setOf(listId, taskId), pulled.changes.map { it.entityId }.toSet())
        assertTrue(pulled.accessibleListIds.contains(listId))

        // after being removed the guest no longer sees the list in accessibleListIds
        sharing.removeMember(listId, guest, owner)
        assertFalse(sync.pull(guest, 0, 500).accessibleListIds.contains(listId))
    }

    @Test
    fun `pull pages through large change sets`() {
        val user = UUID.randomUUID()
        val listId = UUID.randomUUID()
        val changes = mutableListOf(change("list", listId, "100:00000:d", "name" to "Big"))
        repeat(5) { changes.add(change("task", UUID.randomUUID(), "100:00000:d", "listId" to listId.toString(), "title" to "t$it")) }
        sync.push(user, PushRequest("d", changes))

        val page = sync.pull(user, 0, 4)

        assertEquals(4, page.changes.size)
        assertTrue(page.hasMore)
        assertEquals(2, sync.pull(user, page.nextSeq, 4).changes.size)
    }
}
