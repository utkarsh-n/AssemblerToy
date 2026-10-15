import XCTest
import Foundation
@testable import AssemblerToy
import AssemblerCore

/// These fixtures match UITests/AssemblerToyUITests.swift. Unlike the execution
/// tests, restoration checks never call session.assemble before running.
@MainActor
final class SessionRestorationTests: XCTestCase {
    private enum Fixture {
        static let halt = "HALT\n"
        static let continuousFill = """
        LDI R0, 0
        LDI R1, 1
        loop:
          XOR R0, R1
          SYS 2
          JMP loop
        """
        static let redRow = """
        LDI R0, 0
        LDI R1, 5
        LDI R2, 8
        draw:
          SYS 1
          INC R0
          DEC R2
          JNZ draw
        SYS 6
        """
        static let amberPixel = """
        LDI R0, 0
        LDI R1, 2
        SYS 1
        SYS 6
        """
    }

    private func withRestored(_ source: String, mode: ExecutionMode = .user,
                              argumentDomain: Bool = false,
                              _ body: (MachineSession, UserDefaults) throws -> Void) throws {
        let suite = "AssemblerToy.RestorationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            preferences.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            preferences.removePersistentDomain(forName: suite)
        }
        // A test-host launch's arguments must not override this independent suite.
        preferences.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        if argumentDomain {
            preferences.setVolatileDomain([
                "AssemblerToy.source": source,
                "AssemblerToy.bareMetal": mode == .bareMetal ? "YES" : "NO"
            ], forName: UserDefaults.argumentDomain)
        } else {
            preferences.set(source, forKey: "AssemblerToy.source")
            preferences.set(mode == .bareMetal, forKey: "AssemblerToy.bareMetal")
        }
        XCTAssertEqual(preferences.string(forKey: "AssemblerToy.source"), source)
        let session = MachineSession(preferences: preferences)
        try body(session, preferences)
    }

    private func assertLoaded(_ session: MachineSession, source: String,
                              expectedCode: [UInt8], mode: ExecutionMode = .user,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(session.title, "Your program", file: file, line: line)
        XCTAssertEqual(session.source, source, file: file, line: line)
        XCTAssertEqual(session.program.source, source, file: file, line: line)
        XCTAssertEqual(session.machine.program, session.program, file: file, line: line)
        XCTAssertEqual(session.machine.memory, session.program.bytes, file: file, line: line)
        XCTAssertEqual(Array(session.program.bytes.prefix(expectedCode.count)), expectedCode, file: file, line: line)
        XCTAssertEqual(Array(session.machine.memory.prefix(expectedCode.count)), expectedCode, file: file, line: line)
        XCTAssertEqual(session.program.instructions.count, expectedCode.count / 4, file: file, line: line)
        XCTAssertEqual(session.program.instructions.map(\.bytes).flatMap { $0 }, expectedCode, file: file, line: line)
        XCTAssertEqual(session.machine.mode, mode, file: file, line: line)
        XCTAssertEqual(session.machine.cycleCount, 0, file: file, line: line)
        XCTAssertEqual(session.machine.instructionCount, 0, file: file, line: line)
        XCTAssertEqual(session.machine.registers, [0, 0, 0, 0], file: file, line: line)
        XCTAssertEqual(session.machine.framebuffer, [UInt8](repeating: 0, count: 64), file: file, line: line)
        XCTAssertFalse(session.running, file: file, line: line)
    }

    private func runFinite(_ session: MachineSession) {
        session.toggleRun()
        for _ in 0..<2_000 {
            if !session.running { break }
            session.tick()
        }
        XCTAssertTrue(session.machine.halted)
        XCTAssertNil(session.machine.fault)
        XCTAssertFalse(session.running)
    }

    func testSavedRedRowRestoresEncodedRAMAndDrawsBeforeExiting() throws {
        try withRestored(Fixture.redRow) { session, _ in
            let bytes: [UInt8] = [1,0,0,0, 1,1,5,0, 1,2,8,0, 23,1,0,0,
                                 25,0,0,0, 26,2,0,0, 16,12,0,0, 23,6,0,0]
            assertLoaded(session, source: Fixture.redRow, expectedCode: bytes)
            XCTAssertEqual(session.program.labels["draw"], 12)
            runFinite(session)
            XCTAssertEqual(session.machine.framebuffer, [UInt8](repeating: 5, count: 8) + [UInt8](repeating: 0, count: 56))
            XCTAssertEqual(session.machine.registers, [8, 5, 0, 0])
            XCTAssertEqual(session.machine.instructionCount, 36)
            XCTAssertEqual(session.machine.cycleCount, 144)
        }
    }

    func testSavedContinuousFillRestoresLoopAndAlternatesDisplay() throws {
        try withRestored(Fixture.continuousFill) { session, _ in
            assertLoaded(session, source: Fixture.continuousFill,
                         expectedCode: [1,0,0,0, 1,1,1,0, 7,0,1,0, 23,2,0,0, 14,8,0,0])
            XCTAssertEqual(session.program.labels["loop"], 8)
            session.toggleRun()
            for _ in 0..<19 { session.tick() }
            XCTAssertEqual(session.machine.framebuffer, [UInt8](repeating: 1, count: 64))
            XCTAssertEqual(session.machine.pc, 8)
            XCTAssertEqual(session.machine.instructionCount, 5)
            for _ in 0..<13 { session.tick() }
            XCTAssertEqual(session.machine.framebuffer, [UInt8](repeating: 0, count: 64))
            XCTAssertEqual(session.machine.pc, 8)
            XCTAssertEqual(session.machine.instructionCount, 8)
            XCTAssertTrue(session.running)
            XCTAssertNil(session.machine.fault)
        }
    }

    func testSavedHaltRestoresItsOpcodeAndStopsAfterOneInstruction() throws {
        try withRestored(Fixture.halt) { session, _ in
            assertLoaded(session, source: Fixture.halt, expectedCode: [24,0,0,0])
            runFinite(session)
            XCTAssertEqual(session.machine.instructionCount, 1)
            XCTAssertEqual(session.machine.cycleCount, 3)
            XCTAssertEqual(session.machine.pc, 4)
        }
    }

    func testSavedAmberPixelRestoresAndExecutesDriverOutput() throws {
        try withRestored(Fixture.amberPixel) { session, _ in
            assertLoaded(session, source: Fixture.amberPixel,
                         expectedCode: [1,0,0,0, 1,1,2,0, 23,1,0,0, 23,6,0,0])
            runFinite(session)
            XCTAssertEqual(session.machine.framebuffer[0], 2)
            XCTAssertEqual(Array(session.machine.framebuffer.dropFirst()), [UInt8](repeating: 0, count: 63))
            XCTAssertEqual(session.machine.instructionCount, 4)
        }
    }

    func testLaunchArgumentDomainRedRowRestoresRawSourceBytes() throws {
        try withRestored(Fixture.redRow, argumentDomain: true) { session, preferences in
            XCTAssertFalse(preferences.bool(forKey: "AssemblerToy.bareMetal"))
            assertLoaded(session, source: Fixture.redRow,
                         expectedCode: [1,0,0,0, 1,1,5,0, 1,2,8,0, 23,1,0,0,
                                        25,0,0,0, 26,2,0,0, 16,12,0,0, 23,6,0,0])
            runFinite(session)
            XCTAssertEqual(Array(session.machine.framebuffer.prefix(8)), [UInt8](repeating: 5, count: 8))
            XCTAssertEqual(session.machine.instructionCount, 36)
        }
    }

    func testLaunchArgumentDomainSavedBareModeLoadsUnrestrictedStores() throws {
        let source = "LDI R0, 255\nST R0, 192\nHALT\n"
        try withRestored(source, mode: .bareMetal, argumentDomain: true) { session, preferences in
            XCTAssertTrue(preferences.bool(forKey: "AssemblerToy.bareMetal"))
            assertLoaded(session, source: source,
                         expectedCode: [1,0,255,0, 10,0,192,0, 24,0,0,0], mode: .bareMetal)
            runFinite(session)
            XCTAssertEqual(session.machine.memory[192], 255)
            XCTAssertEqual(session.machine.framebuffer[0] & 7, 7)
        }
    }

    func testInvalidSavedSourceFallsBackToOneConsistentProgramImage() throws {
        try withRestored("NOPE R0, 1") { session, _ in
            let expected = try XCTUnwrap(ExampleCatalog.examples.first(where: { $0.id == "data-sprite" }))
            XCTAssertEqual(session.title, expected.name)
            XCTAssertEqual(session.source, expected.source)
            XCTAssertEqual(session.program.source, expected.source)
            XCTAssertEqual(session.machine.program, session.program)
            XCTAssertEqual(session.machine.memory, session.program.bytes)
            XCTAssertEqual(session.machine.memory[0], 1)
            runFinite(session)
            XCTAssertEqual(session.machine.framebuffer, session.program.dataBytes)
        }
    }
}
