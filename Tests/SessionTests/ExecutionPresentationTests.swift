import XCTest
import Foundation
@testable import AssemblerToy
import AssemblerCore

/// The workbench's cues must describe the most recent real microcycle. A
/// debugger edit or restored snapshot must never retain evidence from its future.
@MainActor
final class ExecutionPresentationTests: XCTestCase {
    private func withSession(_ source: String, mode: ExecutionMode = .bareMetal,
                             _ body: (MachineSession) throws -> Void) throws {
        let suite = "AssemblerToy.ExecutionPresentationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let session = MachineSession(preferences: preferences)
        try session.assemble(source, mode: mode)
        try body(session)
    }

    func testManualMicrocycleAndWholeInstructionDescribeExactLastTransition() throws {
        try withSession("LDI R0, 27\nHALT") { session in
            XCTAssertNil(session.lastExecutionStep)
            for phase in [MicroPhase.fetch, .decode] {
                let before = session.machine
                var expected = before
                let event = try XCTUnwrap(expected.step())
                session.step(micro: true)
                let record = try XCTUnwrap(session.lastExecutionStep)
                XCTAssertEqual(record.before, before)
                XCTAssertEqual(record.after, expected)
                XCTAssertEqual(record.event, event)
                XCTAssertEqual(record.executedPhase, phase)
                XCTAssertEqual(record.highlights.instructionAddress, 0)
                XCTAssertEqual(session.machine, expected)
            }

            let checkpointCount = session.history.count
            let beforeExecute = session.machine
            session.step(micro: false)
            let execute = try XCTUnwrap(session.lastExecutionStep)
            XCTAssertEqual(execute.before, beforeExecute)
            XCTAssertEqual(execute.executedPhase, .execute)
            XCTAssertEqual(execute.before.cycleCount, 2)
            XCTAssertEqual(execute.after.cycleCount, 3)
            XCTAssertEqual(execute.after.registers[0], 27)
            XCTAssertEqual(execute.highlights.changedRegisters, [0])
            XCTAssertEqual(execute.after.pc, 4)
            XCTAssertEqual(session.history.count, checkpointCount + 1,
                           "An instruction-sized manual action must retain one undo checkpoint.")

            let beforeHalt = session.machine
            session.step(micro: false)
            let halt = try XCTUnwrap(session.lastExecutionStep)
            XCTAssertEqual(halt.executedPhase, .execute)
            XCTAssertEqual(halt.highlights.instructionAddress, 4)
            XCTAssertEqual(halt.before.cycleCount, beforeHalt.cycleCount + 2,
                           "The final cue must describe HALT's Execute, rather than its initial Fetch.")
            XCTAssertEqual(halt.after.cycleCount, beforeHalt.cycleCount + 3)
            XCTAssertTrue(halt.after.halted)
            XCTAssertEqual(session.history.last, beforeHalt)
            session.step(micro: true)
            XCTAssertEqual(session.lastExecutionStep, halt,
                           "A refused step on a stopped machine must not invent a new event.")
        }
    }

    func testPlaybackAndSYSDriverCuesDistinguishRAMFromIsolatedDevicePorts() throws {
        for service in [1, 3, 4, 5] {
            try withSession("SYS \(service)\nHALT", mode: .user) { session in
                session.writeRegister(0, value: service == 1 ? 27 : 65)
                session.writeRegister(1, value: 3)
                session.setInput(1)
                let originalRAM = session.machine.memory
                session.toggleRun()
                for phase in [MicroPhase.fetch, .decode, .execute, .trap, .kernel, .driver, .returnToUser] {
                    let before = session.machine
                    var expected = before
                    let event = try XCTUnwrap(expected.step())
                    session.tick()
                    let record = try XCTUnwrap(session.lastExecutionStep)
                    XCTAssertEqual(record.before, before)
                    XCTAssertEqual(record.after, expected)
                    XCTAssertEqual(record.event, event)
                    XCTAssertEqual(record.executedPhase, phase)
                    XCTAssertEqual(record.highlights.instructionAddress, 0)
                    guard phase == .driver else { continue }
                    let cue = ExecutionCue(machine: session.machine, step: record)
                    XCTAssertEqual(cue.detail, event.message)
                    switch service {
                    case 1:
                        XCTAssertEqual(record.bus?.kind, .deviceWrite)
                        XCTAssertEqual(record.bus?.address, 219)
                        XCTAssertEqual(record.highlights.writtenMemory, [219])
                        XCTAssertEqual(record.highlights.changedMemory, [219])
                        XCTAssertEqual(record.after.memory[219], 3)
                        XCTAssertEqual(cue.source, "Trusted driver")
                        XCTAssertEqual(cue.destination, "Display RAM 0xDB")
                    case 3:
                        XCTAssertEqual(record.bus?.kind, .deviceRead)
                        XCTAssertEqual(record.bus?.address, MemoryMap.inputPort)
                        XCTAssertTrue(record.highlights.readMemory.isEmpty)
                        XCTAssertTrue(record.highlights.changedMemory.isEmpty)
                        XCTAssertEqual(record.highlights.writtenRegisters, [0])
                        XCTAssertEqual(record.after.registers[0], 1)
                        XCTAssertEqual(record.after.memory, originalRAM)
                        XCTAssertEqual(cue.source, "Input port 0")
                        XCTAssertEqual(cue.destination, "R0")
                    case 4:
                        XCTAssertEqual(record.bus?.kind, .deviceWrite)
                        XCTAssertEqual(record.bus?.address, MemoryMap.consolePort)
                        XCTAssertTrue(record.highlights.writtenMemory.isEmpty)
                        XCTAssertEqual(record.after.console, "A")
                        XCTAssertEqual(record.after.memory, originalRAM)
                        XCTAssertEqual(cue.destination, "Console port 1")
                    case 5:
                        XCTAssertEqual(record.bus?.kind, .deviceRead)
                        XCTAssertNil(record.bus?.address)
                        XCTAssertTrue(record.highlights.readMemory.isEmpty)
                        XCTAssertEqual(record.highlights.writtenRegisters, [0])
                        XCTAssertEqual(record.after.memory, originalRAM)
                        XCTAssertEqual(cue.source, "Clock device")
                    default: XCTFail("Unexpected service")
                    }
                }
                XCTAssertEqual(session.machine.instructionCount, 1)
                XCTAssertEqual(session.lastExecutionStep?.capturedSystemCall?.service, UInt8(service))
                XCTAssertEqual(session.machine.privilege, .user)
                session.running = false
            }
        }
    }

    func testAcceptedEditsAndRestorationClearStaleEvidenceWhileRejectedActionsPreserveIt() throws {
        try withSession("LDI R0, 27\nHALT") { session in
            session.step(micro: true)
            let fetch = try XCTUnwrap(session.lastExecutionStep)
            session.writeByte(at: 256, value: 1)
            XCTAssertEqual(session.lastExecutionStep, fetch)
            session.writeRegister(4, value: 1)
            XCTAssertEqual(session.lastExecutionStep, fetch)
            session.setInput(session.machine.inputValue)
            XCTAssertEqual(session.lastExecutionStep, fetch)
            XCTAssertThrowsError(try session.assemble("UNKNOWN", mode: .bareMetal))
            XCTAssertEqual(session.lastExecutionStep, fetch)

            session.writeRegister(0, value: session.machine.registers[0])
            XCTAssertNil(session.lastExecutionStep)
            session.step(micro: true)
            XCTAssertNotNil(session.lastExecutionStep)
            session.writeByte(at: 128, value: session.machine.memory[128])
            XCTAssertNil(session.lastExecutionStep)
            session.step(micro: true)
            XCTAssertNotNil(session.lastExecutionStep)
            session.setInput(1)
            XCTAssertNil(session.lastExecutionStep)

            session.reset()
            session.step(micro: true)
            XCTAssertNotNil(session.lastExecutionStep)
            session.rewind()
            XCTAssertNil(session.lastExecutionStep)
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.step(micro: true)
            session.reset()
            XCTAssertNil(session.lastExecutionStep)
            session.step(micro: true)
            session.changeMode(.user)
            XCTAssertNil(session.lastExecutionStep)
            session.step(micro: true)
            try session.assemble("NOP\nHALT", mode: .user)
            XCTAssertNil(session.lastExecutionStep)
            session.step(micro: true)
            session.load(try XCTUnwrap(ExampleCatalog.examples.first))
            XCTAssertNil(session.lastExecutionStep)
        }
    }

    func testGuideBackRestartAndDoneKeepEvidenceAlignedWithTheActualSnapshot() throws {
        try withSession("LDI R0, 27\nHALT") { session in
            session.playbackSpeed = 0.25
            session.startGuidedInstruction()
            session.advanceGuidedInstruction()
            let fetch = try XCTUnwrap(session.lastExecutionStep)
            XCTAssertEqual(fetch, session.guidedInstruction?.latestStep)
            session.advanceGuidedInstruction()
            session.advanceGuidedInstruction()
            XCTAssertEqual(session.lastExecutionStep?.after.registers[0], 27)
            session.previousGuidedStep()
            XCTAssertEqual(session.lastExecutionStep, session.guidedInstruction?.latestStep)
            XCTAssertEqual(session.lastExecutionStep?.executedPhase, .decode)
            XCTAssertEqual(session.lastExecutionStep?.after, session.machine)
            session.previousGuidedStep()
            XCTAssertEqual(session.lastExecutionStep, fetch)
            session.previousGuidedStep()
            XCTAssertNil(session.lastExecutionStep)
            XCTAssertEqual(session.machine.cycleCount, 0)

            session.advanceGuidedInstruction()
            session.advanceGuidedInstruction()
            session.restartGuidedInstruction()
            XCTAssertNil(session.lastExecutionStep)
            XCTAssertEqual(session.machine.cycleCount, 0)
            for _ in 0..<3 { session.advanceGuidedInstruction() }
            let execute = try XCTUnwrap(session.lastExecutionStep)
            session.endGuidedInstruction()
            XCTAssertNil(session.guidedInstruction)
            XCTAssertEqual(session.lastExecutionStep, execute)
            XCTAssertEqual(execute.after, session.machine)
            XCTAssertEqual(session.playbackSpeed, 0.25)
            XCTAssertFalse(session.running)
            session.rewind()
            XCTAssertNil(session.lastExecutionStep)
            XCTAssertEqual(session.machine.registers[0], 0)
        }
    }
}
