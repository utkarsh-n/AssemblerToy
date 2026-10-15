import XCTest
@testable import AssemblerCore

final class AssemblerCoreTests: XCTestCase {
    private func machine(_ source: String, mode: ExecutionMode = .bareMetal) throws -> Machine {
        Machine(program: try Assembler.assemble(source), mode: mode)
    }
    private func finish(_ initial: Machine, limit: Int = 1_000) -> Machine {
        var machine = initial
        for _ in 0..<limit {
            if machine.isFinished { break }
            machine.stepInstruction()
        }
        return machine
    }

    func testEveryOpcodeRoundTripsThroughActualEncoderAndDecoder() throws {
        let source = """
        NOP
        LDI R0, 0xff
        MOV R1, R0
        ADD R1, R0
        SUB R1, R0
        AND R1, R0
        OR R1, R0
        XOR R1, R0
        SHL R1
        LD R1, 128
        ST R1, 128
        LDX R1, R0
        STX R1, R0
        CMP R1, R0
        JMP start
        JZ start
        JNZ start
        PUSH R1
        POP R1
        CALL start
        RET
        IN R1
        OUT R1
        SYS 1
        HALT
        INC R1
        start: DEC R1
        """
        let program = try Assembler.assemble(source)
        XCTAssertEqual(Set(program.instructions.map(\.instruction.opcode)), Set(Opcode.allCases))
        XCTAssertEqual(program.bytes.count, 256)
        for row in program.instructions {
            let bytes = Array(program.bytes[row.address..<(row.address + 4)])
            XCTAssertEqual(try Decoder.decode(bytes), row.instruction)
        }
    }

    func testLabelsCommentsNumbersAndSourceMetadata() throws {
        let program = try Assembler.assemble("; header\nstart: ldi r0, 0b101 ; five\nLDI R1, 0X0A\nJMP end\nend: HALT")
        XCTAssertEqual(program.labels["start"], 0)
        XCTAssertEqual(program.labels["end"], 12)
        XCTAssertEqual(program.instructions.first?.lineNumber, 2)
        XCTAssertEqual(program.instructions.first?.instruction.b, 5)
        XCTAssertEqual(program.instructions[1].instruction.b, 10)
        XCTAssertEqual(program.instructions[2].instruction.a, 12)
        XCTAssertTrue(program.instructions[0].source.contains("five"))
    }

    func testWindowsNewlinesKeepHumanLineNumbers() throws {
        let program = try Assembler.assemble("; header\r\nLDI R0, 3\r\nHALT")
        XCTAssertEqual(program.instructions.map(\.lineNumber), [2, 3])
    }

    func testSixtyFourDataBytesArePlacedAtTheirActualAddresses() throws {
        let values = (0..<64).map(String.init).joined(separator: ",")
        let program = try Assembler.assemble("HALT\n.org 128\nsprite: .byte \(values)")
        XCTAssertEqual(program.labels["sprite"], 128)
        XCTAssertEqual(program.dataBytes, (0..<64).map(UInt8.init))
        XCTAssertEqual(program.bytes[191], 63)
        XCTAssertEqual(program.bytes[192], 0)
    }

    func testHelpfulDiagnosticsAccumulateWithCorrectLines() {
        do {
            _ = try Assembler.assemble("LDI R4, 1\nNOPE\nJMP missing\nLDI R0, -1\nSYS 9")
            XCTFail("Expected diagnostics")
        } catch let error as AssemblerError {
            XCTAssertEqual(Set(error.diagnostics.map(\.lineNumber)), Set([1, 2, 3, 4, 5]))
            XCTAssertTrue(error.localizedDescription.contains("R0...R3"))
            XCTAssertTrue(error.localizedDescription.contains("missing"))
            XCTAssertTrue(error.localizedDescription.contains("0...255"))
        } catch { XCTFail("Wrong error: \(error)") }
    }

    func testInvalidAssemblyBoundariesAndOperandsAreRejected() {
        let invalid = [
            "", "NOP 1", "LDI R0, 256", "LDI R0, +1", "LDI R0, 0x", "LDI R0, 0b2",
            "JMP 3", "JMP 128", "a: NOP\na: HALT", "1bad: HALT", "SYS 0",
            Array(repeating: "NOP", count: 33).joined(separator: "\n"),
            "HALT\n.byte 1", "HALT\n.org 191\n.byte 1,2", "HALT\n.org 128\n.org 0",
            "HALT\n.org 128\n.byte -1", "HALT\n.org 128\n.byte", "HALT\n.org 256"
        ]
        for source in invalid { XCTAssertThrowsError(try Assembler.assemble(source), source) }
        XCTAssertNoThrow(try Assembler.assemble(Array(repeating: "NOP", count: 32).joined(separator: "\n")))
    }

    func testDecoderRejectsMalformedInstructionBytes() {
        let invalid: [[UInt8]] = [[], [0], [255, 0, 0, 0], [0, 0, 0, 1], [0, 1, 0, 0], [1, 4, 0, 0], [2, 0, 4, 0], [8, 0, 1, 0], [14, 3, 0, 0], [23, 0, 0, 0]]
        for bytes in invalid { XCTAssertThrowsError(try Decoder.decode(bytes), String(describing: bytes)) }
    }

    func testMicrophasesFetchActualRAMBytes() throws {
        var model = try machine("LDI R0, 12\nHALT")
        XCTAssertEqual(model.step()?.phase, .fetch)
        XCTAssertEqual(model.fetchedBytes, [Opcode.ldi.rawValue, 0, 12, 0])
        XCTAssertEqual(model.bus?.kind, .instructionFetch)
        XCTAssertEqual(model.registers[0], 0)
        XCTAssertEqual(model.step()?.phase, .decode)
        XCTAssertEqual(model.currentInstruction?.description, "LDI R0, 12")
        XCTAssertEqual(model.registers[0], 0)
        XCTAssertEqual(model.step()?.phase, .execute)
        XCTAssertEqual(model.registers[0], 12)
        XCTAssertEqual(model.pc, 4)
        XCTAssertEqual(model.instructionCount, 1)
    }

    func testWrapCarryZeroAndBorrow() throws {
        var model = try machine("LDI R0, 255\nLDI R1, 1\nADD R0, R1\nSUB R0, R1\nINC R0\nDEC R0\nHALT")
        model.stepInstruction(); model.stepInstruction(); model.stepInstruction()
        XCTAssertEqual(model.registers[0], 0)
        XCTAssertTrue(model.zeroFlag); XCTAssertTrue(model.carryFlag)
        XCTAssertEqual(model.lastALU?.left, 255); XCTAssertEqual(model.lastALU?.right, 1)
        model.stepInstruction()
        XCTAssertEqual(model.registers[0], 255)
        XCTAssertFalse(model.zeroFlag); XCTAssertTrue(model.carryFlag)
        model.stepInstruction()
        XCTAssertEqual(model.registers[0], 0); XCTAssertTrue(model.zeroFlag); XCTAssertTrue(model.carryFlag)
        model.stepInstruction()
        XCTAssertEqual(model.registers[0], 255); XCTAssertTrue(model.carryFlag)
    }

    func testBitwiseOperationsAndShiftCarry() throws {
        var model = try machine("LDI R0, 170\nLDI R1, 85\nOR R0, R1\nAND R0, R1\nXOR R0, R1\nLDI R0, 128\nSHL R0\nHALT")
        model.stepInstruction(); model.stepInstruction(); model.stepInstruction()
        XCTAssertEqual(model.registers[0], 255)
        model.stepInstruction(); XCTAssertEqual(model.registers[0], 85)
        model.stepInstruction(); XCTAssertEqual(model.registers[0], 0); XCTAssertTrue(model.zeroFlag)
        model.stepInstruction(); model.stepInstruction()
        XCTAssertEqual(model.registers[0], 0); XCTAssertTrue(model.zeroFlag); XCTAssertTrue(model.carryFlag)
    }

    func testCompareDoesNotOverwriteRegisterAndBranchesUseFlags() throws {
        let model = finish(try machine("LDI R0, 9\nLDI R1, 9\nCMP R0, R1\nJZ equal\nLDI R2, 99\nequal: LDI R2, 7\nJNZ end\nLDI R3, 2\nend: HALT"))
        XCTAssertEqual(model.registers, [9, 9, 7, 2])
        XCTAssertTrue(model.zeroFlag)
        XCTAssertNil(model.fault)
    }

    func testMemoryDirectAndIndirectReadsAndWrites() throws {
        let model = finish(try machine("LDI R0, 83\nST R0, 128\nLD R1, 128\nLDI R2, 129\nSTX R1, R2\nLDX R3, R2\nHALT"))
        XCTAssertEqual(model.registers, [83, 83, 129, 83])
        XCTAssertEqual(model.memory[128], 83); XCTAssertEqual(model.memory[129], 83)
        XCTAssertTrue(model.trace.contains(where: { $0.bus?.kind == .memoryWrite && $0.bus?.address == 129 }))
    }

    func testProgramCanModifyFutureInstructionBytes() throws {
        let model = finish(try machine("LDI R0, 7\nST R0, 18\nJMP target\nHALT\ntarget: LDI R1, 2\nHALT"))
        XCTAssertEqual(model.program.bytes[18], 2)
        XCTAssertEqual(model.memory[18], 7)
        XCTAssertEqual(model.registers[1], 7)
        XCTAssertNil(model.fault)
    }

    func testExternalEditDoesNotChangeAlreadyFetchedInstruction() throws {
        var model = try machine("LDI R0, 2\nHALT")
        model.step()
        try model.editMemory(at: 2, value: 7)
        model.stepInstruction()
        XCTAssertEqual(model.registers[0], 2)
        model.reset()
        try model.editMemory(at: 2, value: 7)
        model.stepInstruction()
        XCTAssertEqual(model.registers[0], 7)
    }

    func testMalformedSelfModifiedCodeFaultsInDecoder() throws {
        var model = try machine("HALT")
        try model.editMemory(at: 0, value: 255)
        model.stepInstruction()
        XCTAssertEqual(model.phase, .fault)
        XCTAssertTrue(model.fault?.contains("opcode") == true)
        XCTAssertEqual(model.instructionCount, 0)
    }

    func testUserMemoryProtectionIncludesDirectAndIndirectDisplayAccess() throws {
        for source in ["LDI R0, 3\nST R0, 192", "LD R0, 192", "LDI R1, 192\nLDX R0, R1", "LDI R0, 1\nLDI R1, 255\nSTX R0, R1"] {
            let model = finish(try machine(source, mode: .user))
            XCTAssertNotNil(model.fault, source)
            XCTAssertTrue(model.fault?.contains("User code") == true)
            XCTAssertEqual(model.framebuffer, [UInt8](repeating: 0, count: 64))
        }
        let allowed = finish(try machine("LDI R0, 83\nST R0, 191\nLD R1, 191\nHALT", mode: .user))
        XCTAssertNil(allowed.fault); XCTAssertEqual(allowed.registers[1], 83)
    }

    func testBareMetalAndOSPixelHaveSameFunctionalOutput() throws {
        let bare = finish(Machine(program: try ExampleCatalog.examples[0].assemble(), mode: .bareMetal))
        let user = finish(Machine(program: try ExampleCatalog.examples[1].assemble(), mode: .user))
        XCTAssertEqual(bare.framebuffer, user.framebuffer)
        XCTAssertEqual(user.framebuffer[27], 3)
        XCTAssertNil(user.fault)
        XCTAssertEqual(user.privilege, .user)
    }

    func testSyscallHasDistinctPrivilegeAndDriverPhases() throws {
        var model = try machine("LDI R0, 27\nLDI R1, 3\nSYS 1\nHALT", mode: .user)
        model.stepInstruction(); model.stepInstruction()
        XCTAssertEqual(model.step()?.phase, .fetch)
        XCTAssertEqual(model.step()?.phase, .decode)
        XCTAssertEqual(model.step()?.phase, .execute)
        XCTAssertEqual(model.privilege, .user); XCTAssertEqual(model.framebuffer[27], 0)
        XCTAssertEqual(model.step()?.phase, .trap)
        XCTAssertEqual(model.privilege, .kernel)
        XCTAssertEqual(model.bus?.kind, .trap)
        XCTAssertEqual(model.step()?.phase, .kernel)
        XCTAssertEqual(model.framebuffer[27], 0)
        XCTAssertEqual(model.step()?.phase, .driver)
        XCTAssertEqual(model.framebuffer[27], 3)
        XCTAssertEqual(model.bus?.address, 219)
        XCTAssertEqual(model.bus?.privilege, .kernel)
        XCTAssertEqual(model.step()?.phase, .returnToUser)
        XCTAssertEqual(model.privilege, .user)
        XCTAssertEqual(model.instructionCount, 3)
        XCTAssertNil(model.syscall)
    }

    func testSyscallValidationFaultsBeforeAnyDeviceWrite() throws {
        for source in ["LDI R0, 64\nSYS 1", "LDI R1, 8\nSYS 1", "LDI R0, 8\nSYS 2", "LDI R0, 128\nSYS 4"] {
            let model = finish(try machine(source, mode: .user))
            XCTAssertNotNil(model.fault)
            XCTAssertEqual(model.framebuffer, [UInt8](repeating: 0, count: 64))
            XCTAssertEqual(model.console, "")
            XCTAssertFalse(model.trace.contains(where: { $0.phase == .driver }))
        }
    }

    func testEverySyscallServiceAndReturnValues() throws {
        var model = try machine("LDI R0, 2\nSYS 2\nSYS 3\nMOV R2, R0\nLDI R0, 65\nSYS 4\nSYS 5\nSYS 6\nLDI R3, 99", mode: .user)
        model.setInput(1 as UInt8)
        model = finish(model)
        XCTAssertNil(model.fault); XCTAssertTrue(model.halted)
        XCTAssertEqual(model.framebuffer, [UInt8](repeating: 2, count: 64))
        XCTAssertEqual(model.registers[2], 1)
        XCTAssertEqual(model.console, "A")
        XCTAssertGreaterThan(model.registers[0], 0)
        XCTAssertEqual(model.registers[3], 0)
        XCTAssertEqual(model.privilege, .user)
    }

    func testUncheckedDriverDrawsValidIndexThenPanicsPastRAM() throws {
        let example = try XCTUnwrap(ExampleCatalog.examples.first(where: { $0.id == "kernel-panic" }))
        let model = finish(Machine(program: try example.assemble(), mode: example.mode))
        XCTAssertEqual(model.framebuffer[27], 5)
        let panic = try XCTUnwrap(model.panic)
        XCTAssertEqual(panic.kind, .kernelDataAbort)
        XCTAssertEqual(panic.faultAddress, 262)
        XCTAssertEqual(panic.instructionAddress, 16)
        XCTAssertTrue(panic.log.contains("far: 0x106"))
        XCTAssertTrue(model.fault?.hasPrefix("Kernel panic") == true)
        XCTAssertEqual(model.phase, .fault); XCTAssertEqual(model.privilege, .kernel)
        XCTAssertFalse(model.halted)
        XCTAssertTrue(model.trace.last?.message.hasPrefix("Panic:") == true)
        XCTAssertEqual(model.memory.count, MemoryMap.size)
    }

    func testCheckedServiceFaultsWithoutPanicForTheSameIndex() throws {
        let model = finish(try machine("LDI R0, 27\nLDI R1, 5\nSYS 1\nLDI R0, 70\nSYS 1\nHALT", mode: .user))
        XCTAssertEqual(model.framebuffer[27], 5)
        XCTAssertNotNil(model.fault); XCTAssertNil(model.panic)
        XCTAssertFalse(model.trace.contains(where: { $0.phase == .driver && $0.message.contains("70") }))
    }

    func testWatchdogStaysOffUntilTheFirstCheckIn() throws {
        let example = try XCTUnwrap(ExampleCatalog.examples.first(where: { $0.id == "button-loop" }))
        let model = finish(Machine(program: try example.assemble(), mode: example.mode))
        XCTAssertNil(model.watchdogDeadline); XCTAssertNil(model.panic); XCTAssertNil(model.fault)
    }

    func testWatchdogCheckInsKeepTheLoopAliveAndAHangPanicsAfterTheTimeout() throws {
        let example = try XCTUnwrap(ExampleCatalog.examples.first(where: { $0.id == "watchdog-hang" }))
        var model = finish(Machine(program: try example.assemble(), mode: example.mode), limit: 300)
        XCTAssertNil(model.fault); XCTAssertEqual(model.framebuffer, [UInt8](repeating: 4, count: 64))
        XCTAssertGreaterThan(model.watchdogCheckIns, 10)
        model.setInput(true)
        var lastCheckIn = model.lastWatchdogCheckIn
        for _ in 0..<500 where !model.isFinished {
            model.step()
            if model.panic == nil { lastCheckIn = model.lastWatchdogCheckIn }
        }
        let panic = try XCTUnwrap(model.panic)
        XCTAssertEqual(panic.kind, .watchdogTimeout)
        XCTAssertEqual(model.cycleCount, try XCTUnwrap(lastCheckIn) + Machine.watchdogTimeout + 1)
        XCTAssertTrue(panic.reason.contains("no check-ins in 32 microcycles"))
        XCTAssertTrue(panic.log.contains("\(model.watchdogCheckIns) total check-ins"))
        XCTAssertEqual(model.pc, 28)

        model.reset()
        XCTAssertNil(model.panic); XCTAssertNil(model.fault)
        XCTAssertNil(model.lastWatchdogCheckIn); XCTAssertEqual(model.watchdogCheckIns, 0)
        XCTAssertEqual(model.inputValue, 1)
    }

    func testBarePortsAndUserPortProtection() throws {
        var bare = try machine("IN R0\nLDI R1, 65\nOUT R1\nHALT")
        bare.setInput(7 as UInt8)
        bare = finish(bare)
        XCTAssertEqual(bare.registers[0], 7); XCTAssertEqual(bare.console, "A")
        for source in ["IN R0", "OUT R0"] {
            XCTAssertNotNil(finish(try machine(source, mode: .user)).fault)
        }
    }

    func testButtonLoopRespondsToInputChanges() throws {
        let example = try XCTUnwrap(ExampleCatalog.examples.first(where: { $0.id == "button-loop" }))
        var model = Machine(program: try example.assemble(), mode: example.mode)
        for _ in 0..<20 { model.stepInstruction() }
        XCTAssertEqual(model.framebuffer[27], 0)
        model.setInput(true)
        for _ in 0..<20 { model.stepInstruction() }
        XCTAssertEqual(model.framebuffer[27], 3)
        model.setInput(false)
        for _ in 0..<20 { model.stepInstruction() }
        XCTAssertEqual(model.framebuffer[27], 0)
        XCTAssertNil(model.fault)
    }

    func testStackSubroutineAndConsole() throws {
        let example = try XCTUnwrap(ExampleCatalog.examples.first(where: { $0.id == "stack-console" }))
        var model = Machine(program: try example.assemble(), mode: example.mode)
        model.stepInstruction()
        XCTAssertEqual(model.stackPointer, 191); XCTAssertEqual(model.memory[191], 4)
        XCTAssertEqual(model.pc, 8)
        model = finish(model)
        XCTAssertEqual(model.console, "HI")
        XCTAssertEqual(model.stackPointer, 192)
        XCTAssertEqual(model.registers[0], 0)
        XCTAssertNil(model.fault)
    }

    func testStackUnderflowOverflowAndInvalidReturnAddress() throws {
        XCTAssertTrue(finish(try machine("POP R0")).fault?.contains("underflow") == true)
        XCTAssertTrue(finish(try machine("RET")).fault?.contains("underflow") == true)
        let overflow = finish(try machine("LDI R0, 1\nloop: PUSH R0\nJMP loop"), limit: 200)
        XCTAssertEqual(overflow.stackPointer, 128)
        XCTAssertTrue(overflow.fault?.contains("overflow") == true)
        XCTAssertTrue(finish(try machine("LDI R0, 3\nPUSH R0\nRET")).fault?.contains("invalid code") == true)
    }

    func testProgramCounterBoundaryFaultsInsteadOfReadingDataAsCode() throws {
        let source = Array(repeating: "NOP", count: 32).joined(separator: "\n")
        let model = finish(try machine(source))
        XCTAssertEqual(model.instructionCount, 32)
        XCTAssertTrue(model.fault?.contains("PC 128") == true)
    }

    func testMemoryRegisterAndDisplayEditBounds() throws {
        var model = try machine("HALT")
        XCTAssertThrowsError(try model.editMemory(at: -1, value: 0))
        XCTAssertThrowsError(try model.editMemory(at: 256, value: 0))
        XCTAssertThrowsError(try model.editRegister(4, value: 0))
        XCTAssertThrowsError(try model.editRegister(-1, value: 0))
        try model.editMemory(at: 255, value: 7)
        try model.editRegister(3, value: 255)
        XCTAssertEqual(model.framebuffer.last, 7)
        XCTAssertEqual(model.registers[3], 255)
        XCTAssertNil(finish(try machine("LDI R0, 8\nST R0, 192\nHALT")).fault)
    }

    func testBareMetalDisplayAndProbeKeepAllEightRawBits() throws {
        var model = finish(try machine("LDI R0, 255\nST R0, 192\nHALT"))
        XCTAssertNil(model.fault)
        XCTAssertEqual(model.memory[192], 255)
        XCTAssertEqual(model.framebuffer[0], 255)
        XCTAssertEqual(model.framebuffer[0] & 7, 7)
        try model.editMemory(at: 193, value: 128)
        XCTAssertEqual(model.framebuffer[1], 128)
        XCTAssertEqual(model.framebuffer[1] & 7, 0)
    }

    /// Exact instruction strings and data formatting emitted by
    /// App/Views/SpriteComposerView.swift's generatedSource at integration time.
    private func generatedSpriteSource(_ pixels: [UInt8], mode: ExecutionMode) -> String {
        let program: String
        if mode == .user {
            program = """
            ; Your drawing → OS display driver
            LDI R0, 0
            LDI R2, 128
            LDI R3, 64
            draw:
              LDX R1, R2
              SYS 1
              INC R0
              INC R2
              DEC R3
              JNZ draw
            HALT
            """
        } else {
            program = """
            ; Your drawing → physical framebuffer
            LDI R0, 192
            LDI R2, 128
            LDI R3, 64
            draw:
              LDX R1, R2
              STX R1, R0
              INC R0
              INC R2
              DEC R3
              JNZ draw
            HALT
            """
        }
        let data = (0..<8).map { row in
            ".byte " + pixels[(row * 8)..<(row * 8 + 8)].map(String.init).joined(separator: ", ")
        }.joined(separator: "\n")
        return program + "\n\n; Sprite data, one row at a time\n.org 128\n" + data + "\n"
    }

    func testExactGeneratedOSSpriteWritesEveryPixelAndTerminates() throws {
        let pixels: [UInt8] = (0..<64).map { (index: Int) -> UInt8 in
            let rowOffset = (index / 8) * 3
            let value = index * 5 + rowOffset
            return UInt8(value % 8)
        }
        let program = try Assembler.assemble(generatedSpriteSource(pixels, mode: .user))
        let model = finish(Machine(program: program, mode: .user), limit: 400)
        XCTAssertEqual(program.instructions.count, 10)
        XCTAssertEqual(program.labels["draw"], 12)
        XCTAssertTrue(model.halted); XCTAssertNil(model.fault)
        XCTAssertEqual(model.framebuffer, pixels)
        XCTAssertEqual(Array(model.memory[128..<192]), pixels)
        XCTAssertEqual(Array(model.memory[0..<128]), program.codeBytes)
        XCTAssertEqual(model.registers, [64, pixels[63], 192, 0])
        XCTAssertEqual(model.instructionCount, 388)
        XCTAssertEqual(model.pc, 40)
        XCTAssertEqual(model.stackPointer, 192)
        XCTAssertTrue(model.zeroFlag); XCTAssertFalse(model.carryFlag)
        XCTAssertEqual(model.privilege, .user)
    }

    func testExactGeneratedBareSpriteWritesEveryPixelAndWrapsPointer() throws {
        let pixels: [UInt8] = (0..<64).map { (index: Int) -> UInt8 in
            let rowOffset = (index / 8) * 5
            let value = index * 3 + rowOffset + 1
            return UInt8(value % 8)
        }
        let program = try Assembler.assemble(generatedSpriteSource(pixels, mode: .bareMetal))
        let model = finish(Machine(program: program, mode: .bareMetal), limit: 400)
        XCTAssertEqual(program.instructions.count, 10)
        XCTAssertTrue(model.halted); XCTAssertNil(model.fault)
        XCTAssertEqual(model.framebuffer, pixels)
        XCTAssertEqual(Array(model.memory[128..<192]), pixels)
        XCTAssertEqual(Array(model.memory[0..<128]), program.codeBytes)
        XCTAssertEqual(model.registers, [0, pixels[63], 192, 0])
        XCTAssertEqual(model.instructionCount, 388)
        XCTAssertEqual(model.pc, 40)
        XCTAssertEqual(model.stackPointer, 192)
        XCTAssertTrue(model.zeroFlag); XCTAssertFalse(model.carryFlag)
        XCTAssertEqual(model.privilege, .bareMetal)
    }

    func testSyscallCapturesArgumentRegistersAtExecuteAndInputAtDriver() throws {
        var model = try machine("LDI R0, 27\nLDI R1, 3\nSYS 1\nSYS 3\nHALT", mode: .user)
        model.stepInstruction(); model.stepInstruction()
        model.step(); model.step(); model.step() // SYS execute captures arguments.
        try model.editRegister(0, value: 63)
        try model.editRegister(1, value: 7)
        model.stepInstruction()
        XCTAssertEqual(model.framebuffer[27], 3)
        XCTAssertEqual(model.framebuffer[63], 0)
        model.setInput(false)
        for _ in 0..<5 { model.step() } // Through SYS 3 kernel; driver is next.
        XCTAssertEqual(model.nextPhase, .driver)
        model.setInput(true)
        XCTAssertEqual(model.step()?.phase, .driver)
        XCTAssertEqual(model.registers[0], 1)
        model.stepInstruction()
        XCTAssertNil(model.fault)
        XCTAssertEqual(model.privilege, .user)
    }

    func testOrgCannotSilentlyOverlapCodeOrProduceUnalignedInstructions() {
        for source in ["NOP\n.org 0\nHALT", "NOP\n.org 5\nHALT", "HALT\n.org 128\nLDI R0, 1"] {
            XCTAssertThrowsError(try Assembler.assemble(source))
        }
    }

    func testSyscallReturnValueDoesNotChangeALUFlagsBeforeBranch() throws {
        var model = try machine("LDI R0, 0\nLDI R1, 0\nCMP R0, R1\nSYS 3\nJZ equal\nLDI R2, 99\nequal: LDI R2, 7\nHALT", mode: .user)
        model.setInput(true)
        model = finish(model)
        XCTAssertNil(model.fault)
        XCTAssertEqual(model.registers[0], 1)
        XCTAssertEqual(model.registers[2], 7)
        XCTAssertTrue(model.zeroFlag)
        XCTAssertEqual(model.lastALU?.operation, "CMP")
    }

    func testFullSpriteDataExplicitlySharesAndCanBeOverwrittenByStack() throws {
        let pixels = [UInt8](repeating: 7, count: 64)
        let source = "LDI R0, 83\nPUSH R0\nHALT\n.org 128\n.byte " + pixels.map(String.init).joined(separator: ",")
        let model = finish(try machine(source))
        XCTAssertEqual(model.program.dataBytes[63], 7)
        XCTAssertEqual(model.memory[191], 83)
        XCTAssertEqual(model.stackPointer, 191)
        XCTAssertEqual(Array(model.memory[128..<191]), Array(pixels.dropLast()))
    }

    func testSnapshotRestoresMidSyscallStateExactly() throws {
        var model = try machine("LDI R0, 3\nSYS 2\nHALT", mode: .user)
        model.stepInstruction()
        for _ in 0..<4 { model.step() }
        let snapshot = model
        let forward = model.step()
        let after = model
        model = snapshot
        XCTAssertEqual(model.step(), forward)
        XCTAssertEqual(model, after)
    }

    func testResetAndLoadRestoreBytesButKeepPhysicalInput() throws {
        var model = try machine("LDI R0, 4\nHALT", mode: .user)
        model.setInput(true)
        model = finish(model)
        try model.editMemory(at: 128, value: 7)
        model.reset()
        XCTAssertEqual(model.registers, [0,0,0,0]); XCTAssertEqual(model.memory[128], 0)
        XCTAssertEqual(model.inputValue, 1); XCTAssertEqual(model.mode, .user)
        XCTAssertEqual(model.trace, []); XCTAssertEqual(model.cycleCount, 0)
        model.load(program: try Assembler.assemble("HALT"), mode: .bareMetal)
        XCTAssertEqual(model.mode, .bareMetal); XCTAssertEqual(model.privilege, .bareMetal)
        XCTAssertEqual(model.inputValue, 1)
    }

    func testFinishedMachineRemainsUnchanged() throws {
        var model = finish(try machine("HALT"))
        let snapshot = model
        XCTAssertNil(model.step())
        XCTAssertEqual(model.stepInstruction(), [])
        XCTAssertEqual(model, snapshot)
    }

    func testAllCatalogProgramsAssembleAndRunWithinBound() throws {
        for example in ExampleCatalog.examples {
            let model = finish(Machine(program: try example.assemble(), mode: example.mode), limit: 800)
            if example.id == "kernel-panic" {
                XCTAssertEqual(model.panic?.kind, .kernelDataAbort)
            } else {
                XCTAssertNil(model.fault, example.name)
                if ["button-loop", "watchdog-hang"].contains(example.id) { XCTAssertFalse(model.halted) }
                else { XCTAssertTrue(model.halted, example.name) }
            }
            if example.id == "data-sprite" { XCTAssertEqual(model.framebuffer, model.program.dataBytes) }
            XCTAssertLessThanOrEqual(model.trace.count, 384)
        }
    }
}
