import Foundation

/// Thrown only by kernel code that has itself gone wrong; the machine panics instead of faulting.
private struct PanicSignal: Error {
    let kind: PanicKind
    let reason: String
    let faultAddress: Int?
}

public struct SystemCall: Sendable, Equatable {
    public let service: UInt8
    public let arguments: [UInt8]
    public let callerPrivilege: Privilege
    public var name: String {
        switch service {
        case 1: "Draw pixel"
        case 2: "Fill display"
        case 3: "Read input"
        case 4: "Write console"
        case 5: "Read ticks"
        case 6: "Exit"
        case 7: "Draw pixel (unchecked)"
        case 8: "Watchdog check-in"
        default: "Unknown"
        }
    }
}

/// A deterministic, copyable machine. Copying this value preserves the entire
/// CPU, RAM, syscall, and microphase state, so UI history can restore true snapshots.
/// It models a single sequential CPU, no cache/MMU/interrupts, and a tiny synchronous
/// kernel. Display RAM holds 64 raw bytes; the renderer uses each byte's low three
/// bits as its palette index. IN/OUT are isolated ports, not RAM.
/// SYS 7 is a deliberately buggy driver and SYS 8 arms a watchdog, so a panic can be
/// studied as a whole-machine stop distinct from an ordinary fault.
public struct Machine: Sendable, Equatable {
    /// Retain the latest 4 KiB so output loops and snapshot history stay bounded.
    /// Retention counts ASCII bytes rather than grapheme clusters (CRLF is two bytes).
    public static let consoleCapacity = 4_096
    /// Once SYS 8 enables monitoring, a check-in must follow within this many microcycles.
    public static let watchdogTimeout: UInt64 = 32
    public private(set) var program: Program
    public private(set) var mode: ExecutionMode
    public private(set) var memory: [UInt8]
    public private(set) var registers: [UInt8] = [0, 0, 0, 0]
    public private(set) var pc = 0
    /// Points at the occupied top of the stack; 192 denotes an empty stack.
    /// PUSH decrements before storing, so its first write goes to address 191.
    public private(set) var stackPointer = 192
    public private(set) var zeroFlag = false
    public private(set) var carryFlag = false
    public private(set) var phase: MicroPhase = .fetch
    public private(set) var privilege: Privilege
    public private(set) var cycleCount: UInt64 = 0
    public private(set) var instructionCount = 0
    public private(set) var console = ""
    public private(set) var consoleByteCount: UInt64 = 0
    public private(set) var droppedConsoleByteCount: UInt64 = 0
    public private(set) var consoleValue: UInt8 = 0
    public private(set) var inputValue: UInt8 = 0
    public private(set) var trace: [TraceEvent] = []
    public private(set) var lastALU: ALURecord?
    public private(set) var bus: BusActivity?
    public private(set) var currentInstruction: Instruction?
    public private(set) var currentInstructionAddress: Int?
    public private(set) var fetchedBytes: [UInt8] = []
    public private(set) var syscall: SystemCall?
    public private(set) var fault: String?
    /// Set with `fault` when the stop is a kernel panic rather than an enforced rule.
    public private(set) var panic: KernelPanic?
    public private(set) var halted = false
    public private(set) var watchdogCheckIns = 0
    /// The microcycle of the latest check-in; nil until SYS 8 enables monitoring.
    public private(set) var lastWatchdogCheckIn: UInt64?
    /// Raw display bytes. The physical display interprets `byte & 7` as a color.
    public var framebuffer: [UInt8] { Array(memory[MemoryMap.framebuffer]) }
    public var ticks: UInt8 { UInt8(truncatingIfNeeded: cycleCount) }
    public var isFinished: Bool { halted || fault != nil }
    public var nextPhase: MicroPhase { scheduledPhase }
    public var stackDepth: Int { 192 - stackPointer }
    /// The last microcycle that may run without another check-in.
    public var watchdogDeadline: UInt64? { lastWatchdogCheckIn.map { $0 + Self.watchdogTimeout } }

    private enum DriverAction: Sendable, Equatable {
        case pixel(index: UInt8, palette: UInt8), fill(UInt8), input, output(UInt8), ticks, exit
        case uncheckedPixel(index: UInt8, palette: UInt8), watchdogCheckIn
    }
    private var scheduledPhase: MicroPhase = .fetch
    private var driverAction: DriverAction?

    public init(program: Program, mode: ExecutionMode = .bareMetal) {
        self.program = program
        self.mode = mode
        self.memory = program.bytes
        self.privilege = mode == .bareMetal ? .bareMetal : .user
    }

    /// Reset keeps the physical input switch in its current position.
    public mutating func reset() {
        let input = inputValue
        self = Machine(program: program, mode: mode)
        inputValue = input
    }

    public mutating func load(program: Program, mode: ExecutionMode? = nil) {
        let input = inputValue
        self = Machine(program: program, mode: mode ?? self.mode)
        inputValue = input
    }

    /// This is an external debugger edit, independent of CPU privilege. A CPU's
    /// already-fetched instruction remains latched until its next fetch.
    public mutating func editMemory(at address: Int, value: UInt8) throws {
        guard memory.indices.contains(address) else { throw MachineError("RAM address \(address) is outside 0...255.") }
        memory[address] = value
    }

    public mutating func editRegister(_ index: Int, value: UInt8) throws {
        guard registers.indices.contains(index) else { throw MachineError("Register index \(index) is outside R0...R3.") }
        registers[index] = value
    }

    public mutating func setInput(_ value: UInt8) { inputValue = value }
    public mutating func setInput(_ pressed: Bool) { inputValue = pressed ? 1 : 0 }

    /// Advances exactly one visible microphase, returning the resulting trace event.
    /// Finished machines remain unchanged and return nil.
    @discardableResult public mutating func step() -> TraceEvent? {
        guard !isFinished else { return nil }
        cycleCount &+= 1
        phase = scheduledPhase
        bus = nil
        if let deadline = watchdogDeadline, cycleCount > deadline {
            return enterPanic(PanicSignal(kind: .watchdogTimeout,
                reason: "watchdog timeout: no check-ins in \(Self.watchdogTimeout) microcycles (\(watchdogCheckIns) total check-ins since monitoring enabled)",
                faultAddress: nil))
        }
        do {
            let message: String
            switch phase {
            case .fetch:
                guard MemoryMap.code.contains(pc), pc % 4 == 0, pc + 4 <= 128 else {
                    throw MachineError("PC \(pc) is outside aligned code addresses 0...124.")
                }
                currentInstructionAddress = pc
                currentInstruction = nil
                fetchedBytes = Array(memory[pc..<(pc + 4)])
                bus = activity(.instructionFetch, address: pc, value: fetchedBytes[0], "Fetch four bytes at RAM[\(pc)].")
                scheduledPhase = .decode
                message = "PC \(pc) → instruction bytes \(fetchedBytes.map { String(format: "%02X", $0) }.joined(separator: " "))."
            case .decode:
                let decoded = try Decoder.decode(fetchedBytes)
                currentInstruction = decoded
                scheduledPhase = .execute
                message = "Decode \(decoded.description): \(decoded.opcode.explanation)"
            case .execute:
                guard let instruction = currentInstruction, let address = currentInstructionAddress else { throw MachineError("No decoded instruction is ready.") }
                pc = address + 4
                message = try execute(instruction)
                if instruction.opcode != .sys {
                    instructionCount += 1
                    scheduledPhase = halted ? .halted : .fetch
                    if halted { phase = .halted }
                }
            case .trap:
                guard let call = syscall else { throw MachineError("No syscall is pending.") }
                privilege = .kernel
                bus = activity(.trap, address: nil, value: call.service, "Trap SYS \(call.service): \(call.name).")
                scheduledPhase = .kernel
                message = "Trap SYS \(call.service): save \(call.callerPrivilege.title.lowercased()) state; privilege → kernel."
            case .kernel:
                guard let call = syscall else { throw MachineError("No syscall is pending.") }
                driverAction = try dispatch(call)
                scheduledPhase = .driver
                message = "Kernel validates SYS \(call.service) (\(call.name)) and dispatches the trusted driver."
            case .driver:
                guard let action = driverAction else { throw MachineError("No driver action is pending.") }
                message = try runDriver(action)
                scheduledPhase = .returnToUser
            case .returnToUser:
                guard let call = syscall else { throw MachineError("No syscall state to return from.") }
                privilege = call.callerPrivilege
                instructionCount += 1
                let exiting = call.service == 6
                syscall = nil
                driverAction = nil
                halted = exiting
                scheduledPhase = exiting ? .halted : .fetch
                message = exiting ? "Return from kernel; SYS 6 closes the process." : "Restore \(privilege.title.lowercased()) privilege; resume at PC \(pc)."
            case .halted, .fault: return nil
            }
            return record(message)
        } catch let signal as PanicSignal {
            return enterPanic(signal)
        } catch {
            fault = error.localizedDescription
            phase = .fault
            scheduledPhase = .fault
            return record("Fault: \(error.localizedDescription)")
        }
    }

    /// Finishes the current instruction, or starts one if at a fetch boundary.
    /// The bound also protects callers if this model gains longer device phases.
    @discardableResult public mutating func stepInstruction() -> [TraceEvent] {
        let target = instructionCount + 1
        var events: [TraceEvent] = []
        for _ in 0..<16 {
            guard !isFinished, instructionCount < target else { break }
            if let event = step() { events.append(event) }
        }
        return events
    }

    private mutating func execute(_ instruction: Instruction) throws -> String {
        let a = Int(instruction.a), b = Int(instruction.b)
        let op = instruction.opcode
        switch op {
        case .nop: return "NOP; PC → \(pc)."
        case .ldi:
            registers[a] = instruction.b
            return "R\(a) ← immediate \(instruction.b)."
        case .mov:
            registers[a] = registers[b]
            return "R\(a) ← R\(b) = \(registers[a])."
        case .add, .sub, .and, .or, .xor, .cmp:
            let left = registers[a], right = registers[b]
            let result: UInt8, carry: Bool
            switch op {
            case .add: (result, carry) = left.addingReportingOverflow(right)
            case .sub, .cmp: (result, carry) = left.subtractingReportingOverflow(right)
            case .and: result = left & right; carry = false
            case .or: result = left | right; carry = false
            case .xor: result = left ^ right; carry = false
            default: fatalError("Unreachable arithmetic opcode.")
            }
            updateALU(op.mnemonic, left: left, right: right, result: result, carry: carry)
            if op != .cmp { registers[a] = result }
            return "ALU \(op.mnemonic): \(left), \(right) → \(result); Z=\(zeroFlag ? 1 : 0), C=\(carryFlag ? 1 : 0)."
        case .shl:
            let left = registers[a], result = left &<< 1
            updateALU("SHL", left: left, right: 1, result: result, carry: left & 0x80 != 0)
            registers[a] = result
            return "ALU SHL: \(left) << 1 → \(result); outgoing bit = \(carryFlag ? 1 : 0)."
        case .inc, .dec:
            let left = registers[a]
            let (result, carry) = op == .inc ? left.addingReportingOverflow(1) : left.subtractingReportingOverflow(1)
            updateALU(op.mnemonic, left: left, right: 1, result: result, carry: carry)
            registers[a] = result
            return "ALU \(op.mnemonic): \(left) → \(result); Z=\(zeroFlag ? 1 : 0), C=\(carryFlag ? 1 : 0)."
        case .ld, .ldx:
            let address = op == .ld ? b : Int(registers[b])
            registers[a] = try read(address)
            return "R\(a) ← RAM[\(address)] = \(registers[a])."
        case .st, .stx:
            let address = op == .st ? b : Int(registers[b])
            try write(address, value: registers[a])
            return "RAM[\(address)] ← R\(a) = \(registers[a])."
        case .jmp, .jz, .jnz:
            let take = op == .jmp || (op == .jz && zeroFlag) || (op == .jnz && !zeroFlag)
            if take { pc = a }
            return "\(op.mnemonic) \(a): \(take ? "taken" : "not taken"); PC → \(pc)."
        case .push:
            try push(registers[a])
            return "Push R\(a) = \(registers[a]); SP → \(stackPointer)."
        case .pop:
            registers[a] = try pop()
            return "Pop \(registers[a]) into R\(a); SP → \(stackPointer)."
        case .call:
            try push(UInt8(pc))
            pc = a
            return "Push return address \(memory[stackPointer]); CALL → PC \(pc)."
        case .ret:
            let target = Int(try pop())
            guard target < 128, target % 4 == 0 else { throw MachineError("RET found invalid code address \(target) on the stack.") }
            pc = target
            return "Pop return address; PC → \(pc)."
        case .input:
            guard privilege != .user else { throw MachineError("User code cannot read the input port directly; use SYS 3.") }
            registers[a] = inputValue
            bus = activity(.deviceRead, address: MemoryMap.inputPort, value: inputValue, "Input port → R\(a).")
            return "Input port → R\(a) = \(inputValue)."
        case .output:
            guard privilege != .user else { throw MachineError("User code cannot write the console port directly; use SYS 4.") }
            try output(registers[a])
            return "Console port ← R\(a) ASCII \(registers[a])."
        case .sys:
            syscall = SystemCall(service: instruction.a, arguments: registers, callerPrivilege: privilege)
            scheduledPhase = .trap
            return "SYS \(instruction.a) requests \(syscall?.name ?? "service"); next phase → trap."
        case .halt:
            halted = true
            return "HALT; execution stopped after \(instructionCount + 1) instructions."
        }
    }

    private mutating func updateALU(_ operation: String, left: UInt8, right: UInt8, result: UInt8, carry: Bool) {
        zeroFlag = result == 0
        carryFlag = carry
        lastALU = ALURecord(operation: operation, left: left, right: right, result: result, carry: carry, zero: zeroFlag)
    }

    private mutating func read(_ address: Int) throws -> UInt8 {
        guard memory.indices.contains(address) else { throw MachineError("Read address \(address) is outside RAM.") }
        if privilege == .user && MemoryMap.framebuffer.contains(address) { throw MachineError("User code cannot read display RAM at \(address); access devices through SYS.") }
        let value = memory[address]
        bus = activity(MemoryMap.framebuffer.contains(address) ? .deviceRead : .memoryRead, address: address, value: value, "RAM[\(address)] → \(value).")
        return value
    }

    private mutating func write(_ address: Int, value: UInt8) throws {
        guard memory.indices.contains(address) else { throw MachineError("Write address \(address) is outside RAM.") }
        if MemoryMap.framebuffer.contains(address) {
            guard privilege != .user else { throw MachineError("User code cannot write display RAM at \(address); use SYS 1 or SYS 2.") }
        }
        memory[address] = value
        bus = activity(MemoryMap.framebuffer.contains(address) ? .deviceWrite : .memoryWrite, address: address, value: value, "RAM[\(address)] ← \(value).")
    }

    private mutating func push(_ value: UInt8) throws {
        guard stackPointer > MemoryMap.stackBottom else { throw MachineError("Stack overflow: all 64 shared data/stack bytes are occupied.") }
        stackPointer -= 1
        try write(stackPointer, value: value)
    }

    private mutating func pop() throws -> UInt8 {
        guard stackPointer <= MemoryMap.stackTop else { throw MachineError("Stack underflow: there is no value to pop.") }
        let value = try read(stackPointer)
        stackPointer += 1
        return value
    }

    private func dispatch(_ call: SystemCall) throws -> DriverAction {
        switch call.service {
        case 1:
            guard call.arguments[0] < 64 else { throw MachineError("SYS 1 pixel index \(call.arguments[0]) is outside 0...63.") }
            guard call.arguments[1] < 8 else { throw MachineError("SYS 1 palette index \(call.arguments[1]) is outside 0...7.") }
            return .pixel(index: call.arguments[0], palette: call.arguments[1])
        case 2:
            guard call.arguments[0] < 8 else { throw MachineError("SYS 2 palette index \(call.arguments[0]) is outside 0...7.") }
            return .fill(call.arguments[0])
        case 3: return .input
        case 4:
            guard call.arguments[0] < 128 else { throw MachineError("SYS 4 console value must be ASCII 0...127.") }
            return .output(call.arguments[0])
        case 5: return .ticks
        case 6: return .exit
        case 7:
            // Deliberate teaching bug: SYS 1's pixel index check is missing.
            guard call.arguments[1] < 8 else { throw MachineError("SYS 7 palette index \(call.arguments[1]) is outside 0...7.") }
            return .uncheckedPixel(index: call.arguments[0], palette: call.arguments[1])
        case 8: return .watchdogCheckIn
        default: throw MachineError("Unknown kernel service \(call.service).")
        }
    }

    private mutating func runDriver(_ action: DriverAction) throws -> String {
        switch action {
        case let .pixel(index, palette):
            try write(192 + Int(index), value: palette)
            return "Display driver writes palette \(palette) to pixel \(index) (RAM[\(192 + Int(index))])."
        case .fill(let palette):
            for address in MemoryMap.framebuffer { memory[address] = palette }
            bus = activity(.deviceWrite, address: 192, value: palette, "Display driver fills all 64 pixels with palette \(palette).")
            return "Display driver fills RAM[192...255] with palette \(palette)."
        case .input:
            registers[0] = inputValue
            bus = activity(.deviceRead, address: MemoryMap.inputPort, value: inputValue, "Input driver returns the current switch in R0.")
            return "Input driver reads \(inputValue); return value → R0."
        case .output(let value):
            try output(value)
            return "Console driver appends ASCII \(value)."
        case .ticks:
            registers[0] = ticks
            bus = activity(.deviceRead, address: nil, value: ticks, "Clock driver returns microphase ticks modulo 256.")
            return "Clock driver reads \(cycleCount) microphase ticks; low byte \(ticks) → R0."
        case .exit: return "Kernel marks the process for exit; return phase closes it."
        case let .uncheckedPixel(index, palette):
            let address = 192 + Int(index)
            guard memory.indices.contains(address) else {
                throw PanicSignal(kind: .kernelDataAbort,
                    reason: "Kernel data abort: driver write to RAM[\(address)]; index \(index) was never checked",
                    faultAddress: address)
            }
            try write(address, value: palette)
            return "Unchecked display driver writes palette \(palette) to pixel \(index) (RAM[\(address)])."
        case .watchdogCheckIn:
            watchdogCheckIns += 1
            lastWatchdogCheckIn = cycleCount
            bus = activity(.deviceWrite, address: nil, value: UInt8(truncatingIfNeeded: watchdogCheckIns), "Watchdog timer reset.")
            return "Watchdog check-in \(watchdogCheckIns); the next is due within \(Self.watchdogTimeout) microcycles."
        }
    }

    private mutating func enterPanic(_ signal: PanicSignal) -> TraceEvent {
        panic = KernelPanic(kind: signal.kind, reason: signal.reason, cycle: cycleCount, pc: pc,
                            instructionAddress: currentInstructionAddress, faultAddress: signal.faultAddress,
                            watchdogCheckIns: watchdogCheckIns)
        fault = "Kernel panic: \(signal.reason)"
        phase = .fault
        scheduledPhase = .fault
        return record("Panic: \(signal.reason)")
    }

    private mutating func output(_ value: UInt8) throws {
        guard value < 128 else { throw MachineError("Console accepts ASCII bytes 0...127.") }
        consoleValue = value
        console.append(Character(UnicodeScalar(value)))
        consoleByteCount &+= 1
        if console.utf8.count > Self.consoleCapacity {
            console = String(decoding: console.utf8.suffix(Self.consoleCapacity), as: UTF8.self)
            droppedConsoleByteCount &+= 1
        }
        bus = activity(.deviceWrite, address: MemoryMap.consolePort, value: value, "Console port ← ASCII \(value).")
    }

    private func activity(_ kind: BusKind, address: Int?, value: UInt8?, _ description: String) -> BusActivity {
        BusActivity(kind: kind, address: address, value: value, privilege: privilege, description: description)
    }

    private mutating func record(_ message: String) -> TraceEvent {
        let event = TraceEvent(id: cycleCount, phase: phase, message: message, instructionAddress: currentInstructionAddress, bus: bus, privilege: privilege)
        trace.append(event)
        if trace.count > 384 { trace.removeFirst(trace.count - 384) }
        return event
    }
}
