package com.futuretodo.tasks.internal

import com.futuretodo.accounts.UserDataContributor
import com.futuretodo.accounts.UserDeleted
import com.futuretodo.shared.ApiException
import com.futuretodo.shared.CurrentUser
import com.futuretodo.sharing.ListAccess
import org.springframework.context.event.EventListener
import org.springframework.format.annotation.DateTimeFormat
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.TemporalAdjusters
import java.util.UUID

private fun notFound(what: String) = ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "$what not found")

private fun requireText(body: Map<String, Any?>, key: String) {
    val value = body[key]
    if (value !is String || value.isBlank()) {
        throw ApiException(HttpStatus.BAD_REQUEST, "INVALID_FIELD", "$key is required")
    }
}

private fun withPosition(body: Map<String, Any?>): Map<String, Any?> =
    if (body.containsKey("position")) body else body + ("position" to System.currentTimeMillis().toDouble())

@RestController
@RequestMapping("/api/v1")
class ListController(
    private val changes: ChangeService,
    private val repo: TaskRepository,
    private val access: ListAccess,
) {
    @GetMapping("/list-groups")
    fun groups(): List<GroupDto> = repo.groupsOf(CurrentUser.id())

    @PostMapping("/list-groups")
    @ResponseStatus(HttpStatus.CREATED)
    fun createGroup(@RequestBody body: Map<String, Any?>): GroupDto {
        requireText(body, "name")
        val id = UUID.randomUUID()
        changes.writeRest(CurrentUser.id(), EntitySpecs.GROUP, id, withPosition(body))
        return repo.findGroup(id)!!
    }

    @PatchMapping("/list-groups/{id}")
    fun updateGroup(@PathVariable id: UUID, @RequestBody body: Map<String, Any?>): GroupDto {
        ownGroup(id)
        changes.writeRest(CurrentUser.id(), EntitySpecs.GROUP, id, body)
        return repo.findGroup(id)!!
    }

    @DeleteMapping("/list-groups/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteGroup(@PathVariable id: UUID) {
        val user = CurrentUser.id()
        ownGroup(id)
        repo.listsInGroup(id, user).forEach { changes.writeRest(user, EntitySpecs.LIST, it.id, mapOf("groupId" to null)) }
        changes.writeRest(user, EntitySpecs.GROUP, id, mapOf("deleted" to true))
    }

    @GetMapping("/lists")
    fun lists(): List<ListDto> = repo.listsByIds(access.accessibleListIds(CurrentUser.id()))

    @PostMapping("/lists")
    @ResponseStatus(HttpStatus.CREATED)
    fun createList(@RequestBody body: Map<String, Any?>): ListDto {
        requireText(body, "name")
        val id = UUID.randomUUID()
        changes.writeRest(CurrentUser.id(), EntitySpecs.LIST, id, withPosition(body))
        return repo.findList(id)!!
    }

    @GetMapping("/lists/{id}")
    fun getList(@PathVariable id: UUID): ListDto = visibleList(id)

    @PatchMapping("/lists/{id}")
    fun updateList(@PathVariable id: UUID, @RequestBody body: Map<String, Any?>): ListDto {
        visibleList(id)
        changes.writeRest(CurrentUser.id(), EntitySpecs.LIST, id, body)
        return repo.findList(id)!!
    }

    @DeleteMapping("/lists/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteList(@PathVariable id: UUID) {
        visibleList(id)
        changes.writeRest(CurrentUser.id(), EntitySpecs.LIST, id, mapOf("deleted" to true))
    }

    private fun ownGroup(id: UUID): GroupDto {
        val group = repo.findGroup(id)
        if (group == null || group.deleted || group.ownerId != CurrentUser.id()) {
            throw notFound("Group")
        }
        return group
    }

    private fun visibleList(id: UUID): ListDto {
        val list = repo.findList(id)
        if (list == null || list.deleted || access.roleOf(id, CurrentUser.id()) == null) {
            throw notFound("List")
        }
        return list
    }
}

@RestController
@RequestMapping("/api/v1")
class TaskController(
    private val changes: ChangeService,
    private val repo: TaskRepository,
    private val access: ListAccess,
) {
    @GetMapping("/lists/{listId}/tasks")
    fun tasks(
        @PathVariable listId: UUID,
        @RequestParam(defaultValue = "manual") sort: String,
        @RequestParam(defaultValue = "asc") order: String,
        @RequestParam(defaultValue = "true") showCompleted: Boolean,
    ): List<TaskDto> {
        visibleList(listId)
        return repo.withSteps(repo.tasksOfList(listId, showCompleted, sort, order == "desc"))
    }

    @PostMapping("/lists/{listId}/tasks")
    @ResponseStatus(HttpStatus.CREATED)
    fun createTask(@PathVariable listId: UUID, @RequestBody body: Map<String, Any?>): TaskDto {
        visibleList(listId)
        requireText(body, "title")
        val id = UUID.randomUUID()
        changes.writeRest(CurrentUser.id(), EntitySpecs.TASK, id, withPosition(body) + ("listId" to listId.toString()))
        return withSteps(repo.findTask(id)!!)
    }

    @GetMapping("/tasks/{id}")
    fun getTask(@PathVariable id: UUID): TaskDto = withSteps(visibleTask(id, false))

    @PatchMapping("/tasks/{id}")
    fun updateTask(@PathVariable id: UUID, @RequestBody body: Map<String, Any?>): TaskDto {
        visibleTask(id, true)
        val data = body.toMutableMap()
        if (data.containsKey("completed") && !data.containsKey("completedAt")) {
            data["completedAt"] = if (data["completed"] == true) changes.nowUtc().toString() else null
        }
        changes.writeRest(CurrentUser.id(), EntitySpecs.TASK, id, data)
        return withSteps(repo.findTask(id)!!)
    }

    @DeleteMapping("/tasks/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteTask(@PathVariable id: UUID) {
        visibleTask(id, false)
        changes.writeRest(CurrentUser.id(), EntitySpecs.TASK, id, mapOf("deleted" to true))
    }

    @GetMapping("/tasks/{taskId}/steps")
    fun steps(@PathVariable taskId: UUID): List<StepDto> {
        visibleTask(taskId, false)
        return repo.stepsOfTask(taskId)
    }

    @PostMapping("/tasks/{taskId}/steps")
    @ResponseStatus(HttpStatus.CREATED)
    fun createStep(@PathVariable taskId: UUID, @RequestBody body: Map<String, Any?>): StepDto {
        visibleTask(taskId, false)
        requireText(body, "title")
        val id = UUID.randomUUID()
        changes.writeRest(CurrentUser.id(), EntitySpecs.STEP, id, withPosition(body) + ("taskId" to taskId.toString()))
        return repo.findStep(id)!!
    }

    @PatchMapping("/steps/{id}")
    fun updateStep(@PathVariable id: UUID, @RequestBody body: Map<String, Any?>): StepDto {
        visibleStep(id)
        changes.writeRest(CurrentUser.id(), EntitySpecs.STEP, id, body - "taskId")
        return repo.findStep(id)!!
    }

    @DeleteMapping("/steps/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteStep(@PathVariable id: UUID) {
        visibleStep(id)
        changes.writeRest(CurrentUser.id(), EntitySpecs.STEP, id, mapOf("deleted" to true))
    }

    private fun withSteps(task: TaskDto): TaskDto = task.copy(steps = repo.stepsOfTask(task.id))

    private fun visibleList(listId: UUID) {
        val list = repo.findList(listId)
        if (list == null || list.deleted || access.roleOf(listId, CurrentUser.id()) == null) {
            throw notFound("List")
        }
    }

    private fun visibleTask(id: UUID, allowDeleted: Boolean): TaskDto {
        val task = repo.findTask(id)
        if (task == null || (task.deleted && !allowDeleted) || access.roleOf(task.listId, CurrentUser.id()) == null) {
            throw notFound("Task")
        }
        return task
    }

    private fun visibleStep(id: UUID): StepDto {
        val step = repo.findStep(id)
        if (step == null || step.deleted) {
            throw notFound("Step")
        }
        visibleTask(step.taskId, false)
        return step
    }
}

object SmartLists {
    fun bucketOf(due: LocalDate, today: LocalDate): String {
        val endOfWeek = today.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY))
        return when {
            due.isBefore(today) -> "overdue"
            due == today -> "today"
            due == today.plusDays(1) -> "tomorrow"
            !due.isAfter(endOfWeek) -> "thisWeek"
            else -> "later"
        }
    }

    fun group(tasks: List<TaskDto>, today: LocalDate): Map<String, List<TaskDto>> {
        val result = linkedMapOf<String, List<TaskDto>>()
        val buckets = tasks.groupBy { bucketOf(it.dueDate!!, today) }
        listOf("overdue", "today", "tomorrow", "thisWeek", "later").forEach { result[it] = buckets[it] ?: emptyList() }
        return result
    }
}

@RestController
@RequestMapping("/api/v1")
class SmartListController(private val repo: TaskRepository, private val access: ListAccess) {
    @GetMapping("/smart-lists/{type}")
    fun smartList(
        @PathVariable type: String,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) today: LocalDate?,
    ): SmartListResponse {
        val user = CurrentUser.id()
        val day = today ?: LocalDate.now(ZoneOffset.UTC)
        val lists = access.accessibleListIds(user)
        val params = mapOf("today" to day, "user" to user)
        val ownOrAssigned = "(l.owner_id = :user OR t.assignee_id = :user)"
        return when (type) {
            "my-day" -> response(type, repo.smart(lists, "t.my_day_date = :today AND $ownOrAssigned", params, "t.position, t.created_at"))
            "important" -> response(type, repo.smart(lists, "t.important", params, "t.completed, t.created_at DESC"))
            "planned" -> {
                val planned = repo.smart(lists, "t.due_date IS NOT NULL AND NOT t.completed", params, "t.due_date, t.created_at")
                val tasks = repo.withSteps(planned)
                SmartListResponse(type, tasks, SmartLists.group(tasks, day))
            }
            "assigned-to-me" -> response(type, repo.smart(lists, "t.assignee_id = :user", params, "t.completed, t.created_at DESC"))
            "all" -> response(type, repo.smart(lists, "TRUE", params, "t.created_at DESC"))
            "completed" -> response(type, repo.smart(lists, "t.completed", params, "t.completed_at DESC NULLS LAST"))
            else -> throw notFound("Smart list")
        }
    }

    @GetMapping("/smart-lists/my-day/suggestions")
    fun suggestions(
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) today: LocalDate?,
    ): List<TaskDto> {
        val user = CurrentUser.id()
        val day = today ?: LocalDate.now(ZoneOffset.UTC)
        val condition = "NOT t.completed AND (t.my_day_date IS NULL OR t.my_day_date <> :today) " +
            "AND (t.due_date <= :today OR t.my_day_date < :today) AND (l.owner_id = :user OR t.assignee_id = :user)"
        val lists = access.accessibleListIds(user)
        return repo.withSteps(repo.smart(lists, condition, mapOf("today" to day, "user" to user), "t.due_date NULLS LAST"))
    }

    @GetMapping("/search")
    fun search(@RequestParam q: String, @RequestParam(defaultValue = "false") includeCompleted: Boolean): List<TaskDto> {
        val query = SearchQuery.toTsQuery(q) ?: return emptyList()
        return repo.withSteps(repo.search(access.accessibleListIds(CurrentUser.id()), query, includeCompleted))
    }

    private fun response(type: String, tasks: List<TaskDto>) = SmartListResponse(type, repo.withSteps(tasks))
}

@Component
class TasksAccountListener(private val repo: TaskRepository) {
    @EventListener
    fun onUserDeleted(event: UserDeleted) {
        repo.deleteAllOf(event.userId)
    }
}

@Component
class TasksDataContributor(private val repo: TaskRepository) : UserDataContributor {
    override fun exportKey(): String = "tasks"

    override fun exportData(userId: UUID): Any = repo.exportFor(userId)
}
