package com.futuretodo.tasks.internal

import com.futuretodo.IntegrationTestBase
import com.futuretodo.shared.ApiException
import com.futuretodo.shared.FieldChange
import com.futuretodo.tasks.IncomingChange
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.http.HttpStatus
import java.time.LocalDate
import java.util.UUID

/** Integration tests: the tasks module (change engine + repository) against a real PostgreSQL. */
class TaskEngineIntegrationTest : IntegrationTestBase() {
    @Autowired
    lateinit var changes: ChangeService

    @Autowired
    lateinit var repo: TaskRepository

    private fun f(value: Any?, hlc: String) = FieldChange(value, hlc)

    private fun createList(owner: UUID, name: String = "Groceries"): UUID {
        val id = UUID.randomUUID()
        changes.apply(owner, IncomingChange("list", id, mapOf("name" to f(name, "001:00000:a"), "position" to f(1.0, "001:00000:a"))))
        return id
    }

    private fun createTask(owner: UUID, listId: UUID, title: String, extra: Map<String, FieldChange> = emptyMap()): UUID {
        val id = UUID.randomUUID()
        val fields = mapOf("listId" to f(listId.toString(), "001:00000:a"), "title" to f(title, "001:00000:a")) + extra
        changes.apply(owner, IncomingChange("task", id, fields))
        return id
    }

    private fun createStep(owner: UUID, taskId: UUID, title: String) {
        val fields = mapOf("taskId" to f(taskId.toString(), "001:00000:a"), "title" to f(title, "001:00000:a"))
        changes.apply(owner, IncomingChange("step", UUID.randomUUID(), fields))
    }

    @Test
    fun `task endpoint data is stored in postgres and read back`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(owner, listId, "Buy milk", mapOf("dueDate" to f("2026-10-10", "001:00000:a")))

        val task = repo.findTask(taskId)!!

        assertEquals("Buy milk", task.title)
        assertEquals(LocalDate.of(2026, 10, 10), task.dueDate)
        assertEquals(listId, task.listId)
        assertEquals(listOf(taskId), repo.tasksOfList(listId, true, "manual", false).map { it.id })
    }

    @Test
    fun `per field last write wins and edits to different fields both survive`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(owner, listId, "Original")

        changes.apply(owner, IncomingChange("task", taskId, mapOf("title" to f("Newer title", "010:00000:phone"))))
        // an older edit from a device that was offline: title loses, note wins (never set before)
        changes.apply(
            owner,
            IncomingChange(
                "task",
                taskId,
                mapOf("title" to f("Older title", "005:00000:laptop"), "note" to f("A note", "005:00000:laptop")),
            ),
        )

        val task = repo.findTask(taskId)!!
        assertEquals("Newer title", task.title)
        assertEquals("A note", task.note)
        assertEquals("010:00000:phone", task.clocks["title"])
        assertEquals("005:00000:laptop", task.clocks["note"])
    }

    @Test
    fun `delete is a tombstone that can be undone by a newer change`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(owner, listId, "Temp")

        changes.apply(owner, IncomingChange("task", taskId, mapOf("deleted" to f(true, "020:00000:a"))))
        assertTrue(repo.findTask(taskId)!!.deleted)
        assertTrue(repo.tasksOfList(listId, true, "manual", false).isEmpty())

        changes.apply(owner, IncomingChange("task", taskId, mapOf("deleted" to f(false, "021:00000:a"))))
        assertFalse(repo.findTask(taskId)!!.deleted)
    }

    @Test
    fun `completing a repeating task creates the next occurrence with copied steps`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(
            owner,
            listId,
            "Water plants",
            mapOf(
                "dueDate" to f("2026-10-04", "001:00000:a"),
                "repeatType" to f("DAILY", "001:00000:a"),
                "repeatInterval" to f(2, "001:00000:a"),
            ),
        )
        createStep(owner, taskId, "Fill can")

        changes.apply(owner, IncomingChange("task", taskId, mapOf("completed" to f(true, "030:00000:a"))))
        // the same completion arriving again must not create a second occurrence
        changes.apply(owner, IncomingChange("task", taskId, mapOf("completed" to f(true, "030:00000:a"))))

        val tasks = repo.tasksOfList(listId, true, "manual", false)
        assertEquals(2, tasks.size)
        val next = tasks.first { it.id != taskId }
        assertEquals(LocalDate.of(2026, 10, 6), next.dueDate)
        assertFalse(next.completed)
        assertEquals(listOf("Fill can"), repo.stepsOfTask(next.id).map { it.title })
    }

    @Test
    fun `a stranger cannot read or change someone elses list or task`() {
        val owner = UUID.randomUUID()
        val stranger = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(owner, listId, "Private")

        val e = assertThrows<ApiException> {
            changes.apply(stranger, IncomingChange("task", taskId, mapOf("title" to f("Hacked", "099:00000:x"))))
        }
        assertEquals(HttpStatus.NOT_FOUND, e.status)
        assertThrows<ApiException> {
            changes.apply(stranger, IncomingChange("task", UUID.randomUUID(), mapOf("listId" to f(listId.toString(), "001:00000:x"))))
        }
        assertEquals("Private", repo.findTask(taskId)!!.title)
    }

    @Test
    fun `assignee must be a member of the list`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(owner, listId, "Assign me")

        val e = assertThrows<ApiException> {
            changes.apply(owner, IncomingChange("task", taskId, mapOf("assigneeId" to f(UUID.randomUUID().toString(), "040:00000:a"))))
        }

        assertEquals("ASSIGNEE_NOT_MEMBER", e.code)
    }

    @Test
    fun `invalid values are rejected and unknown fields are ignored`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val taskId = createTask(owner, listId, "Valid")

        val e = assertThrows<ApiException> {
            changes.apply(owner, IncomingChange("task", taskId, mapOf("title" to f("x".repeat(300), "050:00000:a"))))
        }
        assertEquals("INVALID_FIELD", e.code)
        changes.apply(owner, IncomingChange("task", taskId, mapOf("bogus" to f("1", "050:00000:a"), "important" to f(true, "050:00000:a"))))

        assertTrue(repo.findTask(taskId)!!.important)
        assertNotNull(repo.findTask(taskId)!!.clocks["important"])
    }

    @Test
    fun `full text search finds tasks by title note and step`() {
        val owner = UUID.randomUUID()
        val listId = createList(owner)
        val marker = "zebra" + UUID
            .randomUUID()
            .toString()
            .take(6)
            .filter { it.isLetter() }
        val byTitle = createTask(owner, listId, "Feed the $marker")
        val byNote = createTask(owner, listId, "Other", mapOf("note" to f("remember $marker", "001:00000:a")))
        val byStep = createTask(owner, listId, "Third")
        createStep(owner, byStep, "buy $marker")

        val found = repo.search(setOf(listId), SearchQuery.toTsQuery(marker.take(marker.length - 1))!!, true).map { it.id }.toSet()

        assertEquals(setOf(byTitle, byNote, byStep), found)
    }
}
