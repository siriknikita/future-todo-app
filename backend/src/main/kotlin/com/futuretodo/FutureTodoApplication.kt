package com.futuretodo

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class FutureTodoApplication

fun main(args: Array<String>) {
    runApplication<FutureTodoApplication>(*args)
}
