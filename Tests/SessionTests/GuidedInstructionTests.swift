import XCTest
import Foundation
@testable import AssemblerToy
import AssemblerCore

@MainActor
final class GuidedInstructionTests: XCTestCase {
    private func withSession(_ source: String, mode: ExecutionMode = .bareMetal,
                             _ body: (MachineSession) throws -> Void) throws {
        let suite = "AssemblerToy.GuidedTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let session = MachineSession(preferences: preferences)
        try session.assemble(source, mode: mode)
        try body(session)
    }

    @discardableResult
    private func next(_ session: MachineSession) throws -> GuidedInstructionStep {
        let before = session.machine
        var expected = before
        let event = try XCTUnwrap(expected.step())
        session.advanceGuidedInstruction()
        let step = try XCTUnwrap(session.guidedInstruction?.latestStep)
        XCTAssertEqual(step.before, before)
        XCTAssertEqual(step.after, expected)
        XCTAssertEqual(step.event, event)
        XCTAssertEqual(step.explanation, event.message)
        XCTAssertEqual(session.machine, expected)
        XCTAssertEqual(expected.cycleCount, before.cycleCount + 1)
        return step
    }

    private func finish(_ session: MachineSession) throws -> GuidedInstruction {
        for _ in 0..<16 {
            guard session.guidedInstruction?.canAdvance == true else { break }
            try next(session)
        }
        let guide = try XCTUnwrap(session.guidedInstruction)
        XCTAssertTrue(guide.isComplete)
        return guide
    }

    func testOrdinaryGuideBlocksAutoplayAndPublishesThreeActualPhases() throws {
        try withSession("LDI R0, 7\nHALT") { session in
            session.playbackSpeed = 0.5
            session.toggleRun()
            for _ in 0..<3 { session.advancePlayback(elapsed: 0.05) }
            let baseline = session.machine
            session.startGuidedInstruction()
            let guide = try XCTUnwrap(session.guidedInstruction)
            XCTAssertEqual(guide.baseline, baseline)
            XCTAssertEqual(guide.instructionAddress, 0)
            XCTAssertEqual(guide.executionBytes, session.program.instructions[0].bytes)
            XCTAssertTrue(guide.sourceMatchesExecution)
            XCTAssertFalse(guide.canPrevious)
            XCTAssertTrue(guide.canAdvance)
            XCTAssertFalse(session.running)
            session.toggleRun()
            session.tick()
            session.advancePlayback(elapsed: 100)
            session.step(micro: false)
            XCTAssertEqual(session.machine, baseline)
            XCTAssertTrue(session.history.isEmpty)

            let fetch = try next(session)
            XCTAssertEqual(fetch.executedPhase, .fetch)
            XCTAssertEqual(fetch.highlights.readMemory, [0, 1, 2, 3])
            XCTAssertTrue(fetch.highlights.changedMemory.isEmpty)
            XCTAssertTrue(fetch.changes.filter { $0.layer == .memory }.allSatisfy { $0.access == .read && !$0.didChange })
            let decode = try next(session)
            XCTAssertEqual(decode.executedPhase, .decode)
            XCTAssertEqual(decode.after.currentInstruction?.description, "LDI R0, 7")
            let execute = try next(session)
            XCTAssertEqual(execute.executedPhase, .execute)
            XCTAssertEqual(execute.after.registers[0], 7)
            XCTAssertEqual(execute.highlights.writtenRegisters, [0])
            XCTAssertEqual(execute.highlights.changedRegisters, [0])
            XCTAssertTrue(execute.changes.filter { $0.layer == .os }.isEmpty,
                          "A plain register immediate must not imply an OS operation.")
            XCTAssertTrue(session.guidedInstruction?.isComplete == true)
            XCTAssertEqual(session.machine.instructionCount, 1)
            XCTAssertEqual(session.history.count, 3)
            session.advanceGuidedInstruction()
            XCTAssertEqual(session.machine, execute.after)
            XCTAssertEqual(session.playbackSpeed, 0.5)
        }
    }

    func testUnchangedRegisterWriteStoreAndLoadRemainVisible() throws {
        try withSession("LDI R0, 0\nST R0, 128\nLD R0, 128\nHALT") { session in
            session.startGuidedInstruction()
            let immediate = try finish(session)
            let writtenZero = try XCTUnwrap(immediate.latestStep?.changes.first { $0.field == "R0" })
            XCTAssertEqual(writtenZero.access, .write)
            XCTAssertFalse(writtenZero.didChange)
            XCTAssertEqual(immediate.latestStep?.highlights.writtenRegisters, [0])
            XCTAssertTrue(immediate.latestStep?.highlights.changedRegisters.isEmpty == true)

            session.startGuidedInstruction()
            let store = try finish(session)
            let storeStep = try XCTUnwrap(store.latestStep)
            XCTAssertEqual(storeStep.highlights.readRegisters, [0])
            XCTAssertEqual(storeStep.highlights.writtenMemory, [128])
            XCTAssertTrue(storeStep.highlights.changedMemory.isEmpty)
            let unchangedStore = try XCTUnwrap(storeStep.changes.first { $0.field == "RAM128" })
            XCTAssertEqual(unchangedStore.access, .write)
            XCTAssertFalse(unchangedStore.didChange)

            session.startGuidedInstruction()
            let load = try finish(session)
            XCTAssertEqual(load.latestStep?.highlights.readMemory, [128])
            XCTAssertEqual(load.latestStep?.highlights.writtenRegisters, [0])
            XCTAssertTrue(load.latestStep?.highlights.changedRegisters.isEmpty == true)
            XCTAssertEqual(session.machine.instructionCount, 3)
        }
    }

    func testOperandReadsArithmeticFlagsAndBranchFollowActualExecution() throws {
        try withSession("MOV R1, R0\nCMP R0, R1\nJZ taken\nHALT\ntaken: NOP") { session in
            session.writeRegister(0, value: 255)
            session.startGuidedInstruction()
            let move = try finish(session)
            XCTAssertEqual(move.latestStep?.highlights.readRegisters, [0])
            XCTAssertEqual(move.latestStep?.highlights.writtenRegisters, [1])
            XCTAssertEqual(session.machine.registers[1], 255)
            session.startGuidedInstruction()
            let compare = try finish(session)
            XCTAssertEqual(compare.latestStep?.highlights.readRegisters, [0, 1])
            XCTAssertTrue(compare.latestStep?.highlights.writtenRegisters.isEmpty == true)
            XCTAssertTrue(session.machine.zeroFlag)
            XCTAssertTrue(compare.latestStep?.highlights.cpuFields.contains("zeroFlag") == true)
            XCTAssertEqual(session.machine.lastALU?.result, 0)
            session.startGuidedInstruction()
            let branch = try finish(session)
            XCTAssertEqual(session.machine.pc, 16)
            let flagRead = try XCTUnwrap(branch.latestStep?.changes.first { $0.field == "zeroFlag" })
            XCTAssertEqual(flagRead.access, .read)
            XCTAssertFalse(flagRead.didChange)
            XCTAssertTrue(branch.latestStep?.explanation.contains("taken") == true)
        }
        try withSession("INC R0\nHALT") { session in
            session.writeRegister(0, value: 255)
            session.startGuidedInstruction()
            let arithmetic = try finish(session)
            XCTAssertEqual(arithmetic.latestStep?.highlights.readRegisters, [0])
            XCTAssertEqual(arithmetic.latestStep?.highlights.writtenRegisters, [0])
            XCTAssertEqual(session.machine.registers[0], 0)
            XCTAssertTrue(session.machine.zeroFlag)
            XCTAssertTrue(session.machine.carryFlag)
            XCTAssertTrue(arithmetic.latestStep?.changes.contains { $0.field == "carryFlag" && $0.didChange } == true)
        }
    }

    func testSYSWalksSevenActualPhasesCapturesArgumentsAndWritesDisplayRAM() throws {
        try withSession("LDI R0, 27\nLDI R1, 3\nSYS 1\nHALT", mode: .user) { session in
            session.step(micro: false)
            session.step(micro: false)
            let baseline = session.machine
            session.startGuidedInstruction()
            XCTAssertEqual(session.guidedInstruction?.instructionAddress, 8)
            var steps: [GuidedInstructionStep] = []
            for _ in 0..<7 { steps.append(try next(session)) }
            XCTAssertEqual(steps.map(\.executedPhase), [.fetch, .decode, .execute, .trap, .kernel, .driver, .returnToUser])
            XCTAssertEqual(steps[2].capturedSystemCall?.arguments, [27, 3, 0, 0])
            XCTAssertEqual(steps[2].highlights.readRegisters, [0, 1, 2, 3])
            XCTAssertEqual(steps[2].after.pc, 12)
            XCTAssertEqual(steps[2].after.privilege, .user)
            XCTAssertEqual(steps[3].after.privilege, .kernel)
            XCTAssertEqual(steps[3].bus?.kind, .trap)
            XCTAssertTrue(steps[4].highlights.writtenMemory.isEmpty)
            XCTAssertEqual(steps[5].highlights.writtenMemory, [219])
            XCTAssertEqual(steps[5].highlights.changedMemory, [219])
            XCTAssertEqual(steps[5].after.memory[219], 3)
            XCTAssertEqual(steps[6].after.privilege, .user)
            XCTAssertNil(steps[6].after.syscall)
            XCTAssertEqual(steps[6].capturedSystemCall?.arguments, [27, 3, 0, 0])
            XCTAssertEqual(session.machine.instructionCount, baseline.instructionCount + 1)
            XCTAssertEqual(session.guidedInstruction?.steps.count, 7)
            XCTAssertTrue(session.guidedInstruction?.isComplete == true)
            session.previousGuidedStep()
            XCTAssertEqual(session.machine, steps[6].before)
            XCTAssertEqual(session.machine.privilege, .kernel)
            XCTAssertFalse(session.guidedInstruction?.isComplete == true)
            XCTAssertEqual(try next(session), steps[6])
        }
    }

    func testOtherServicesExposeActualDeviceOperationsWithoutInventingRAMPorts() throws {
        for service in 2...6 {
            try withSession("SYS \(service)\nHALT", mode: .user) { session in
                if service == 4 { session.writeRegister(0, value: 65) }
                session.startGuidedInstruction()
                let guide = try finish(session)
                XCTAssertEqual(guide.steps.count, 7)
                let driver = guide.steps[5]
                switch service {
                case 2:
                    XCTAssertEqual(driver.highlights.writtenMemory, Set(MemoryMap.framebuffer))
                    XCTAssertTrue(driver.highlights.changedMemory.isEmpty)
                    XCTAssertEqual(driver.changes.filter { $0.layer == .memory && $0.access == .write }.count, 64)
                case 3:
                    XCTAssertEqual(driver.highlights.writtenRegisters, [0])
                    XCTAssertTrue(driver.highlights.changedRegisters.isEmpty)
                    XCTAssertTrue(driver.highlights.readMemory.isEmpty)
                    XCTAssertEqual(driver.bus?.address, MemoryMap.inputPort)
                    XCTAssertTrue(driver.changes.contains { $0.field == "inputPort" && $0.access == .read && !$0.didChange })
                case 4:
                    XCTAssertEqual(driver.after.console, "A")
                    XCTAssertEqual(driver.after.consoleByteCount, 1)
                    XCTAssertTrue(driver.highlights.writtenMemory.isEmpty)
                    XCTAssertEqual(driver.bus?.address, MemoryMap.consolePort)
                    XCTAssertTrue(driver.changes.contains { $0.field == "consolePort" && $0.access == .write })
                case 5:
                    XCTAssertEqual(driver.after.registers[0], UInt8(truncatingIfNeeded: driver.after.cycleCount))
                    XCTAssertEqual(driver.highlights.writtenRegisters, [0])
                    XCTAssertNil(driver.bus?.address)
                    XCTAssertTrue(driver.changes.contains { $0.field == "ticks" && $0.access == .read })
                case 6:
                    XCTAssertTrue(guide.currentMachine.halted)
                    XCTAssertEqual(guide.currentMachine.instructionCount, 1)
                    XCTAssertTrue(driver.highlights.writtenMemory.isEmpty)
                default: XCTFail("Unexpected service")
                }
                XCTAssertTrue(guide.steps.allSatisfy { !$0.highlights.readMemory.contains(MemoryMap.inputPort) || $0.executedPhase == .fetch })
                XCTAssertTrue(guide.steps.allSatisfy { !$0.highlights.writtenMemory.contains(MemoryMap.consolePort) })
            }
        }
    }

    func testMidInstructionKeepsLatchedBytesAndSeparatesEditedRAMFromSource() throws {
        try withSession("LDI R0, 5\nHALT") { session in
            session.step(micro: true)
            session.writeByte(at: 2, value: 9)
            let baseline = session.machine
            session.startGuidedInstruction()
            let guide = try XCTUnwrap(session.guidedInstruction)
            XCTAssertTrue(guide.isPartwayThroughInstruction)
            XCTAssertEqual(guide.instructionAddress, 0)
            XCTAssertEqual(guide.executionBytes[2], 5)
            XCTAssertEqual(guide.ramBytes[2], 9)
            XCTAssertTrue(guide.sourceMatchesExecution)
            let completed = try finish(session)
            XCTAssertEqual(completed.steps.map(\.executedPhase), [.decode, .execute])
            XCTAssertEqual(session.machine.registers[0], 5)
            session.restartGuidedInstruction()
            XCTAssertEqual(session.machine, baseline)
            XCTAssertTrue(session.guidedInstruction?.steps.isEmpty == true)
            session.endGuidedInstruction()
            session.reset()
            session.writeByte(at: 2, value: 9)
            session.startGuidedInstruction()
            XCTAssertFalse(session.guidedInstruction?.sourceMatchesExecution == true)
            XCTAssertEqual(session.guidedInstruction?.executionBytes[2], 9)
            XCTAssertEqual(try finish(session).currentMachine.registers[0], 9)
        }
    }

    func testCALLAndRETShowExactStackWriteReadAndProgramCounter() throws {
        try withSession("CALL sub\nHALT\nsub: RET") { session in
            session.startGuidedInstruction()
            let call = try finish(session)
            XCTAssertEqual(call.latestStep?.highlights.writtenMemory, [191])
            XCTAssertEqual(session.machine.memory[191], 4)
            XCTAssertEqual(session.machine.stackPointer, 191)
            XCTAssertEqual(session.machine.pc, 8)
            XCTAssertTrue(call.latestStep?.highlights.cpuFields.contains("stackPointer") == true)
            session.startGuidedInstruction()
            let returning = try finish(session)
            XCTAssertEqual(returning.instructionAddress, 8)
            XCTAssertEqual(returning.latestStep?.highlights.readMemory, [191])
            XCTAssertTrue(returning.latestStep?.highlights.changedMemory.isEmpty == true)
            XCTAssertEqual(session.machine.stackPointer, 192)
            XCTAssertEqual(session.machine.pc, 4)
            XCTAssertEqual(session.machine.instructionCount, 2)
        }
    }

    func testDecodeKernelAndExecutionFaultsAndHALTStopAtActualBoundary() throws {
        try withSession("HALT") { session in
            session.startGuidedInstruction()
            let halt = try finish(session)
            XCTAssertEqual(halt.steps.count, 3)
            XCTAssertEqual(halt.latestStep?.executedPhase, .execute)
            XCTAssertEqual(halt.latestStep?.event.phase, .halted)
            XCTAssertEqual(session.machine.instructionCount, 1)
            XCTAssertTrue(session.machine.halted)
            session.startGuidedInstruction()
            XCTAssertNil(session.guidedInstruction)
        }
        try withSession("NOP") { session in
            session.writeByte(at: 0, value: 255)
            session.startGuidedInstruction()
            let malformed = try finish(session)
            XCTAssertNil(malformed.instruction)
            XCTAssertEqual(malformed.steps.count, 2)
            XCTAssertEqual(malformed.latestStep?.executedPhase, .decode)
            XCTAssertEqual(malformed.latestStep?.event.phase, .fault)
            XCTAssertEqual(session.machine.instructionCount, 0)
            XCTAssertTrue(malformed.latestStep?.changes.contains { $0.field == "fault" && $0.didChange } == true)
            session.previousGuidedStep()
            XCTAssertNil(session.machine.fault)
            XCTAssertEqual(session.machine.nextPhase, .decode)
            XCTAssertTrue(session.guidedInstruction?.canAdvance == true)
        }
        try withSession("SYS 1", mode: .user) { session in
            session.writeRegister(0, value: 64)
            session.startGuidedInstruction()
            let rejected = try finish(session)
            XCTAssertEqual(rejected.steps.count, 5)
            XCTAssertEqual(rejected.latestStep?.executedPhase, .kernel)
            XCTAssertEqual(rejected.currentMachine.privilege, .kernel)
            XCTAssertTrue(rejected.latestStep?.highlights.writtenMemory.isEmpty == true)
            XCTAssertEqual(rejected.capturedSystemCall?.arguments[0], 64)
        }
        try withSession("RET") { session in
            session.startGuidedInstruction()
            let underflow = try finish(session)
            XCTAssertEqual(underflow.steps.count, 3)
            XCTAssertEqual(underflow.latestStep?.executedPhase, .execute)
            XCTAssertEqual(session.machine.stackPointer, 192)
            XCTAssertTrue(underflow.latestStep?.highlights.readMemory.isEmpty == true)
            XCTAssertEqual(session.machine.instructionCount, 0)
        }
    }

    func testBackRestartRestoreExactMachineAndFullCapacityHistory() throws {
        try withSession("JMP 0") { session in
            session.toggleRun()
            for _ in 0..<520 { session.tick() }
            let baseline = session.machine
            let history = session.history
            XCTAssertEqual(history.count, 512)
            session.startGuidedInstruction()
            let guide = try finish(session)
            XCTAssertEqual(guide.steps.count, 2) // Begin at Decode after cycle 520.
            XCTAssertEqual(session.history, Array((history + guide.steps.map(\.before)).suffix(512)))
            session.previousGuidedStep()
            XCTAssertEqual(session.machine, guide.steps[1].before)
            XCTAssertEqual(session.history, Array((history + [guide.steps[0].before]).suffix(512)))
            XCTAssertTrue(session.canRewind)
            session.restartGuidedInstruction()
            XCTAssertEqual(session.machine, baseline)
            XCTAssertEqual(session.history, history, "Restart must recover entries evicted by guide-owned checkpoints.")
            XCTAssertTrue(session.guidedInstruction?.steps.isEmpty == true)
            XCTAssertFalse(session.guidedInstruction?.canPrevious == true)
            let replay = try finish(session)
            XCTAssertEqual(replay.steps, guide.steps)
            session.previousGuidedStep()
            session.previousGuidedStep()
            XCTAssertEqual(session.machine, baseline)
            XCTAssertEqual(session.history, history)
            session.previousGuidedStep()
            XCTAssertEqual(session.machine, baseline)
        }
    }

    func testExitRetainsCurrentSnapshotUndoAndSlowSpeedWithoutResumeDebt() throws {
        try withSession("LDI R0, 7\nHALT") { session in
            session.playbackSpeed = 0.25
            session.startGuidedInstruction()
            let fetch = try next(session)
            let history = session.history
            session.endGuidedInstruction()
            XCTAssertNil(session.guidedInstruction)
            XCTAssertEqual(session.machine, fetch.after)
            XCTAssertEqual(session.history, history)
            XCTAssertEqual(session.playbackSpeed, 0.25)
            XCTAssertFalse(session.running)
            session.toggleRun()
            session.advancePlayback(elapsed: 0.1)
            XCTAssertEqual(session.machine, fetch.after)
            session.running = false
            session.rewind()
            XCTAssertEqual(session.machine, fetch.before)
            XCTAssertTrue(session.history.isEmpty)
            XCTAssertFalse(session.canRewind)
        }
    }

    func testConflictingAcceptedChangesSafelyEndGuideAndRejectedChangesPreserveIt() throws {
        try withSession("LDI R0, 7\nHALT") { session in
            session.startGuidedInstruction()
            let fetch = try next(session)
            session.setInput(0)
            XCTAssertNotNil(session.guidedInstruction)
            session.writeByte(at: 256, value: 1)
            XCTAssertNotNil(session.guidedInstruction)
            XCTAssertEqual(session.machine, fetch.after)
            session.writeByte(at: 128, value: 5)
            XCTAssertNil(session.guidedInstruction)
            XCTAssertEqual(session.machine.cycleCount, 1)
            XCTAssertEqual(session.history.count, 2)
            session.rewind()
            XCTAssertEqual(session.machine, fetch.after)

            session.startGuidedInstruction()
            session.writeRegister(1, value: 3)
            XCTAssertNil(session.guidedInstruction)
            session.startGuidedInstruction()
            session.setInput(1)
            XCTAssertNil(session.guidedInstruction)
            session.startGuidedInstruction()
            XCTAssertThrowsError(try session.assemble("BAD", mode: .bareMetal))
            XCTAssertNotNil(session.guidedInstruction)
            try session.assemble("HALT", mode: .user)
            XCTAssertNil(session.guidedInstruction)
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.startGuidedInstruction()
            session.changeMode(.bareMetal)
            XCTAssertNil(session.guidedInstruction)
            session.startGuidedInstruction()
            session.reset()
            XCTAssertNil(session.guidedInstruction)
            XCTAssertTrue(session.history.isEmpty)
            XCTAssertEqual(session.machine.cycleCount, 0)
        }
    }
}
