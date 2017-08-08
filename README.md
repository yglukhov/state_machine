# state_machine
State machine

# Usage
```nim
import state_machine

type
    CarEvent = enum
        park
        ignite
        idle
        shift_up
        shift_down
        crash
        repair

    CarState = enum
        parked
        idling
        first_gear
        second_gear
        third_gear
        stalled

# Setup
var sm: StateMechine[CarState, CarEvent]
sm.init()

# Define possible transitions
sm.transition(park, {idling, first_gear}, parked)

sm.transition(ignite, stalled, stalled)
sm.transition(ignite, parked, idling)

sm.transition(idle, first_gear, idling)

sm.transition(shift_up, idling, first_gear)
sm.transition(shift_up, first_gear, second_gear)
sm.transition(shift_up, second_gear, third_gear)

sm.transition(shift_down, third_gear, second_gear)
sm.transition(shift_down, second_gear, first_gear)

# Setup transition handlers
sm.afterTransition(first_gear, {second_gear}) do():
    echo "first -> second: "

sm.afterTransition(CarState.all, first_gear) do(f, t: CarState, e: CarEvent):
    echo "-> first"


# Use
sm.event(ignite)
doAssert(sm.state == idling)

sm.event(shift_up)
doAssert(sm.state == first_gear)

sm.event(shift_up)
doAssert(sm.state == second_gear)
echo sm.state
sm.event(shift_down)
doAssert(sm.state == first_gear)

doAssert(not sm.tryEvent(repair))
```