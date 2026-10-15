import Foundation
import AssemblerCore

enum GuidedLayer: String, CaseIterable, Identifiable, Sendable {
    case assembly, cpu, registers, memory, os
    var id: String { rawValue }
    var title: String {
        switch self {
        case .assembly: "Assembly"
        case .cpu: "CPU"
        case .registers: "Registers"
        case .memory: "Memory"
        case .os: "OS"
        }
    }
}

enum GuidedAccess: String, Sendable {
    case read, write, changed
    var title: String {
        switch self {
        case .read: "Read"
        case .write: "Written"
        case .changed: "Changed"
        }
    }
}

struct GuidedValueChange: Identifiable, Sendable, Equatable {
    let layer: GuidedLayer
    let field: String
    let title: String
    let before: String
    let after: String
    let access: GuidedAccess
    var id: String { "\(layer.rawValue).\(field)" }
    var didChange: Bool { before != after }
}

struct GuidedHighlights: Sendable, Equatable {
    let instructionAddress: Int
    var readRegisters: Set<Int> = []
    var writtenRegisters: Set<Int> = []
    var changedRegisters: Set<Int> = []
    var readMemory: Set<Int> = []
    var writtenMemory: Set<Int> = []
    var changedMemory: Set<Int> = []
    var cpuFields: Set<String> = []
    var osFields: Set<String> = []
}

/// A presentation record of one real interpreter microstep. Keeping both exact
/// snapshots distinguishes an unchanged value that was read/written from a diff.
struct GuidedInstructionStep: Identifiable, Sendable, Equatable {
    let id: Int
    let before: Machine
    let after: Machine
    let executedPhase: MicroPhase
    let event: TraceEvent
    let highlights: GuidedHighlights
    let changes: [GuidedValueChange]
    var explanation: String { event.message }
    var bus: BusActivity? { event.bus }
    var capturedSystemCall: SystemCall? { after.syscall ?? before.syscall }

    init(id: Int, before: Machine, after: Machine, event: TraceEvent, instructionAddress: Int) {
        self.id = id
        self.before = before
        self.after = after
        self.executedPhase = before.nextPhase
        self.event = event
        let presentation = GuidedPresentation.make(before: before, after: after, event: event,
                                                  instructionAddress: instructionAddress)
        highlights = presentation.highlights
        changes = presentation.changes
    }
}

struct GuidedInstruction: Sendable, Equatable {
    let baseline: Machine
    let instructionAddress: Int
    /// RAM and latched execution bytes may differ after a debugger patch.
    let ramBytes: [UInt8]
    let executionBytes: [UInt8]
    let instruction: Instruction?
    let sourceRow: InstructionRow?
    let isPartwayThroughInstruction: Bool
    private(set) var steps: [GuidedInstructionStep] = []

    var sourceMatchesExecution: Bool { sourceRow?.bytes == executionBytes }
    var latestStep: GuidedInstructionStep? { steps.last }
    var currentMachine: Machine { latestStep?.after ?? baseline }
    var isComplete: Bool {
        currentMachine.instructionCount > baseline.instructionCount || currentMachine.isFinished
    }
    var canAdvance: Bool { !isComplete }
    var canPrevious: Bool { !steps.isEmpty }
    var capturedSystemCall: SystemCall? {
        latestStep?.capturedSystemCall ?? steps.reversed().compactMap(\.capturedSystemCall).first ?? baseline.syscall
    }

    init(machine: Machine) {
        baseline = machine
        isPartwayThroughInstruction = machine.nextPhase != .fetch
        instructionAddress = isPartwayThroughInstruction ? (machine.currentInstructionAddress ?? machine.pc) : machine.pc
        let address = instructionAddress
        ramBytes = address >= 0 && address + 4 <= machine.memory.count
            ? Array(machine.memory[address..<(address + 4)]) : []
        executionBytes = isPartwayThroughInstruction && machine.fetchedBytes.count == 4 ? machine.fetchedBytes : ramBytes
        instruction = isPartwayThroughInstruction
            ? (machine.currentInstruction ?? (try? Decoder.decode(executionBytes)))
            : (try? Decoder.decode(executionBytes))
        sourceRow = machine.program.instructions.first { $0.address == address }
    }

    mutating func append(_ step: GuidedInstructionStep) { steps.append(step) }
    mutating func removeLastStep() -> GuidedInstructionStep? { steps.popLast() }
    mutating func restart() { steps.removeAll() }
}

private enum GuidedPresentation {
    static func make(before: Machine, after: Machine, event: TraceEvent,
                     instructionAddress: Int) -> (highlights: GuidedHighlights, changes: [GuidedValueChange]) {
        var highlights = GuidedHighlights(instructionAddress: instructionAddress)
        var changes: [GuidedValueChange] = []
        let phase = before.nextPhase
        let instruction = before.currentInstruction
        var readCPU: Set<String> = []
        var writtenCPU: Set<String> = ["phase", "nextPhase", "cycleCount"]
        if phase == .fetch { readCPU.insert("pc") }
        if phase == .decode { readCPU.insert("fetchedBytes") }
        if phase == .execute {
            readCPU.insert("decodedInstruction")
            writtenCPU.insert("pc")
            if let instruction {
                let a = Int(instruction.a), b = Int(instruction.b)
                switch instruction.opcode {
                case .ldi, .ld, .pop, .input:
                    if after.fault == nil { highlights.writtenRegisters.insert(a) }
                case .mov:
                    highlights.readRegisters.insert(b)
                    if after.fault == nil { highlights.writtenRegisters.insert(a) }
                case .add, .sub, .and, .or, .xor, .cmp:
                    highlights.readRegisters.formUnion([a, b])
                    if instruction.opcode != .cmp && after.fault == nil { highlights.writtenRegisters.insert(a) }
                    writtenCPU.formUnion(["zeroFlag", "carryFlag", "alu"])
                case .shl, .inc, .dec:
                    highlights.readRegisters.insert(a)
                    if after.fault == nil { highlights.writtenRegisters.insert(a) }
                    writtenCPU.formUnion(["zeroFlag", "carryFlag", "alu"])
                case .ldx:
                    highlights.readRegisters.insert(b)
                    if after.fault == nil { highlights.writtenRegisters.insert(a) }
                case .st, .push:
                    highlights.readRegisters.insert(a)
                case .stx:
                    highlights.readRegisters.formUnion([a, b])
                case .output:
                    if before.privilege != .user { highlights.readRegisters.insert(a) }
                case .sys:
                    highlights.readRegisters.formUnion(0..<4)
                case .jz, .jnz:
                    readCPU.insert("zeroFlag")
                default: break
                }
                if [.push, .pop, .call, .ret].contains(instruction.opcode) {
                    readCPU.insert("stackPointer")
                    if before.stackPointer != after.stackPointer { writtenCPU.insert("stackPointer") }
                }
            }
        }
        if phase == .driver, let call = before.syscall, [3, 5].contains(call.service), after.fault == nil {
            highlights.writtenRegisters.insert(0)
        }
        if let bus = event.bus {
            switch bus.kind {
            case .instructionFetch:
                if let address = bus.address {
                    highlights.readMemory.formUnion(address..<(address + after.fetchedBytes.count))
                }
            case .memoryRead:
                if let address = bus.address { highlights.readMemory.insert(address) }
            case .memoryWrite:
                if let address = bus.address { highlights.writtenMemory.insert(address) }
            case .deviceRead:
                if let address = bus.address, MemoryMap.framebuffer.contains(address) { highlights.readMemory.insert(address) }
            case .deviceWrite:
                if let address = bus.address, MemoryMap.framebuffer.contains(address) {
                    if phase == .driver && before.syscall?.service == 2 {
                        highlights.writtenMemory.formUnion(MemoryMap.framebuffer)
                    } else {
                        highlights.writtenMemory.insert(address)
                    }
                }
            case .trap: break
            }
        }
        for index in before.registers.indices where before.registers[index] != after.registers[index] {
            highlights.changedRegisters.insert(index)
        }
        for address in before.memory.indices where before.memory[address] != after.memory[address] {
            highlights.changedMemory.insert(address)
        }
        for register in highlights.readRegisters.union(highlights.writtenRegisters).union(highlights.changedRegisters).sorted() {
            let access: GuidedAccess = highlights.writtenRegisters.contains(register) ? .write
                : (highlights.readRegisters.contains(register) ? .read : .changed)
            changes.append(.init(layer: .registers, field: "R\(register)", title: "R\(register)",
                                 before: byte(before.registers[register]), after: byte(after.registers[register]),
                                 access: access))
        }
        for address in highlights.readMemory.union(highlights.writtenMemory).union(highlights.changedMemory).sorted() {
            let access: GuidedAccess = highlights.writtenMemory.contains(address) ? .write
                : (highlights.readMemory.contains(address) ? .read : .changed)
            changes.append(.init(layer: .memory, field: "RAM\(address)", title: "RAM \(hex(address))",
                                 before: byte(before.memory[address]), after: byte(after.memory[address]), access: access))
        }
        func add(_ layer: GuidedLayer, _ field: String, _ title: String, _ previous: String, _ current: String,
                 read: Bool = false, written: Bool = false) {
            guard previous != current || read || written else { return }
            changes.append(.init(layer: layer, field: field, title: title, before: previous, after: current,
                                 access: written ? .write : (read ? .read : .changed)))
            if layer == .cpu { highlights.cpuFields.insert(field) }
            if layer == .os { highlights.osFields.insert(field) }
        }
        let cpu: [(String, String, String, String)] = [
            ("pc", "Program counter", hex(before.pc), hex(after.pc)),
            ("stackPointer", "Stack pointer", hex(before.stackPointer), hex(after.stackPointer)),
            ("zeroFlag", "Zero flag", bit(before.zeroFlag), bit(after.zeroFlag)),
            ("carryFlag", "Carry flag", bit(before.carryFlag), bit(after.carryFlag)),
            ("phase", "Completed phase", before.phase.title, after.phase.title),
            ("nextPhase", "Next phase", before.nextPhase.title, after.nextPhase.title),
            ("cycleCount", "Microcycles", String(before.cycleCount), String(after.cycleCount)),
            ("instructionCount", "Instructions completed", String(before.instructionCount), String(after.instructionCount)),
            ("alu", "ALU result", alu(before.lastALU), alu(after.lastALU))
        ]
        for (field, title, previous, current) in cpu {
            add(.cpu, field, title, previous, current, read: readCPU.contains(field), written: writtenCPU.contains(field))
        }
        add(.assembly, "fetchedBytes", "Latched bytes", bytes(before.fetchedBytes), bytes(after.fetchedBytes),
            read: phase == .decode, written: phase == .fetch && event.bus?.kind == .instructionFetch)
        add(.assembly, "decodedInstruction", "Decoded instruction", before.currentInstruction?.description ?? "None",
            after.currentInstruction?.description ?? "None", read: phase == .execute,
            written: phase == .decode && after.currentInstruction != nil)
        let callRead = [.trap, .kernel, .driver, .returnToUser].contains(phase)
        var privilegeRead = false
        if phase == .execute, let instruction {
            switch instruction.opcode {
            case .sys, .input, .output: privilegeRead = true
            case .ld, .st: privilegeRead = MemoryMap.framebuffer.contains(Int(instruction.b))
            case .ldx, .stx: privilegeRead = MemoryMap.framebuffer.contains(Int(before.registers[Int(instruction.b)]))
            default: break
            }
        }
        if phase == .driver, let service = before.syscall?.service, [1, 7].contains(service) { privilegeRead = true }
        add(.os, "privilege", "Privilege", before.privilege.title, after.privilege.title,
            read: privilegeRead, written: [.trap, .returnToUser].contains(phase))
        add(.os, "service", "Service", service(before.syscall), service(after.syscall), read: callRead)
        add(.os, "arguments", "Captured arguments", arguments(before.syscall), arguments(after.syscall), read: callRead)
        add(.os, "consoleValue", "Console byte", byte(before.consoleValue), byte(after.consoleValue),
            written: event.bus?.kind == .deviceWrite && event.bus?.address == MemoryMap.consolePort)
        add(.os, "consoleByteCount", "Console bytes emitted", String(before.consoleByteCount), String(after.consoleByteCount))
        add(.os, "droppedConsoleByteCount", "Console bytes discarded", String(before.droppedConsoleByteCount), String(after.droppedConsoleByteCount))
        add(.os, "console", "Console output", before.console, after.console)
        add(.os, "inputValue", "Input switch", byte(before.inputValue), byte(after.inputValue),
            read: event.bus?.kind == .deviceRead && event.bus?.address == MemoryMap.inputPort)
        if let bus = event.bus, let value = bus.value {
            if bus.kind == .deviceRead && bus.address == MemoryMap.inputPort {
                add(.os, "inputPort", "Input port 0", byte(before.inputValue), byte(value), read: true)
            }
            if bus.kind == .deviceWrite && bus.address == MemoryMap.consolePort {
                add(.os, "consolePort", "Console port 1", byte(before.consoleValue), byte(value), written: true)
            }
            if phase == .driver && before.syscall?.service == 5 && bus.kind == .deviceRead {
                add(.os, "ticks", "Clock ticks modulo 256", byte(before.ticks), byte(value), read: true)
            }
        }
        add(.os, "watchdogCheckIns", "Watchdog check-ins", String(before.watchdogCheckIns), String(after.watchdogCheckIns),
            written: phase == .driver && before.syscall?.service == 8)
        add(.cpu, "halted", "Stopped", bit(before.halted), bit(after.halted))
        add(.cpu, "fault", "Fault", before.fault ?? "None", after.fault ?? "None")
        return (highlights, changes)
    }

    private static func hex(_ value: Int) -> String { String(format: "0x%02X", value) }
    private static func byte(_ value: UInt8) -> String { "\(hex(Int(value))) · \(value)" }
    private static func bit(_ value: Bool) -> String { value ? "1" : "0" }
    private static func bytes(_ values: [UInt8]) -> String { values.isEmpty ? "None" : values.map { hex(Int($0)) }.joined(separator: " ") }
    private static func service(_ call: SystemCall?) -> String { call.map { "SYS \($0.service) · \($0.name)" } ?? "None" }
    private static func arguments(_ call: SystemCall?) -> String {
        call.map { $0.arguments.enumerated().map { "R\($0.offset)=\(byte($0.element))" }.joined(separator: ", ") } ?? "None"
    }
    private static func alu(_ record: ALURecord?) -> String {
        record.map { "\($0.operation): \($0.left), \($0.right) → \($0.result)" } ?? "None"
    }
}
