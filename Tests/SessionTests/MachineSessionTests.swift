import XCTest
import Foundation
import Observation
@testable import AssemblerToy
import AssemblerCore

/// Observation's change handler is Sendable and can run before the setter returns.
private final class ResetObservationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func record() {
        lock.lock()
        defer { lock.unlock() }
        fired = true
    }
    var didFire: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }
}

@MainActor
final class MachineSessionTests: XCTestCase {
    private func withPreferences(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "AssemblerToy.SessionTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        try body(preferences)
    }

    private func withSession(_ source: String, mode: ExecutionMode = .bareMetal,
                             _ body: (MachineSession) throws -> Void) throws {
        try withPreferences { preferences in
            let session = MachineSession(preferences: preferences)
            try session.assemble(source, mode: mode)
            try body(session)
        }
    }

    func testNormalizedSpeedDefaultsToReadablePaceAndPersistsValidBounds() throws {
        try withPreferences { preferences in
            let session = MachineSession(preferences: preferences)
            XCTAssertEqual(session.playbackSpeed, 1)
            XCTAssertEqual(session.cyclesPerSecond, 2)
            XCTAssertFalse(session.isSpeedSettling)
            for speed in [0.25, 0.5, 1, 2, 4] {
                session.playbackSpeed = speed
                XCTAssertEqual(session.playbackSpeed, speed)
                XCTAssertEqual(session.cyclesPerSecond, speed * 2)
                XCTAssertFalse(session.isSpeedSettling)
                let restored = MachineSession(preferences: preferences)
                XCTAssertEqual(restored.playbackSpeed, speed)
                XCTAssertEqual(restored.cyclesPerSecond, speed * 2)
            }
            for invalid in [-1, 0, 0.249, 4.001, Double.infinity, -Double.infinity, Double.nan] {
                session.playbackSpeed = invalid
                XCTAssertEqual(session.playbackSpeed, 4)
                XCTAssertEqual(preferences.double(forKey: "AssemblerToy.playbackSpeed"), 4)
            }
        }
    }

    func testInvalidRestoredSpeedFallsBackToOneRatherThanLegacyFastRates() throws {
        try withPreferences { preferences in
            for invalid in [0, 0.1, 60, 240, Double.infinity, Double.nan] {
                preferences.set(invalid, forKey: "AssemblerToy.playbackSpeed")
                let session = MachineSession(preferences: preferences)
                XCTAssertEqual(session.playbackSpeed, 1)
                XCTAssertEqual(session.cyclesPerSecond, 2)
            }
            preferences.set("fast", forKey: "AssemblerToy.playbackSpeed")
            XCTAssertEqual(MachineSession(preferences: preferences).playbackSpeed, 1)
        }
    }

    func testPlaybackCadencePresentsEveryMicrocycleAtEachNormalizedSpeed() throws {
        try withSession("INC R0\nJMP 0") { session in
            for speed in [0.25, 0.5, 1, 2, 4] {
                session.reset()
                session.playbackSpeed = speed
                session.toggleRun()
                for _ in 0..<400 {
                    let previous = session.machine.cycleCount
                    session.advancePlayback(elapsed: 0.05)
                    let current = session.machine.cycleCount
                    XCTAssertLessThanOrEqual(current - previous, 1)
                }
                XCTAssertEqual(session.machine.cycleCount, UInt64(speed * 40))
                XCTAssertEqual(session.history.count, Int(session.machine.cycleCount))
                XCTAssertTrue(session.running)
                XCTAssertNil(session.machine.fault)
            }
        }
    }

    func testPacingProgressDoesNotPublishUntilARealMicrocycleIsDue() throws {
        try withSession("JMP 0") { session in
            session.toggleRun()
            let signal = ResetObservationSignal()
            withObservationTracking {
                _ = session.machine.cycleCount
                _ = session.isSpeedSettling
            } onChange: {
                signal.record()
            }
            for _ in 0..<9 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertEqual(session.machine.cycleCount, 0)
            XCTAssertFalse(signal.didFire)
            session.advancePlayback(elapsed: 0.05)
            XCTAssertEqual(session.machine.cycleCount, 1)
            XCTAssertEqual(session.machine.nextPhase, .decode)
            XCTAssertTrue(signal.didFire)
        }
    }

    func testSpeedUpIsSmoothAndKeepsThePartiallyElapsedCycle() throws {
        try withSession("JMP 0") { session in
            session.toggleRun()
            for _ in 0..<7 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.playbackSpeed = 4
            XCTAssertTrue(session.isSpeedSettling)
            XCTAssertEqual(session.cyclesPerSecond, 8)
            session.advancePlayback(elapsed: 0.1)
            XCTAssertEqual(session.machine.cycleCount, 0, "The new pace must ramp rather than jump immediately.")
            session.advancePlayback(elapsed: 0.05)
            XCTAssertEqual(session.machine.cycleCount, 1, "Retuning must retain the fraction already elapsed.")
            for _ in 0..<6 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertFalse(session.isSpeedSettling)
            XCTAssertEqual(session.machine.cycleCount, 2)
            session.advancePlayback(elapsed: 0.01)
            XCTAssertEqual(session.machine.cycleCount, 3)
        }
    }

    func testSlowdownAndReversalBlendFromCurrentPace() throws {
        try withSession("JMP 0") { session in
            session.playbackSpeed = 4
            session.toggleRun()
            session.advancePlayback(elapsed: 0.1)
            session.playbackSpeed = 0.25
            session.advancePlayback(elapsed: 0.05)
            XCTAssertEqual(session.machine.cycleCount, 1, "Slowdown must blend from the current pace.")
            for _ in 0..<8 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertEqual(session.machine.cycleCount, 2)
            XCTAssertFalse(session.isSpeedSettling)
            session.advancePlayback(elapsed: 0.1)
            XCTAssertEqual(session.machine.cycleCount, 2)

            session.reset()
            session.playbackSpeed = 1
            session.toggleRun()
            for _ in 0..<7 { session.advancePlayback(elapsed: 0.05) }
            session.playbackSpeed = 4
            session.advancePlayback(elapsed: 0.1)
            session.playbackSpeed = 0.5
            session.advancePlayback(elapsed: 0.05)
            XCTAssertEqual(session.machine.cycleCount, 1, "A reversal must retain both phase and current effective pace.")
            for _ in 0..<8 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertEqual(session.machine.cycleCount, 1)
            XCTAssertFalse(session.isSpeedSettling)
        }
    }

    func testSettlingPublishesOnlyItsStartAndCompletion() throws {
        try withSession("JMP 0") { session in
            session.toggleRun()
            let began = ResetObservationSignal()
            withObservationTracking { _ = session.isSpeedSettling } onChange: { began.record() }
            session.playbackSpeed = 2
            XCTAssertTrue(began.didFire)
            let ended = ResetObservationSignal()
            withObservationTracking { _ = session.isSpeedSettling } onChange: { ended.record() }
            for _ in 0..<8 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertTrue(session.isSpeedSettling)
            XCTAssertFalse(ended.didFire)
            session.advancePlayback(elapsed: 0.05)
            XCTAssertFalse(session.isSpeedSettling)
            XCTAssertTrue(ended.didFire)
        }
    }

    func testPauseAndInactiveGuardDiscardDebtAndResumeWithoutBurst() throws {
        try withSession("JMP 0") { session in
            session.playbackSpeed = 4
            session.toggleRun()
            session.advancePlayback(elapsed: 0.1)
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.running = false // The scene's inactive transition uses this guard.
            for _ in 0..<10 { session.advancePlayback(elapsed: 100) }
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.playbackSpeed = 2
            XCTAssertFalse(session.isSpeedSettling)
            session.toggleRun()
            session.advancePlayback(elapsed: 0.05)
            XCTAssertEqual(session.machine.cycleCount, 0)
            for _ in 0..<4 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertEqual(session.machine.cycleCount, 1)
            session.toggleRun()
            session.advancePlayback(elapsed: 100)
            XCTAssertEqual(session.machine.cycleCount, 1)
            XCTAssertFalse(session.running)
        }
    }

    func testStalledAndInvalidCallbacksNeverCatchUpOrSkipPhases() throws {
        try withSession("JMP 0") { session in
            session.playbackSpeed = 4
            session.toggleRun()
            for invalid in [-1, 0, Double.infinity, -Double.infinity, Double.nan] {
                session.advancePlayback(elapsed: invalid)
            }
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.advancePlayback(elapsed: 30)
            XCTAssertEqual(session.machine.cycleCount, 0, "A stall may contribute only a bounded 0.1 seconds.")
            session.advancePlayback(elapsed: 30)
            XCTAssertEqual(session.machine.cycleCount, 1)
            XCTAssertEqual(session.machine.nextPhase, .decode)
            session.advancePlayback(elapsed: 0.001)
            XCTAssertEqual(session.machine.cycleCount, 1, "No stale catch-up debt may survive the bounded callback.")
            session.advancePlayback(elapsed: 30)
            XCTAssertEqual(session.machine.cycleCount, 2)
            XCTAssertEqual(session.machine.nextPhase, .execute)
            session.advancePlayback(elapsed: 30)
            XCTAssertEqual(session.machine.cycleCount, 3)
            XCTAssertEqual(session.machine.nextPhase, .fetch)
        }
    }

    func testScheduledBreakpointStopsBeforeFetchAndContinuationKeepsEveryPhase() throws {
        try withSession("JMP 0") { session in
            session.breakpoints = [0]
            session.toggleRun()
            for _ in 0..<10 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 0)
            XCTAssertTrue(session.history.isEmpty)
            session.toggleRun()
            for _ in 0..<9 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertEqual(session.machine.cycleCount, 0)
            session.advancePlayback(elapsed: 0.05)
            XCTAssertEqual(session.machine.cycleCount, 1)
            XCTAssertEqual(session.machine.nextPhase, .decode)
            for _ in 0..<30 { session.advancePlayback(elapsed: 0.05) }
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 3)
            XCTAssertEqual(session.history.count, 3)
        }
    }

    func testManualChangesClearPartialScheduledProgress() throws {
        try withSession("JMP 0") { session in
            let changes: [(MachineSession) throws -> Void] = [
                { $0.reset() },
                { $0.step(micro: true) },
                { $0.rewind() },
                { $0.changeMode(.user) },
                { try $0.assemble("JMP 0", mode: .bareMetal) }
            ]
            for change in changes {
                session.reset()
                session.toggleRun()
                for _ in 0..<9 { session.advancePlayback(elapsed: 0.05) }
                try change(session)
                XCTAssertFalse(session.running)
                let count = session.machine.cycleCount
                session.toggleRun()
                session.advancePlayback(elapsed: 0.05)
                XCTAssertEqual(session.machine.cycleCount, count)
            }
        }
    }

    func testInitialRunHonorsCurrentBreakpointAndContinuationSkipsOnce() throws {
        try withSession("LDI R0, 1\nJMP 0") { session in
            session.breakpoints = [0]
            session.toggleRun()
            session.tick()
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 0)
            XCTAssertTrue(session.machine.fetchedBytes.isEmpty)
            XCTAssertTrue(session.history.isEmpty)

            session.toggleRun()
            session.tick()
            XCTAssertTrue(session.running)
            XCTAssertEqual(session.machine.nextPhase, .decode)
            for _ in 0..<8 { session.tick() }
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.pc, 0)
            XCTAssertEqual(session.machine.cycleCount, 6)
        }
    }

    func testPatchAtBreakpointIsFetchedWhenExecutionContinues() throws {
        try withSession("LDI R0, 1\nHALT") { session in
            session.breakpoints = [0]
            session.toggleRun()
            session.tick()
            session.writeByte(at: 2, value: 9)
            session.toggleRun()
            session.tick()
            session.step(micro: false)
            XCTAssertEqual(session.machine.registers[0], 9)
            XCTAssertEqual(session.machine.instructionCount, 1)
        }
    }

    func testResetAndModeChangeClearBreakpointContinuation() throws {
        try withSession("JMP 0") { session in
            session.breakpoints = [0]
            session.toggleRun()
            session.tick()
            session.reset()
            session.toggleRun()
            session.tick()
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 0)

            session.setInput(1)
            session.changeMode(.user)
            session.toggleRun()
            session.tick()
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.inputValue, 1)
            XCTAssertEqual(session.machine.mode, .user)
            XCTAssertEqual(session.machine.cycleCount, 0)
        }
    }

    func testResetFromExecutedOutputClearsStateAndNotifiesCycleObservers() throws {
        let source = """
        LDI R0, 27
        LDI R1, 5
        SYS 1
        LDI R0, 65
        SYS 4
        LDI R2, 255
        INC R2
        loop: JMP loop
        """
        try withSession(source, mode: .user) { session in
            session.setInput(1)
            session.toggleRun()
            for _ in 0..<32 { session.tick() }
            session.toggleRun() // Pause a still-running program after real output.

            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 32)
            XCTAssertEqual(session.machine.instructionCount, 8)
            XCTAssertEqual(session.machine.framebuffer[27], 5)
            XCTAssertEqual(session.machine.console, "A")
            XCTAssertEqual(session.machine.consoleByteCount, 1)
            XCTAssertEqual(session.machine.registers, [65, 5, 0, 0])
            XCTAssertTrue(session.machine.zeroFlag)
            XCTAssertTrue(session.machine.carryFlag)
            XCTAssertFalse(session.history.isEmpty)
            XCTAssertTrue(session.canRewind)

            let signal = ResetObservationSignal()
            withObservationTracking {
                _ = session.machine.cycleCount
            } onChange: {
                signal.record()
            }
            session.reset()

            XCTAssertTrue(signal.didFire, "Reset did not invalidate the observed cycle read.")
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 0)
            XCTAssertEqual(session.machine.instructionCount, 0)
            XCTAssertEqual(session.machine.pc, 0)
            XCTAssertEqual(session.machine.phase, .fetch)
            XCTAssertEqual(session.machine.nextPhase, .fetch)
            XCTAssertEqual(session.machine.privilege, .user)
            XCTAssertEqual(session.machine.mode, .user)
            XCTAssertEqual(session.machine.registers, [0, 0, 0, 0])
            XCTAssertEqual(session.machine.framebuffer, [UInt8](repeating: 0, count: 64))
            XCTAssertEqual(session.machine.memory, session.program.bytes)
            XCTAssertFalse(session.machine.zeroFlag)
            XCTAssertFalse(session.machine.carryFlag)
            XCTAssertEqual(session.machine.console, "")
            XCTAssertEqual(session.machine.consoleByteCount, 0)
            XCTAssertEqual(session.machine.droppedConsoleByteCount, 0)
            XCTAssertEqual(session.machine.inputValue, 1)
            XCTAssertTrue(session.machine.trace.isEmpty)
            XCTAssertTrue(session.history.isEmpty)
            XCTAssertFalse(session.canRewind)
            // Queued clock ticks after Reset must remain harmless.
            for _ in 0..<10 { session.tick() }
            XCTAssertEqual(session.machine.cycleCount, 0)
        }
    }

    func testRewindDoesNotCarryAStaleBreakpointBypass() throws {
        try withSession("JMP 0") { session in
            session.breakpoints = [0]
            session.toggleRun()
            session.tick()
            session.toggleRun()
            session.tick()
            session.rewind()
            session.toggleRun()
            session.tick()
            XCTAssertFalse(session.running)
            XCTAssertEqual(session.machine.cycleCount, 0)
        }
    }

    func testInvalidEditsPreserveEveryCheckpointAtCapacity() throws {
        try withSession("JMP 0") { session in
            session.toggleRun()
            for _ in 0..<520 { session.tick() }
            let history = session.history
            let machine = session.machine
            XCTAssertEqual(history.count, 512)
            session.writeByte(at: 256, value: 1)
            XCTAssertEqual(session.history, history)
            XCTAssertEqual(session.machine, machine)
            session.writeRegister(4, value: 1)
            XCTAssertEqual(session.history, history)
            XCTAssertEqual(session.machine, machine)
        }
    }

    func testSuccessfulEditAndInputRewindRestoreExactSnapshots() throws {
        try withSession("LDI R0, 5\nSYS 2\nHALT", mode: .user) { session in
            for _ in 0..<7 { session.step(micro: true) }
            XCTAssertEqual(session.machine.nextPhase, .kernel)
            let original = session.machine
            session.writeRegister(2, value: 99)
            session.rewind()
            XCTAssertEqual(session.machine, original)
            session.setInput(1)
            session.rewind()
            XCTAssertEqual(session.machine, original)
            session.step(micro: false)
            XCTAssertEqual(session.machine.framebuffer, Array(repeating: 5, count: 64))
            XCTAssertEqual(session.machine.privilege, .user)
        }
    }

    func testPausedSessionDoesNotAdvanceAndResumesWithoutReset() throws {
        try withSession("INC R0\nJMP 0") { session in
            session.toggleRun()
            for _ in 0..<18 { session.tick() }
            session.running = false // The view applies this on inactive scene changes.
            let paused = session.machine
            let count = session.history.count
            for _ in 0..<100 { session.tick() }
            XCTAssertEqual(session.machine, paused)
            XCTAssertEqual(session.history.count, count)
            session.toggleRun()
            session.tick()
            XCTAssertEqual(session.machine.cycleCount, paused.cycleCount + 1)
        }
    }

    func testHaltedAndFaultedSessionsDoNotAccumulateEmptyCheckpoints() throws {
        for source in ["HALT", "RET"] {
            try withSession(source) { session in
                session.toggleRun()
                for _ in 0..<8 { session.tick() }
                XCTAssertTrue(session.machine.isFinished)
                let finished = session.machine
                let count = session.history.count
                session.running = true
                for _ in 0..<100 { session.tick() }
                XCTAssertFalse(session.running)
                XCTAssertEqual(session.machine, finished)
                XCTAssertEqual(session.history.count, count)
            }
        }
    }

    func testUnchangedInputDoesNotConsumeUndoHistory() throws {
        try withSession("HALT") { session in
            for _ in 0..<100 { session.setInput(0) }
            XCTAssertTrue(session.history.isEmpty)
            session.setInput(1)
            XCTAssertEqual(session.history.count, 1)
            for _ in 0..<100 { session.setInput(1) }
            XCTAssertEqual(session.history.count, 1)
        }
    }

    func testCanRewindTracksOnlyHistoryAvailabilityTransitions() throws {
        try withSession("INC R0\nJMP 0") { session in
            XCTAssertFalse(session.canRewind)
            session.step(micro: true)
            XCTAssertTrue(session.canRewind)
            session.step(micro: true)
            session.rewind()
            XCTAssertTrue(session.canRewind)
            session.rewind()
            XCTAssertFalse(session.canRewind)
            session.setInput(1)
            XCTAssertTrue(session.canRewind)
            session.reset()
            XCTAssertFalse(session.canRewind)
            session.step(micro: true)
            session.changeMode(.user)
            XCTAssertFalse(session.canRewind)
            session.step(micro: true)
            try session.assemble("HALT", mode: .user)
            XCTAssertFalse(session.canRewind)
        }
    }

    func testHistoryRemainsBoundedAcrossOneHundredThousandMicrocycles() throws {
        try withSession("INC R0\nJMP 0") { session in
            session.toggleRun()
            for _ in 0..<100_000 { session.tick() }
            XCTAssertTrue(session.running)
            XCTAssertNil(session.machine.fault)
            XCTAssertEqual(session.machine.cycleCount, 100_000)
            XCTAssertEqual(session.history.count, 512)
            XCTAssertEqual(session.machine.trace.count, 384)
            XCTAssertEqual(session.history.first?.cycleCount, 99_488)
            for _ in 0..<512 { session.rewind() }
            XCTAssertEqual(session.machine.cycleCount, 99_488)
            XCTAssertTrue(session.history.isEmpty)
        }
    }

    func testConsoleHistoryRemainsBoundedAndReplaysAfterRewind() throws {
        try withSession("LDI R0, 65\nprint: OUT R0\nJMP print") { session in
            session.toggleRun()
            for _ in 0..<60_000 { session.tick() }
            XCTAssertEqual(session.machine.consoleByteCount, 10_000)
            XCTAssertEqual(session.machine.console.utf8.count, Machine.consoleCapacity)
            XCTAssertEqual(session.history.count, 512)
            XCTAssertTrue(session.history.allSatisfy { $0.console.utf8.count <= Machine.consoleCapacity })
            let finished = session.machine
            for _ in 0..<512 { session.rewind() }
            session.toggleRun()
            for _ in 0..<512 { session.tick() }
            XCTAssertEqual(session.machine, finished)
        }
    }
}
