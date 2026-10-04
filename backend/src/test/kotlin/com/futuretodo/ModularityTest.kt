package com.futuretodo

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.springframework.modulith.core.ApplicationModules

class ModularityTest {
    private val modules = ApplicationModules.of(FutureTodoApplication::class.java)

    @Test
    fun `module boundaries are respected and there are no cycles`() {
        modules.verify()
    }

    @Test
    fun `every business module is detected`() {
        listOf("accounts", "tasks", "sharing", "sync", "notifications").forEach {
            assertTrue(modules.getModuleByName(it).isPresent, "module $it not found")
        }
    }
}
