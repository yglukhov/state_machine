# Package

version       = "0.1.0"
author        = "Yuriy Glukhov"
description   = "State machines"
license       = "MIT"

# Dependencies

requires "nim >= 0.17.0"

task tests, "Run tests":
    exec "nim c -r state_machine"
    exec "nim js -r state_machine"
