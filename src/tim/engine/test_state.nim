# Shared test state for @test / assert
var gTestFailed* {.global.}: bool = false
var gTestLabel* {.global.}: string = ""
var gTestMsg* {.global.}: string = ""
