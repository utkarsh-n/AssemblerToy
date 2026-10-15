import XCTest
@testable import AssemblerCore

/// Reproducible stress checks: fixed seeds, exact iteration bounds, no timing gates.
final class StressTests: XCTestCase {
    private struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next() >> 24) }
        mutating func index(_ count: Int) -> Int { Int(next() % UInt64(count)) }
    }

    private func assertInvariants(_ machine: Machine, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(machine.memory.count, 256, file: file, line: line)
        XCTAssertEqual(machine.registers.count, 4, file: file, line: line)
        XCTAssertTrue((128...192).contains(machine.stackPointer), file: file, line: line)
        XCTAssertTrue((0...128).contains(machine.pc), file: file, line: line)
        XCTAssertEqual(machine.pc % 4, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(machine.trace.count, 384, file: file, line: line)
        XCTAssertLessThanOrEqual(machine.console.utf8.count, Machine.consoleCapacity, file: file, line: line)
        XCTAssertEqual(machine.consoleByteCount, UInt64(machine.console.utf8.count) + machine.droppedConsoleByteCount, file: file, line: line)
    }

    func testLongRunningLoopKeepsCPUAndTraceBoundedAcrossTickWraps() throws {
        var machine = Machine(program: try Assembler.assemble("loop: INC R0\nJMP loop"))
        for _ in 0..<100_000 { machine.stepInstruction() }
        XCTAssertFalse(machine.isFinished)
        XCTAssertEqual(machine.instructionCount, 100_000)
        XCTAssertEqual(machine.cycleCount, 300_000)
        XCTAssertEqual(machine.registers[0], UInt8(truncatingIfNeeded: 50_000))
        XCTAssertEqual(machine.pc, 0)
        XCTAssertEqual(machine.ticks, UInt8(truncatingIfNeeded: 300_000))
        XCTAssertEqual(machine.trace.count, 384)
        XCTAssertEqual(machine.trace.first?.id, machine.cycleCount - 383)
        XCTAssertEqual(machine.trace.last?.id, machine.cycleCount)
        XCTAssertEqual(Set(machine.trace.map(\.id)).count, 384)
        assertInvariants(machine)
    }

    func testConsoleOutputLoopsKeepAnExactBoundedTailAndResetCounts() throws {
        let configurations: [(ExecutionMode, String)] = [
            (.bareMetal, "LDI R0, 65\nloop: OUT R0\nJMP loop"),
            (.user, "LDI R0, 65\nloop: SYS 4\nJMP loop")
        ]
        for (mode, source) in configurations {
            var machine = Machine(program: try Assembler.assemble(source), mode: mode)
            machine.stepInstruction()
            for _ in 0..<20_000 {
                machine.stepInstruction()
                machine.stepInstruction()
            }
            XCTAssertNil(machine.fault)
            XCTAssertEqual(machine.consoleByteCount, 20_000)
            XCTAssertEqual(machine.droppedConsoleByteCount, UInt64(20_000 - Machine.consoleCapacity))
            XCTAssertEqual(machine.console, String(repeating: "A", count: Machine.consoleCapacity))
            XCTAssertEqual(machine.consoleValue, 65)
            assertInvariants(machine)
            machine.reset()
            XCTAssertEqual(machine.console, "")
            XCTAssertEqual(machine.consoleByteCount, 0)
            XCTAssertEqual(machine.droppedConsoleByteCount, 0)
        }
    }

    func testConsoleTailMatchesRawASCIISuffixIncludingCRLFGraphemes() throws {
        var machine = Machine(program: try Assembler.assemble("loop: OUT R0\nJMP loop"))
        let count = Machine.consoleCapacity * 3 + 17
        let expected = (0..<count).map { UInt8($0 % 128) }
        for value in expected {
            try machine.editRegister(0, value: value)
            machine.stepInstruction()
            machine.stepInstruction()
        }
        XCTAssertEqual(Array(machine.console.utf8), Array(expected.suffix(Machine.consoleCapacity)))
        XCTAssertEqual(machine.consoleByteCount, UInt64(count))
        XCTAssertEqual(machine.droppedConsoleByteCount, UInt64(count - Machine.consoleCapacity))
        assertInvariants(machine)
    }

    func testRewindAcrossConsoleTruncationAndKernelPhasesReplaysExactly() throws {
        var machine = Machine(program: try Assembler.assemble("LDI R0, 65\nloop: SYS 4\nJMP loop"), mode: .user)
        machine.stepInstruction()
        for _ in 0..<(Machine.consoleCapacity - 3) {
            machine.stepInstruction(); machine.stepInstruction()
        }
        let checkpoint = machine
        var states: [Machine] = []
        for _ in 0..<240 {
            machine.step()
            states.append(machine)
        }
        XCTAssertEqual(checkpoint.consoleByteCount, UInt64(Machine.consoleCapacity - 3))
        XCTAssertEqual(checkpoint.droppedConsoleByteCount, 0)
        XCTAssertGreaterThan(machine.droppedConsoleByteCount, 0)
        machine = checkpoint
        for expected in states {
            machine.step()
            XCTAssertEqual(machine, expected)
        }
        XCTAssertEqual(checkpoint.console.utf8.count, Machine.consoleCapacity - 3)
        XCTAssertEqual(checkpoint.droppedConsoleByteCount, 0)
        assertInvariants(machine)
    }

    func testSavedSnapshotsRemainIndependentUnderRegisterRAMInputAndByteEdits() throws {
        var machine = Machine(program: try Assembler.assemble("loop: SYS 3\nMOV R1, R0\nINC R2\nJMP loop"), mode: .user)
        var snapshots: [Machine] = []
        var random = Random(state: 0xA55E_B1E7)
        for step in 0..<5_000 {
            machine.setInput(random.byte())
            if step % 7 == 0 { try machine.editMemory(at: 128 + random.index(64), value: random.byte()) }
            if step % 13 == 0 { try machine.editRegister(3, value: random.byte()) }
            machine.step()
            if step % 100 == 0 { snapshots.append(machine) }
        }
        for checkpoint in snapshots {
            var first = checkpoint
            var second = checkpoint
            for _ in 0..<40 { first.step(); second.step() }
            XCTAssertEqual(first, second)
            XCTAssertNotEqual(first.cycleCount, checkpoint.cycleCount)
            assertInvariants(first)
            assertInvariants(checkpoint)
        }
        XCTAssertNil(machine.fault)
    }

    private func validBytes(_ opcode: Opcode, random: inout Random) -> [UInt8] {
        var a: UInt8 = 0, b: UInt8 = 0
        switch opcode {
        case .nop, .ret, .halt: break
        case .ldi, .ld, .st: a = UInt8(random.index(4)); b = random.byte()
        case .mov, .add, .sub, .and, .or, .xor, .ldx, .stx, .cmp:
            a = UInt8(random.index(4)); b = UInt8(random.index(4))
        case .shl, .push, .pop, .input, .output, .inc, .dec: a = UInt8(random.index(4))
        case .jmp, .jz, .jnz, .call: a = UInt8(random.index(32) * 4)
        case .sys: a = UInt8(random.index(6) + 1)
        }
        return [opcode.rawValue, a, b, 0]
    }

    func testTenThousandValidInstructionMutationsHaveOnlyModeledOutcomes() throws {
        let program = try Assembler.assemble("HALT")
        var random = Random(state: 0xCAFE_88F0)
        for index in 0..<10_000 {
            let mode: ExecutionMode = index.isMultiple(of: 2) ? .bareMetal : .user
            var machine = Machine(program: program, mode: mode)
            let opcode = Opcode.allCases[index % Opcode.allCases.count]
            let bytes = validBytes(opcode, random: &random)
            XCTAssertEqual(try Decoder.decode(bytes).opcode, opcode)
            for register in 0..<4 { try machine.editRegister(register, value: random.byte()) }
            for (offset, byte) in bytes.enumerated() { try machine.editMemory(at: offset, value: byte) }
            let before = machine
            let events = machine.stepInstruction()
            XCTAssertFalse(events.isEmpty)
            XCTAssertLessThanOrEqual(events.count, 7)
            assertInvariants(machine)
            if machine.fault != nil { XCTAssertEqual(machine.phase, .fault) }
            if mode == .user, opcode == .st, bytes[2] >= 192 {
                XCTAssertNotNil(machine.fault)
                XCTAssertEqual(machine.framebuffer, before.framebuffer)
            }
            if mode == .user, opcode == .stx, before.registers[Int(bytes[2])] >= 192 {
                XCTAssertNotNil(machine.fault)
                XCTAssertEqual(machine.framebuffer, before.framebuffer)
            }
        }
    }

    func testTenThousandMalformedByteInstructionsFaultWithoutNativeCrashes() throws {
        let program = try Assembler.assemble("HALT")
        var random = Random(state: 0xBAD0_C0DE)
        for _ in 0..<10_000 {
            var machine = Machine(program: program)
            let bytes = [random.byte(), random.byte(), random.byte(), UInt8(random.index(255) + 1)]
            for (address, byte) in bytes.enumerated() { try machine.editMemory(at: address, value: byte) }
            machine.stepInstruction()
            XCTAssertNotNil(machine.fault)
            XCTAssertEqual(machine.instructionCount, 0)
            XCTAssertEqual(machine.cycleCount, 2)
            assertInvariants(machine)
        }
    }

    func testCatalogUnderRepeatedLoadResetInputAndReplay() throws {
        var machine = Machine(program: try ExampleCatalog.examples[0].assemble())
        for round in 0..<25 {
            for example in ExampleCatalog.examples {
                machine.load(program: try example.assemble(), mode: example.mode)
                for index in 0..<1_000 {
                    if index % 10 == 0 { machine.setInput((index + round) % 20 == 0) }
                    if machine.isFinished { break }
                    machine.stepInstruction()
                }
                switch example.id {
                case "kernel-panic": XCTAssertEqual(machine.panic?.kind, .kernelDataAbort)
                case "watchdog-hang":
                    // The switch pattern decides whether this round hangs; either way only the watchdog may stop it.
                    if let panic = machine.panic { XCTAssertEqual(panic.kind, .watchdogTimeout) }
                    else { XCTAssertNil(machine.fault); XCTAssertFalse(machine.halted) }
                case "button-loop": XCTAssertNil(machine.fault); XCTAssertFalse(machine.halted)
                default: XCTAssertNil(machine.fault, example.id); XCTAssertTrue(machine.halted)
                }
                assertInvariants(machine)
                let snapshot = machine
                machine.reset()
                XCTAssertEqual(machine.inputValue, snapshot.inputValue)
                XCTAssertEqual(machine.memory, machine.program.bytes)
                XCTAssertEqual(machine.cycleCount, 0)
                XCTAssertEqual(machine.consoleByteCount, 0)
            }
        }
    }

    func testMalformedAssemblyCorpusReportsDiagnosticsWithoutCrashes() {
        let corruptions = [
            "LDI R-1, 0", "LDI R99, 4", "LDI R0, 99999999999999999999999999999999999",
            "JMP missing_label", "SYS 255", "HALT\n.org 128\n.byte 0, 256",
            "HALT\n.org 128\n.byte 0xGG", "label: NOP\nlabel: HALT",
            "\0: HALT", "🙂: HALT", "NOP\n.org 1\nHALT", "RET 0",
            "HALT\n.org 192", "HALT\n.org 128\n.byte 1\n.org 128",
            "LD R0, 1e2", "LDI R0, 0b101010102", "STX R0", ".org"
        ]
        for _ in 0..<50 {
            for source in corruptions {
                do { _ = try Assembler.assemble(source); XCTFail("Accepted malformed input: \(source)") }
                catch let error as AssemblerError {
                    XCTAssertFalse(error.diagnostics.isEmpty)
                    XCTAssertTrue(error.diagnostics.allSatisfy { $0.lineNumber > 0 && !$0.message.isEmpty })
                } catch { XCTFail("Wrong error type: \(error)") }
            }
        }
        let source = Array(repeating: "UNKNOWN R0, 999999999999999999999999999999", count: 2_000).joined(separator: "\n")
        XCTAssertThrowsError(try Assembler.assemble(source)) { error in
            XCTAssertTrue((error as? AssemblerError)?.diagnostics.last?.lineNumber == 2_000)
        }
    }
}
