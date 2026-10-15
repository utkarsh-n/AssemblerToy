import Foundation

/// AT-8 is a deliberately small teaching ISA, not ARM assembly or an iOS kernel.
/// Instructions are four bytes: opcode, operand A, operand B, and a reserved zero byte.
/// RAM and registers contain bytes. Arithmetic wraps modulo 256. There is no JIT or
/// native execution; this model interprets the actual bytes fetched from its RAM.
public enum MemoryMap {
    public static let size = 256
    public static let instructionSize = 4
    public static let code = 0..<128
    public static let data = 128..<192
    public static let framebuffer = 192..<256
    public static let stackBottom = 128
    public static let stackTop = 191
    public static let screenWidth = 8
    public static let screenHeight = 8
    public static let inputPort = 0
    public static let consolePort = 1
}

public enum ExecutionMode: String, CaseIterable, Identifiable, Sendable, Equatable {
    case bareMetal
    case user
    public var id: String { rawValue }
    public var title: String { self == .bareMetal ? "Bare metal" : "User + OS" }
}

public enum Privilege: String, Sendable, Equatable {
    case bareMetal, user, kernel
    public var title: String {
        switch self {
        case .bareMetal: "Bare metal"
        case .user: "User"
        case .kernel: "Kernel"
        }
    }
}

public enum MicroPhase: String, CaseIterable, Identifiable, Sendable, Equatable {
    case fetch, decode, execute, trap, kernel, driver, returnToUser, halted, fault
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .returnToUser: "Return"
        default: rawValue.capitalized
        }
    }
    public var explanation: String {
        switch self {
        case .fetch: "The CPU reads four instruction bytes from RAM at the program counter."
        case .decode: "The decoder turns those bytes into an opcode and validated operands."
        case .execute: "The CPU performs the decoded instruction."
        case .trap: "SYS transfers control into the model kernel and saves user state."
        case .kernel: "The kernel validates the requested service and chooses a driver action."
        case .driver: "A trusted driver touches the display or input/output port."
        case .returnToUser: "The kernel restores privilege and resumes the next instruction."
        case .halted: "The program stopped. Reset it or edit and reassemble its source."
        case .fault: "The machine stopped because an operation violated the model's rules."
        }
    }
}

public enum Opcode: UInt8, CaseIterable, Sendable, Equatable {
    case nop = 0, ldi, mov, add, sub, and, or, xor, shl, ld, st, ldx, stx, cmp
    case jmp, jz, jnz, push, pop, call, ret, input, output, sys, halt, inc, dec
    public var mnemonic: String {
        switch self {
        case .input: "IN"
        case .output: "OUT"
        default: String(describing: self).uppercased()
        }
    }
    public var operandCount: Int {
        switch self {
        case .nop, .ret, .halt: 0
        case .shl, .jmp, .jz, .jnz, .push, .pop, .call, .input, .output, .sys, .inc, .dec: 1
        default: 2
        }
    }
    public var explanation: String {
        switch self {
        case .nop: "Do nothing and advance to the next instruction."
        case .ldi: "Copy an immediate byte into a register."
        case .mov: "Copy the second register into the first."
        case .add: "Add two registers; wrap at 256 and report overflow as carry."
        case .sub: "Subtract the second register; carry reports a borrow."
        case .and: "Keep bits that are 1 in both registers."
        case .or: "Keep bits that are 1 in either register."
        case .xor: "Keep bits that differ between the registers."
        case .shl: "Shift left by one bit; the outgoing top bit becomes carry."
        case .ld: "Read one RAM byte at an immediate address."
        case .st: "Write one register byte at an immediate RAM address."
        case .ldx: "Read one RAM byte at the address held by the second register."
        case .stx: "Write the first register at the address held by the second register."
        case .cmp: "Compare by subtracting for flags, without changing a register."
        case .jmp: "Jump to an aligned instruction address."
        case .jz: "Jump when the last ALU result was zero."
        case .jnz: "Jump when the last ALU result was nonzero."
        case .push: "Push a register byte onto the descending data-RAM stack."
        case .pop: "Pop a byte from the stack into a register."
        case .call: "Push the return address and jump to a subroutine."
        case .ret: "Pop and jump to the saved return address."
        case .input: "Read the isolated input port; requires bare-metal privilege."
        case .output: "Write ASCII to the isolated console port; requires bare-metal privilege."
        case .sys: "Request a kernel service through a visible trap, kernel, driver, and return."
        case .halt: "Stop execution."
        case .inc: "Increment a register modulo 256 and update flags."
        case .dec: "Decrement a register modulo 256 and update flags."
        }
    }
}

public struct Instruction: Sendable, Equatable {
    public let opcode: Opcode
    public let a: UInt8
    public let b: UInt8
    public let c: UInt8
    public init(opcode: Opcode, a: UInt8 = 0, b: UInt8 = 0, c: UInt8 = 0) {
        self.opcode = opcode; self.a = a; self.b = b; self.c = c
    }
    public var bytes: [UInt8] { [opcode.rawValue, a, b, c] }
    public var mnemonic: String { opcode.mnemonic }
    public var operandDescription: String {
        switch opcode {
        case .nop, .ret, .halt: ""
        case .ldi: "R\(a), \(b)"
        case .ld, .st: "R\(a), \(b)"
        case .mov, .add, .sub, .and, .or, .xor, .ldx, .stx, .cmp: "R\(a), R\(b)"
        case .shl, .push, .pop, .input, .output, .inc, .dec: "R\(a)"
        case .jmp, .jz, .jnz, .call, .sys: "\(a)"
        }
    }
    public var description: String { operandDescription.isEmpty ? mnemonic : "\(mnemonic) \(operandDescription)" }
}

public struct InstructionRow: Identifiable, Sendable, Equatable {
    public var id: Int { address }
    public let address: Int
    public let lineNumber: Int
    public let source: String
    public let instruction: Instruction
    public var bytes: [UInt8] { instruction.bytes }
}

public struct Program: Sendable, Equatable {
    public let source: String
    /// A complete 256-byte initial RAM image, including the optional data section.
    public let bytes: [UInt8]
    public let instructions: [InstructionRow]
    public let labels: [String: UInt8]
    public var dataBytes: [UInt8] { Array(bytes[MemoryMap.data]) }
    public var codeBytes: [UInt8] { Array(bytes[MemoryMap.code]) }
    public var instructionCount: Int { instructions.count }
}

public struct AssemblyDiagnostic: Identifiable, Sendable, Equatable {
    public var id: String { "\(lineNumber):\(message)" }
    public let lineNumber: Int
    public let message: String
    public var description: String { "Line \(lineNumber): \(message)" }
}

public struct AssemblerError: Error, LocalizedError, Sendable, Equatable {
    public let diagnostics: [AssemblyDiagnostic]
    public var errorDescription: String? { diagnostics.map(\.description).joined(separator: "\n") }
}

public struct MachineError: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum PanicKind: String, Sendable, Equatable {
    case kernelDataAbort, watchdogTimeout
    public var title: String {
        switch self {
        case .kernelDataAbort: "Kernel data abort"
        case .watchdogTimeout: "Watchdog timeout"
        }
    }
    public var explanation: String {
        switch self {
        case .kernelDataAbort: "Trusted kernel code used an address that does not exist. A user mistake is caught by the kernel; a kernel mistake has nothing above it to catch it, so the whole machine stops."
        case .watchdogTimeout: "Once monitoring starts, the watchdog expects regular check-ins. The machine stopped making progress, so the watchdog stopped the whole machine rather than let it hang forever."
        }
    }
}

/// A whole-machine stop. A fault is a rule the kernel or CPU enforces on a program;
/// a panic means the kernel itself, or the watchdog that guards it, gave up.
public struct KernelPanic: Sendable, Equatable {
    public let kind: PanicKind
    public let reason: String
    public let cycle: UInt64
    public let pc: Int
    public let instructionAddress: Int?
    /// The missing address a kernel data abort tried to use, like a real panic's `far` register.
    public let faultAddress: Int?
    public let watchdogCheckIns: Int
    /// A short panic log in the shape of a real one: `panic(cpu 0 caller …): reason`.
    public var log: String {
        var lines = ["panic(cpu 0 caller \(kind == .watchdogTimeout ? "watchdog" : "kernel")): \(reason)"]
        if let faultAddress { lines.append(String(format: "far: 0x%03X (RAM ends at 0x0FF)", faultAddress)) }
        lines.append("pc: \(instructionAddress ?? pc) · cycle \(cycle)")
        if kind == .watchdogTimeout { lines.append("\(watchdogCheckIns) total check-ins since monitoring enabled") }
        lines.append("Reset reboots the machine.")
        return lines.joined(separator: "\n")
    }
}

public enum BusKind: String, Sendable, Equatable {
    case instructionFetch, memoryRead, memoryWrite, deviceRead, deviceWrite, trap
    public var title: String {
        switch self {
        case .instructionFetch: "Instruction fetch"
        case .memoryRead: "RAM read"
        case .memoryWrite: "RAM write"
        case .deviceRead: "Device read"
        case .deviceWrite: "Device write"
        case .trap: "System call"
        }
    }
}

public struct BusActivity: Sendable, Equatable {
    public let kind: BusKind
    /// RAM addresses for memory/framebuffer traffic; port numbers for IN/OUT traffic.
    public let address: Int?
    public let value: UInt8?
    public let privilege: Privilege
    public let description: String
}

public struct ALURecord: Sendable, Equatable {
    public let operation: String
    public let left: UInt8
    public let right: UInt8
    public let result: UInt8
    /// For subtraction and comparison, carry means a borrow; for addition it means overflow.
    public let carry: Bool
    public let zero: Bool
    public var a: UInt8 { left }
    public var b: UInt8 { right }
}

public struct TraceEvent: Identifiable, Sendable, Equatable {
    public let id: UInt64
    public let phase: MicroPhase
    public let message: String
    public let instructionAddress: Int?
    public let bus: BusActivity?
    public let privilege: Privilege
}

public struct MachineExample: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let summary: String
    public let goals: [String]
    public let source: String
    public let mode: ExecutionMode
    public func assemble() throws -> Program { try Assembler.assemble(source) }
}
