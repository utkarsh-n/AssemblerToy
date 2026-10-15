import Foundation
import AssemblerCore

/// A compact account of an actual interpreter transfer, or an explicitly named
/// next-phase preview. Device ports never masquerade as RAM addresses.
struct ExecutionCue: Sendable, Equatable {
    let source: String
    let action: String
    let destination: String
    let detail: String
    let sourceSymbol: String
    let destinationSymbol: String

    init(machine: Machine, step: GuidedInstructionStep?) {
        if let panic = machine.panic {
            self.init(source: panic.kind == .watchdogTimeout ? "Watchdog" : "Kernel driver", action: "Panicked",
                      destination: "Whole machine", detail: panic.reason,
                      sourceSymbol: panic.kind == .watchdogTimeout ? "timer" : "shield.lefthalf.filled",
                      destinationSymbol: "exclamationmark.octagon")
            return
        }
        if let fault = machine.fault {
            self.init(source: "\(step?.executedPhase.title ?? "CPU")", action: "Stopped",
                      destination: "Fault", detail: fault,
                      sourceSymbol: "cpu", destinationSymbol: "exclamationmark.triangle")
            return
        }
        guard let step else {
            self = Self.preview(machine)
            return
        }
        let before = step.before, after = step.after
        let instruction = before.currentInstruction
        let call = step.capturedSystemCall
        let message = step.event.message
        if after.halted {
            self.init(source: call?.service == 6 ? "SYS 6" : "HALT", action: "Stopped",
                      destination: "CPU", detail: message,
                      sourceSymbol: "stop.circle", destinationSymbol: "cpu")
            return
        }
        if let bus = step.bus {
            switch bus.kind {
            case .instructionFetch:
                let address = bus.address ?? step.highlights.instructionAddress
                self.init(source: "RAM \(Self.hex(address))–\(Self.hex(address + 3))",
                          action: "Fetched", destination: "Instruction latch", detail: message,
                          sourceSymbol: "memorychip", destinationSymbol: "cpu")
                return
            case .memoryRead, .memoryWrite:
                let address = bus.address.map { "RAM \(Self.hex($0))" } ?? "RAM"
                let register: String
                if instruction?.opcode == .call {
                    register = "Return PC \(Self.hex((before.currentInstructionAddress ?? before.pc) + 4))"
                } else if instruction?.opcode == .ret {
                    register = "PC \(Self.hex(after.pc))"
                } else {
                    register = instruction.map { "R\($0.a)" } ?? "CPU"
                }
                let reading = bus.kind == .memoryRead
                self.init(source: reading ? address : register,
                          action: reading ? "Read" : "Written", destination: reading ? register : address,
                          detail: message, sourceSymbol: reading ? "memorychip" : "cpu",
                          destinationSymbol: reading ? "cpu" : "memorychip")
                return
            case .deviceRead, .deviceWrite:
                self = Self.deviceCue(step, call: call)
                return
            case .trap:
                self.init(source: "\(call?.callerPrivilege.title ?? "Caller") · SYS \(call?.service ?? bus.value ?? 0)",
                          action: "Trapped", destination: "Kernel", detail: message,
                          sourceSymbol: "cpu", destinationSymbol: "shield.lefthalf.filled")
                return
            }
        }
        switch step.executedPhase {
        case .decode:
            self.init(source: "Latched bytes", action: "Decoded",
                      destination: after.currentInstruction?.description ?? "Decoder",
                      detail: message, sourceSymbol: "barcode", destinationSymbol: "cpu")
        case .kernel:
            self.init(source: "SYS \(call?.service ?? 0)", action: "Validated",
                      destination: call?.name ?? "Driver action", detail: message,
                      sourceSymbol: "shield.lefthalf.filled", destinationSymbol: "gearshape")
        case .driver:
            self.init(source: "Kernel", action: "Dispatched", destination: call?.name ?? "Driver",
                      detail: message, sourceSymbol: "shield.lefthalf.filled", destinationSymbol: "gearshape")
        case .returnToUser:
            self.init(source: "Kernel", action: "Returned", destination: "\(after.privilege.title) · PC \(Self.hex(after.pc))",
                      detail: message, sourceSymbol: "shield.lefthalf.filled", destinationSymbol: "cpu")
        case .execute:
            self = Self.execution(step, instruction: instruction)
        default:
            self.init(source: "CPU", action: step.executedPhase.title, destination: "Next \(after.nextPhase.title)",
                      detail: message, sourceSymbol: "cpu", destinationSymbol: "arrow.right.circle")
        }
    }

    private init(source: String, action: String, destination: String, detail: String,
                 sourceSymbol: String, destinationSymbol: String) {
        self.source = source; self.action = action; self.destination = destination
        self.detail = detail; self.sourceSymbol = sourceSymbol; self.destinationSymbol = destinationSymbol
    }

    private static func preview(_ machine: Machine) -> Self {
        if machine.halted {
            return .init(source: "Program", action: "Stopped", destination: "CPU",
                         detail: "The machine is halted. Its current state remains inspectable.",
                         sourceSymbol: "stop.circle", destinationSymbol: "cpu")
        }
        switch machine.nextPhase {
        case .fetch:
            return .init(source: "RAM at PC \(hex(machine.pc))", action: "Next: Fetch",
                         destination: "Instruction latch", detail: "The next phase will read four bytes. They have not been fetched yet.",
                         sourceSymbol: "memorychip", destinationSymbol: "cpu")
        case .decode:
            return .init(source: "Latched bytes", action: "Next: Decode", destination: "Decoder",
                         detail: "The decoder will validate the bytes already held in the instruction latch.",
                         sourceSymbol: "barcode", destinationSymbol: "cpu")
        case .execute:
            return .init(source: machine.currentInstruction?.description ?? "Decoded instruction",
                         action: "Next: Execute", destination: "CPU",
                         detail: "The instruction is decoded. Its effect has not executed yet.",
                         sourceSymbol: "barcode", destinationSymbol: "cpu")
        case .trap:
            return .init(source: "SYS \(machine.syscall?.service ?? 0)", action: "Next: Trap", destination: "Kernel",
                         detail: "The request has captured its arguments. Privilege changes during Trap.",
                         sourceSymbol: "cpu", destinationSymbol: "shield.lefthalf.filled")
        case .kernel:
            return .init(source: "SYS \(machine.syscall?.service ?? 0)", action: "Next: Kernel", destination: "Service validation",
                         detail: "The kernel will validate this request before a driver action.",
                         sourceSymbol: "shield.lefthalf.filled", destinationSymbol: "gearshape")
        case .driver:
            return .init(source: "Kernel", action: "Next: Driver", destination: machine.syscall?.name ?? "Device service",
                         detail: "The validated action is ready for its driver phase.",
                         sourceSymbol: "shield.lefthalf.filled", destinationSymbol: "gearshape")
        case .returnToUser:
            return .init(source: "Kernel", action: "Next: Return", destination: machine.syscall?.callerPrivilege.title ?? "Caller",
                         detail: "Return restores the caller’s privilege and completes this instruction.",
                         sourceSymbol: "shield.lefthalf.filled", destinationSymbol: "cpu")
        case .halted, .fault:
            return .init(source: "Program", action: "Stopped", destination: "CPU",
                         detail: machine.nextPhase.explanation, sourceSymbol: "stop.circle", destinationSymbol: "cpu")
        }
    }

    private static func deviceCue(_ step: GuidedInstructionStep, call: SystemCall?) -> Self {
        let bus = step.bus!
        let reading = bus.kind == .deviceRead
        let device: String
        let symbol: String
        if let address = bus.address, MemoryMap.framebuffer.contains(address) {
            device = step.executedPhase == .driver && call?.service == 2
                ? "Display RAM 0xC0–FF" : "Display RAM \(hex(address))"
            symbol = "display"
        } else if bus.address == MemoryMap.inputPort {
            device = "Input port 0"; symbol = "switch.2"
        } else if bus.address == MemoryMap.consolePort {
            device = "Console port 1"; symbol = "text.alignleft"
        } else if call?.service == 8 {
            device = "Watchdog timer"; symbol = "timer"
        } else {
            device = "Clock device"; symbol = "clock"
        }
        let register = step.executedPhase == .driver ? "R0" : step.before.currentInstruction.map { "R\($0.a)" } ?? "CPU"
        let producer = step.executedPhase == .driver ? "Trusted driver" : register
        return .init(source: reading ? device : producer, action: reading ? "Read" : "Written",
                     destination: reading ? register : device, detail: step.event.message,
                     sourceSymbol: reading ? symbol : "cpu", destinationSymbol: reading ? "cpu" : symbol)
    }

    private static func execution(_ step: GuidedInstructionStep, instruction: Instruction?) -> Self {
        let message = step.event.message
        guard let instruction else {
            return .init(source: "Decoder", action: "Execute", destination: "CPU", detail: message,
                         sourceSymbol: "barcode", destinationSymbol: "cpu")
        }
        let a = Int(instruction.a), b = Int(instruction.b)
        switch instruction.opcode {
        case .ldi:
            return .init(source: "Immediate \(instruction.b)", action: "Copied", destination: "R\(a) = \(step.after.registers[a])",
                         detail: message, sourceSymbol: "number", destinationSymbol: "cpu")
        case .mov:
            return .init(source: "R\(b) = \(step.before.registers[b])", action: "Copied", destination: "R\(a) = \(step.after.registers[a])",
                         detail: message, sourceSymbol: "cpu", destinationSymbol: "cpu")
        case .add, .sub, .and, .or, .xor, .cmp, .shl, .inc, .dec:
            return .init(source: instruction.opcode.operandCount == 2 ? "R\(a) · R\(b)" : "R\(a)",
                         action: instruction.mnemonic, destination: instruction.opcode == .cmp ? "Z · C flags" : "R\(a) · flags",
                         detail: message, sourceSymbol: "cpu", destinationSymbol: "function")
        case .jmp, .jz, .jnz:
            return .init(source: instruction.opcode == .jmp ? "Jump \(hex(a))" : "Zero flag \(step.before.zeroFlag ? 1 : 0)",
                         action: instruction.mnemonic, destination: "PC \(hex(step.after.pc))", detail: message,
                         sourceSymbol: "arrow.branch", destinationSymbol: "cpu")
        case .sys:
            return .init(source: "R0–R3", action: "Captured", destination: "SYS \(instruction.a)", detail: message,
                         sourceSymbol: "cpu", destinationSymbol: "shield.lefthalf.filled")
        case .nop:
            return .init(source: "NOP", action: "Advanced", destination: "PC \(hex(step.after.pc))", detail: message,
                         sourceSymbol: "barcode", destinationSymbol: "cpu")
        default:
            return .init(source: instruction.mnemonic, action: "Executed", destination: "CPU", detail: message,
                         sourceSymbol: "barcode", destinationSymbol: "cpu")
        }
    }

    private static func hex(_ value: Int) -> String { String(format: "0x%02X", value) }
}
