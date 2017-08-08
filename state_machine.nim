import tables

type
    StateMachineBase = object {.inheritable.}
        transitionsMatrix: seq[int16]
        beforeTransitionHandlers: Table[int32, seq[TransitionHandlerBase]]
        afterTransitionHandlers: Table[int32, seq[TransitionHandlerBase]]
        stateHandlers: seq[seq[proc()]]
        numEvents: int
        curState: int16

    TransitionHandlerBase = proc(fromState, toState, event: int16)

proc init(sm: var StateMachineBase, numEvents, numStates: int) =
    let num = numEvents * numStates
    sm.transitionsMatrix = newSeq[int16](num)
    for i in 0 ..< num: sm.transitionsMatrix[i] = -1
    sm.beforeTransitionHandlers = initTable[int32, seq[TransitionHandlerBase]]()
    sm.afterTransitionHandlers = initTable[int32, seq[TransitionHandlerBase]]()
    sm.numEvents = numEvents

proc transitionIdx(sm: StateMachineBase, event, state: int16): int {.inline.} =
    state * sm.numEvents + event

proc destinationState(sm: StateMachineBase, event, fromState: int16): int16 =
    sm.transitionsMatrix[sm.transitionIdx(event, fromState)]

proc defineTransition(sm: var StateMachineBase, event, fromState, toState: int16) =
    let idx = sm.transitionIdx(event, fromState)
    assert(sm.transitionsMatrix[idx] == -1, "Transition already defined")
    sm.transitionsMatrix[idx] = toState

proc defineTransition(sm: var StateMachineBase, event: int16, fromStates: openarray[int16], toState: int16) =
    for s in fromStates:
        sm.defineTransition(event, s, toState)

proc transitionKey(fromState, toState: int16): int32 {.inline.} =
    (int32(fromState) shl 16) or toState

proc addBeforeTransitionHandler(sm: var StateMachineBase, fromState, toState: int16, handler: TransitionHandlerBase) =
    sm.beforeTransitionHandlers.mgetOrPut(transitionKey(fromState, toState), nil).safeAdd(handler)

proc addAfterTransitionHandler(sm: var StateMachineBase, fromState, toState: int16, handler: TransitionHandlerBase) =
    sm.afterTransitionHandlers.mgetOrPut(transitionKey(fromState, toState), nil).safeAdd(handler)

proc addBeforeTransitionHandler(sm: var StateMachineBase, fromState: int16, toStates: openarray[int16], handler: TransitionHandlerBase) =
    if toStates.len == 0:
        sm.addBeforeTransitionHandler(fromState, -1, handler)
    else:
        for s in toStates:
            sm.addBeforeTransitionHandler(fromState, s, handler)

proc addAfterTransitionHandler(sm: var StateMachineBase, fromState: int16, toStates: openarray[int16], handler: TransitionHandlerBase) =
    if toStates.len == 0:
        sm.addAfterTransitionHandler(fromState, -1, handler)
    else:
        for s in toStates:
            sm.addAfterTransitionHandler(fromState, s, handler)

proc addBeforeTransitionHandler(sm: var StateMachineBase, fromStates, toStates: openarray[int16], handler: TransitionHandlerBase) =
    if fromStates.len == 0:
        sm.addBeforeTransitionHandler(-1, toStates, handler)
    else:
        for s in fromStates:
            sm.addBeforeTransitionHandler(s, toStates, handler)

proc addAfterTransitionHandler(sm: var StateMachineBase, fromStates, toStates: openarray[int16], handler: TransitionHandlerBase) =
    if fromStates.len == 0:
        sm.addAfterTransitionHandler(-1, toStates, handler)
    else:
        for s in fromStates:
            sm.addAfterTransitionHandler(s, toStates, handler)

proc addBeforeTransitionHandler(sm: var StateMachineBase, fromStates: openarray[int16], toState: int16, handler: TransitionHandlerBase) =
    sm.addBeforeTransitionHandler(fromStates, [toState], handler)

proc addAfterTransitionHandler(sm: var StateMachineBase, fromStates: openarray[int16], toState: int16, handler: TransitionHandlerBase) =
    sm.addAfterTransitionHandler(fromStates, [toState], handler)

proc addAroundTransitionHandler(sm: var StateMachineBase, fromStates, toStates: openarray[int16], handler: TransitionHandlerBase) =
    sm.addBeforeTransitionHandler(fromStates, toStates, handler)
    sm.addAfterTransitionHandler(fromStates, toStates, handler)

proc addStateHandler(sm: var StateMachineBase, state: int16, handler: proc()) =
    if state >= sm.stateHandlers.len:
        sm.stateHandlers.setLen(state + 1)
    sm.stateHandlers[state].safeAdd(handler)

iterator beforeTransitionHandlers(sm: StateMachineBase, transitionKeys: openarray[int32]): TransitionHandlerBase =
    for k in transitionKeys:
        for h in sm.beforeTransitionHandlers.getOrDefault(k):
            yield h

iterator afterTransitionHandlers(sm: StateMachineBase, transitionKeys: openarray[int32]): TransitionHandlerBase =
    for k in transitionKeys:
        for h in sm.afterTransitionHandlers.getOrDefault(k):
            yield h

proc handleEvent(sm: var StateMachineBase, event: int16): bool =
    let fromState = sm.curState
    let toState = sm.destinationState(event, fromState)
    if toState == -1:
        return false
    result = true

    let transitionKeys = [ transitionKey(fromState, toState),
        transitionKey(-1, toState),
        transitionKey(fromState, -1) ]

    for h in beforeTransitionHandlers(sm, transitionKeys):
        h(fromState, toState, event)

    sm.curState = toState
    if toState < sm.stateHandlers.len:
        for h in sm.stateHandlers[toState]:
            h()

    for h in afterTransitionHandlers(sm, transitionKeys):
        h(fromState, toState, event)

proc setToSeq[T](s: set[T]): seq[int16] =
    result = newSeq[int16](s.card)
    var i = 0
    for v in low(T) .. high(T):
        if v in s:
            result[i] = int16(v)
            inc i

proc setToSeq[T](s: T): array[1, int16] {.inline.} = [int16(s)]

type
    StateMechine[TState, TEvent] = object of StateMachineBase

proc wrap[TState, TEvent](sm: StateMechine[TState, TEvent], handler: proc(fromState, toState: TState, event: TEvent)): TransitionHandlerBase {.inline.} =
    result = proc(fromState, toState, event: int16) =
        handler(TState(fromState), TState(toState), TEvent(event))

proc wrap[TState, TEvent](sm: StateMechine[TState, TEvent], handler: proc()): TransitionHandlerBase {.inline.} =
    result = proc(fromState, toState, event: int16) =
        handler()

proc init*[TState, TEvent](sm: var StateMechine[TState, TEvent]) {.inline.} =
    sm.init(high(TEvent).ord + 1, high(TState).ord + 1)

proc state*[TState, TEvent](sm: var StateMechine[TState, TEvent], state: TState, handler: proc()) {.inline.} =
    addStateHandler(sm, int16(state), handler)

proc transition*[TState, TEvent](sm: var StateMechine[TState, TEvent], event: TEvent, fromStates: set[TState], toState: TState) {.inline.} =
    sm.defineTransition(int16(event), setToSeq(fromStates), int16(toState))

proc transition*[TState, TEvent](sm: var StateMechine[TState, TEvent], event: TEvent, fromState, toState: TState) {.inline.} =
    sm.defineTransition(int16(event), int16(fromState), int16(toState))

proc beforeTransition*[TState, TEvent](sm: var StateMechine[TState, TEvent], fromStates, toStates: set[TState] | TState, handler: proc(fromState, toState: TState, event: TEvent)) {.inline.} =
    sm.addBeforeTransitionHandler(setToSeq(fromStates), setToSeq(toStates), sm.wrap(handler))

proc afterTransition*[TState, TEvent](sm: var StateMechine[TState, TEvent], fromStates, toStates: set[TState] | TState, handler: proc(fromState, toState: TState, event: TEvent)) {.inline.} =
    sm.addAfterTransitionHandler(setToSeq(fromStates), setToSeq(toStates), sm.wrap(handler))

proc aroundTransition*[TState, TEvent](sm: var StateMechine[TState, TEvent], fromStates, toStates: set[TState] | TState, handler: proc(fromState, toState: TState, event: TEvent)) {.inline.} =
    sm.addAroundTransitionHandler(setToSeq(fromStates), setToSeq(toStates), sm.wrap(handler))

proc beforeTransition*[TState, TEvent](sm: var StateMechine[TState, TEvent], fromStates, toStates: set[TState] | TState, handler: proc()) {.inline.} =
    sm.addBeforeTransitionHandler(setToSeq(fromStates), setToSeq(toStates), sm.wrap(handler))

proc afterTransition*[TState, TEvent](sm: var StateMechine[TState, TEvent], fromStates, toStates: set[TState] | TState, handler: proc()) {.inline.} =
    sm.addAfterTransitionHandler(setToSeq(fromStates), setToSeq(toStates), sm.wrap(handler))

proc aroundTransition*[TState, TEvent](sm: var StateMechine[TState, TEvent], fromStates, toStates: set[TState] | TState, handler: proc()) {.inline.} =
    sm.addAroundTransitionHandler(setToSeq(fromStates), setToSeq(toStates), sm.wrap(handler))

proc state*[TState, TEvent](sm: StateMechine[TState, TEvent]): TState {.inline.} = TState(sm.curState)

proc tryEvent*[TState, TEvent](sm: var StateMechine[TState, TEvent], evt: TEvent): bool {.inline.} = sm.handleEvent(int16(evt))
proc event*[TState, TEvent](sm: var StateMechine[TState, TEvent], evt: TEvent) {.inline.} =
    if not sm.tryEvent(evt):
        raise newException(Exception, "Wrong event " & $evt & " sent to state machine in state " & $sm.state)

proc all*[TState: enum](T: typedesc[TState]): set[TState] =
    for i in low(TState) .. high(TState):
        result.incl(i)

when isMainModule:
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
