import Foundation

public enum Decoder {
    /// Validates every operand, including reserved bytes. Malformed machine code faults.
    public static func decode(_ bytes: [UInt8]) throws -> Instruction {
        guard bytes.count == 4 else { throw MachineError("An instruction needs exactly four bytes.") }
        guard let op = Opcode(rawValue: bytes[0]) else { throw MachineError("Unknown opcode \(bytes[0]).") }
        let a = bytes[1], b = bytes[2], c = bytes[3]
        guard c == 0 else { throw MachineError("Reserved instruction byte must be zero.") }
        func register(_ value: UInt8) throws {
            guard value < 4 else { throw MachineError("Register R\(value) does not exist; use R0...R3.") }
        }
        func unused(_ value: UInt8) throws {
            guard value == 0 else { throw MachineError("Unused operand bytes must be zero for \(op.mnemonic).") }
        }
        switch op {
        case .nop, .ret, .halt: try unused(a); try unused(b)
        case .ldi, .ld, .st: try register(a)
        case .mov, .add, .sub, .and, .or, .xor, .ldx, .stx, .cmp: try register(a); try register(b)
        case .shl, .push, .pop, .input, .output, .inc, .dec: try register(a); try unused(b)
        case .jmp, .jz, .jnz, .call:
            guard a < 128, a % 4 == 0 else { throw MachineError("Branch target \(a) must be an aligned address in code RAM (0...124).") }
            try unused(b)
        case .sys:
            guard (1...8).contains(a) else { throw MachineError("SYS service must be 1...8.") }
            try unused(b)
        }
        return Instruction(opcode: op, a: a, b: b, c: c)
    }
}

public enum Assembler {
    private struct Pending {
        let line: Int
        let address: Int
        let original: String
        let operation: String
        let operands: [String]
    }

    /// Two passes resolve forward labels and encode AT-8's actual RAM image.
    /// `.org` moves forward; `.byte` is permitted only in data RAM 128...191.
    public static func assemble(_ source: String) throws -> Program {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var location = 0
        var labels: [String: UInt8] = [:]
        var pending: [Pending] = []
        var diagnostics: [AssemblyDiagnostic] = []
        var instructionTotal = 0
        func report(_ line: Int, _ message: String) { diagnostics.append(.init(lineNumber: line, message: message)) }
        for (index, original) in lines.enumerated() {
            let line = index + 1
            var content = String(original.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]).trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            if let colon = content.firstIndex(of: ":") {
                let name = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
                if !validLabel(name) { report(line, "Invalid label '\(name)'; use letters, digits, and underscores, starting with a letter or underscore.") }
                else if labels[name] != nil { report(line, "Label '\(name)' is defined more than once.") }
                else if location > 191 { report(line, "Label '\(name)' is outside code and data RAM.") }
                else { labels[name] = UInt8(location) }
                content = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if content.isEmpty { continue }
            }
            let pieces = content.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            guard let head = pieces.first else { continue }
            let op = head.uppercased()
            let operands = Array(pieces.dropFirst())
            if op == ".ORG" {
                guard operands.count == 1, let target = number(operands[0]), target <= 191 else {
                    report(line, ".org needs one address from 0...191."); continue
                }
                guard target >= location else { report(line, ".org must move forward to avoid overlapping bytes."); continue }
                location = target
                continue
            }
            if op == ".BYTE" {
                if operands.isEmpty { report(line, ".byte needs at least one byte value.") }
                if location < 128 || location + operands.count > 192 { report(line, "Data bytes must fit in addresses 128...191; start the data section with .org 128.") }
                pending.append(.init(line: line, address: location, original: original, operation: op, operands: operands))
                location += operands.count
                continue
            }
            if !Opcode.allCases.contains(where: { $0.mnemonic == op }) { report(line, "Unknown instruction '\(head)'.") }
            if location >= 128 || location % 4 != 0 || location + 4 > 128 { report(line, "Instructions must fit at aligned code addresses 0...124; the machine holds at most 32 instructions.") }
            instructionTotal += 1
            pending.append(.init(line: line, address: location, original: original, operation: op, operands: operands))
            location += 4
        }
        if instructionTotal == 0 { report(1, "Add at least one instruction, such as HALT.") }
        var image = [UInt8](repeating: 0, count: MemoryMap.size)
        var rows: [InstructionRow] = []
        for entry in pending {
            if entry.operation == ".BYTE" {
                for (offset, token) in entry.operands.enumerated() {
                    guard let value = number(token), value <= 255 else { report(entry.line, "'\(token)' is not a byte; use decimal, 0x hex, or 0b binary in 0...255."); continue }
                    let address = entry.address + offset
                    if MemoryMap.data.contains(address) { image[address] = UInt8(value) }
                }
                continue
            }
            guard let op = Opcode.allCases.first(where: { $0.mnemonic == entry.operation }) else { continue }
            guard entry.operands.count == op.operandCount else { report(entry.line, "\(op.mnemonic) expects \(op.operandCount) operand\(op.operandCount == 1 ? "" : "s"); received \(entry.operands.count).") ; continue }
            func reg(_ token: String) throws -> UInt8 {
                let name = token.uppercased()
                guard name.count == 2, name.first == "R", let value = Int(name.dropFirst()), value < 4 else { throw MachineError("'\(token)' is not a register; use R0...R3.") }
                return UInt8(value)
            }
            func immediate(_ token: String) throws -> UInt8 {
                guard let value = number(token), value <= 255 else { throw MachineError("'\(token)' is not a byte; use decimal, 0x hex, or 0b binary in 0...255.") }
                return UInt8(value)
            }
            func target(_ token: String) throws -> UInt8 {
                if let value = labels[token] { return value }
                if let value = number(token), value <= 255 { return UInt8(value) }
                throw MachineError("Unknown label '\(token)'.")
            }
            do {
                var a: UInt8 = 0, b: UInt8 = 0
                switch op {
                case .nop, .ret, .halt: break
                case .ldi, .ld, .st: a = try reg(entry.operands[0]); b = try immediate(entry.operands[1])
                case .mov, .add, .sub, .and, .or, .xor, .ldx, .stx, .cmp: a = try reg(entry.operands[0]); b = try reg(entry.operands[1])
                case .shl, .push, .pop, .input, .output, .inc, .dec: a = try reg(entry.operands[0])
                case .jmp, .jz, .jnz, .call: a = try target(entry.operands[0])
                case .sys: a = try immediate(entry.operands[0])
                }
                let instruction = try Decoder.decode([op.rawValue, a, b, 0])
                if entry.address >= 0, entry.address + 4 <= 128 {
                    image.replaceSubrange(entry.address..<(entry.address + 4), with: instruction.bytes)
                    rows.append(.init(address: entry.address, lineNumber: entry.line, source: entry.original.trimmingCharacters(in: .whitespaces), instruction: instruction))
                }
            } catch { report(entry.line, error.localizedDescription) }
        }
        guard diagnostics.isEmpty else { throw AssemblerError(diagnostics: diagnostics) }
        return Program(source: source, bytes: image, instructions: rows, labels: labels)
    }

    private static func number(_ token: String) -> Int? {
        guard !token.isEmpty else { return nil }
        let lowered = token.lowercased()
        let digits: Substring, radix: Int
        if lowered.hasPrefix("0x") { digits = lowered.dropFirst(2); radix = 16 }
        else if lowered.hasPrefix("0b") { digits = lowered.dropFirst(2); radix = 2 }
        else { digits = lowered[...]; radix = 10 }
        guard !digits.isEmpty, digits.allSatisfy({ c in
            switch radix {
            case 2: c == "0" || c == "1"
            case 16: ("0"..."9").contains(String(c)) || ("a"..."f").contains(String(c))
            default: ("0"..."9").contains(String(c))
            }
        }) else { return nil }
        return Int(digits, radix: radix)
    }

    private static func validLabel(_ value: String) -> Bool {
        let chars = Array(value.utf8)
        guard let first = chars.first, first == 95 || (65...90).contains(first) || (97...122).contains(first) else { return false }
        return chars.allSatisfy { $0 == 95 || (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }
    }
}
