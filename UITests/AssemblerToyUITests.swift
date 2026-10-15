import XCTest

/// These tests exercise the shipping UI. A single-line UserDefaults baseline
/// launches the app, then the normal editor assembles each verified fixture.
final class AssemblerToyUITests: XCTestCase {
    @MainActor
    func testRepeatedRunPauseStopsTheClockAndRemainsResponsive() throws {
        let app = launch(source: Fixture.continuousFill)
        defer { app.terminate() }
        let transport = app.buttons["runMachine"]

        for iteration in 0..<12 {
            transport.tap()
            XCTAssertTrue(waitForLabel(transport, containing: "Pause"), "Run did not start on repetition \(iteration)")
            transport.tap()
            XCTAssertTrue(waitForLabel(transport, containing: "Run"), "Pause did not stop on repetition \(iteration)")
            XCTAssertTrue(app.staticTexts.matching(identifier: "PAUSED").firstMatch.waitForExistence(timeout: 3))
        }

        let cycles = cycleReadout(in: app)
        XCTAssertTrue(cycles.exists)
        let pausedLabel = cycles.label
        let clockChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", pausedLabel), object: cycles)
        clockChanged.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [clockChanged], timeout: 1.5), .completed,
                       "The clock kept changing after Pause")

        for _ in 0..<10 {
            app.buttons["hardwareInput"].tap()
        }
        XCTAssertTrue(waitForValue(app.buttons["hardwareInput"], equals: "Low, zero"))
        XCTAssertEqual(cycleReadout(in: app).label, pausedLabel,
                       "The clock advanced while paused during hardware input changes")
        app.buttons["stepMachine"].tap()
        let stepped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", pausedLabel),
                                                object: cycleReadout(in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [stepped], timeout: 4), .completed,
                       "Step stopped working after repeated transport changes")
        app.buttons["Reset machine"].tap()
        let clearedHistory = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"),
                                                      object: app.buttons["Rewind one step"])
        XCTAssertEqual(XCTWaiter.wait(for: [clearedHistory], timeout: 4), .completed,
                       "One Reset tap did not clear undo history")
        scrollToTop(in: app)
        let resetCounter = cycleReadout(in: app)
        reveal(resetCounter, in: app)
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "0 cycles"), object: resetCounter)
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 4), .completed,
                       "One Reset tap did not restore the visible clock to zero")
        attachScreenshot(app, named: "Run pause stress completed")
    }

    @MainActor
    func testLoopRunsThroughKernelToExpectedScreenOutput() throws {
        let app = launch(source: Fixture.redRow)
        defer { app.terminate() }
        setPlaybackSpeed(in: app, position: 1, expectedRate: "8 cycles/s")
        app.buttons["runMachine"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "HALTED").firstMatch.waitForExistence(timeout: 45),
                      "The finite loop never completed")
        XCTAssertTrue(waitForLabel(app.buttons["runMachine"], containing: "Run"))
        XCTAssertTrue(app.staticTexts["36 ops"].exists,
                      "Unexpected instruction count; verify the deterministic loop was restored")

        for x in 0..<8 {
            assertPixel(app, x: x, y: 0, palette: "Red")
        }
        assertPixel(app, x: 0, y: 1, palette: "Off")
        assertPixel(app, x: 7, y: 7, palette: "Off")
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        attachScreenshot(app, named: "Eight red pixels after 36 instructions")
    }

    @MainActor
    func testNormalizedPlaybackPacingLiveModulationAndPersistence() throws {
        let app = launch(source: Fixture.continuousFill)
        defer { app.terminate() }
        let transport = app.buttons["runMachine"]
        let rate = app.staticTexts["playbackRateReadout"]
        XCTAssertTrue(waitForLabel(rate, containing: "2 cycles/s"),
                      "The isolated 1× baseline must run at two microcycles per second")
        app.buttons["runMachine"].tap()
        XCTAssertTrue(waitForLabel(transport, containing: "Pause"))
        XCTAssertGreaterThanOrEqual(sampleCycleAdvance(in: app, maximumRate: 2), 1,
                                    "Readable normal playback did not advance")

        // All three changes happen during execution. Endpoint positions map
        // logarithmically to 4×/8 cycles/s and 0.25×/0.5 cycles/s.
        setPlaybackSpeed(in: app, position: 1, expectedRate: "8 cycles/s")
        XCTAssertTrue(waitForLabel(transport, containing: "Pause"))
        XCTAssertGreaterThanOrEqual(sampleCycleAdvance(in: app, maximumRate: 8), 4,
                                    "Live acceleration did not advance the teaching machine")
        setPlaybackSpeed(in: app, position: 0, expectedRate: "0.5 cycles/s")
        XCTAssertTrue(waitForLabel(transport, containing: "Pause"))
        _ = sampleCycleAdvance(in: app, maximumRate: 0.5)
        setNormalPlaybackSpeed(in: app)
        XCTAssertTrue(waitForLabel(rate, containing: "2 cycles/s"))
        XCTAssertTrue(waitForLabel(transport, containing: "Pause"),
                      "Returning to 1× unexpectedly stopped execution")
        transport.tap()
        XCTAssertTrue(waitForLabel(transport, containing: "Run"))
        let pausedLabel = cycleReadout(in: app).label
        let clockChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", pausedLabel), object: cycleReadout(in: app))
        clockChanged.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [clockChanged], timeout: 1.5), .completed,
                       "Speed modulation left a clock running after Pause")

        setPlaybackSpeed(in: app, position: 1, expectedRate: "8 cycles/s")
        app.buttons["Reset machine"].tap()
        XCTAssertTrue(waitForLabel(rate, containing: "8 cycles/s"),
                      "Reset unexpectedly changed the chosen speed")
        app.terminate()
        // Drop only the speed argument override to exercise the value saved by
        // the real slider, rather than masking it with this test's baseline.
        app.launchArguments = ["-AssemblerToy.source", "HALT", "-AssemblerToy.bareMetal", "NO"]
        app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel(rate, containing: "8 cycles/s"),
                      "The chosen speed was not restored after relaunch")
        setNormalPlaybackSpeed(in: app)
        XCTAssertTrue(waitForLabel(rate, containing: "2 cycles/s"))
        app.buttons["Reset machine"].tap()
        XCTAssertTrue(waitForLabel(rate, containing: "2 cycles/s"))
        app.terminate()
        app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel(rate, containing: "2 cycles/s"),
                      "The 1× button did not persist normal playback")
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        attachScreenshot(app, named: "Readable speed modulation and saved normal playback")
    }

    @MainActor
    func testCPURegisterPanelRemainsAnchoredAcrossExecutionPhases() throws {
        let app = launch(source: Fixture.continuousFill)
        defer { app.terminate() }
        let heading = app.staticTexts["Register file"]
        let register = app.buttons["Register 0"]
        reveal(heading, in: app)
        reveal(register, in: app)
        XCTAssertTrue(heading.isHittable)
        XCTAssertTrue(register.isHittable)
        let panel = app.otherElements["cpuRegisterPanel"]
        XCTAssertTrue(panel.exists, "The shipping register section has no measurable accessibility frame")
        let headingFrame = heading.frame
        let registerFrame = register.frame
        let panelFrame = panel.frame
        XCTAssertGreaterThan(panelFrame.height, 0)
        // Real microsteps traverse two loads, XOR and all seven SYS phases.
        // The outer scroll position is set once above. Do not reveal controls
        // or scroll to compensate for any live layout movement from here on.
        for microcycle in 1...16 {
            app.buttons["stepMachine"].tap()
            assertFrame(heading.frame, equals: headingFrame, context: "Register heading")
            assertFrame(register.frame, equals: registerFrame, context: "Register control")
            assertFrame(panel.frame, equals: panelFrame, context: "Register section")
            if microcycle == 9 {
                XCTAssertTrue(waitForValue(register, equals: "1, hex 01"),
                              "The third instruction's XOR did not execute at its microcycle boundary")
            }
        }
        XCTAssertTrue(waitForValue(register, equals: "1, hex 01"))
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        attachScreenshot(app, named: "Stationary register section through CPU bus and kernel changes")
        // Measurement is complete. Reveal the resulting ALU text separately;
        // its offscreen accessibility node must not dictate the test's scroll.
        let equation = app.staticTexts["0  XOR  1  →  1"]
        reveal(equation, in: app)
        XCTAssertTrue(equation.isHittable,
                      "The measured phases never performed the actual ALU operation")
    }

    @MainActor
    func testMalformedEditorSourceCanBeCorrectedAndExecuted() throws {
        let app = launch(source: Fixture.halt)
        defer { app.terminate() }
        openAssemblyEditor(in: app)
        let editor = app.textViews["Assembly source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        replaceSource(in: editor, with: "LDI R9, 300\nBROKEN\n")
        app.buttons["Assemble & load"].tap()
        XCTAssertTrue(editor.exists, "An invalid assembly attempt dismissed the editor")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Unknown instruction")).firstMatch.waitForExistence(timeout: 5))

        replaceSource(in: editor, with: Fixture.amberPixel)
        app.buttons["Assemble & load"].tap()
        XCTAssertTrue(waitForDisappearance(editor), "Corrected source did not load")
        XCTAssertTrue(app.staticTexts["Assembled 4 instructions. Loaded into RAM."].exists)
        scrollToTop(in: app)
        app.buttons["runMachine"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "HALTED").firstMatch.waitForExistence(timeout: 20))
        assertPixel(app, x: 0, y: 0, palette: "Amber")
        assertPixel(app, x: 1, y: 0, palette: "Off")
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        attachScreenshot(app, named: "Malformed source recovered to amber pixel")
    }

    @MainActor
    func testCompactTransportAndGuidedLayersRemainUsableAtLargestTextSize() throws {
        let app = launch(source: Fixture.guidedLoadOnly, largeText: true)
        defer { app.terminate() }
        let controls = [app.buttons["runMachine"], app.buttons["stepMachine"], app.buttons["executionControlsButton"]]
        let center = controls[0].frame.midY
        for control in controls {
            XCTAssertTrue(control.exists && control.isHittable && app.frame.contains(control.frame),
                          "The complete compact transport control is not visible at largest text size: \(control)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertEqual(control.frame.midY, center, accuracy: 2,
                           "Largest text split the transport into multiple rows")
        }
        let band = controls.map { $0.frame.maxY }.max()! - controls.map { $0.frame.minY }.min()!
        XCTAssertLessThanOrEqual(band, 88,
                                 "System glass padding is allowed, but wrapped text must not create a giant bottom panel")
        XCTAssertTrue(waitForLabel(app.buttons["runMachine"], containing: "Run"))
        XCTAssertTrue(waitForValue(app.buttons["stepMachine"], equals: "One microcycle"))

        openGuidedInstruction(in: app)
        assertCompactGuidedTransport(in: app)
        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        assertCompactGuidedTransport(in: app)
        assertGuidedText("guidedR0", equals: "R0: 0 → 27 · Changed", in: app)
        XCTAssertTrue(isVisibleGuidedContent(app.staticTexts["guidedR0"], in: app))
        for (layer, title) in [("assembly", "Assembly"), ("cpu", "CPU"), ("registers", "Registers"), ("memory", "Memory"), ("os", "OS")] {
            let chip = app.buttons["guideLayer.\(layer)"]
            revealGuided(chip, identifier: "guideLayer.\(layer)", in: app)
            XCTAssertTrue(isVisibleGuidedContent(chip, in: app),
                          "The complete \(title) selector is unreachable at largest text size")
            chip.tap()
            assertGuidedText("guideSelectedLayer", equals: title, in: app)
        }
        assertGuidedText("guidedR0", equals: "R0: 0 → 27 · Changed", in: app)
        XCTAssertTrue(app.buttons["guideNextInstruction"].isEnabled)
        XCTAssertTrue(app.buttons["guidePrevious"].isHittable)
        app.buttons["guidePrevious"].tap()
        assertGuidedText("guidedR0", equals: "R0: 0 → 0 · Unchanged", in: app)
        XCTAssertTrue(app.buttons["guideNext"].isEnabled)
        closeGuidedInstruction(in: app)
        scrollToTop(in: app)
        XCTAssertEqual(cycleReadout(in: app).label, "2 cycles")
        XCTAssertEqual(app.staticTexts["programCounterReadout"].label, "0x00")
        XCTAssertTrue(app.staticTexts["0 ops"].exists)
        attachScreenshot(app, named: "Largest text retains a compact transport and real guided restoration")
    }

    @MainActor
    func testWorkbenchStepSizeAndInstructionByteInspectionStayGrounded() throws {
        let app = launch(source: Fixture.guidedPixel)
        defer { app.terminate() }
        let step = app.buttons["stepMachine"]
        XCTAssertTrue(step.isHittable && app.buttons["executionControlsButton"].isHittable,
                      "The step action and its execution-controls affordance must be available")
        XCTAssertTrue(waitForValue(step, equals: "One microcycle"))
        XCTAssertEqual(app.staticTexts["workbenchLastPhase"].label, "Last: None yet")
        XCTAssertEqual(app.staticTexts["workbenchNextPhase"].label, "Next: Fetch")

        step.tap()
        XCTAssertEqual(cycleReadout(in: app).label, "1 cycles")
        XCTAssertEqual(app.staticTexts["programCounterReadout"].label, "0x00")
        XCTAssertTrue(waitForLabel(app.staticTexts["workbenchLastPhase"], containing: "Fetch"))
        XCTAssertTrue(waitForLabel(app.staticTexts["workbenchNextPhase"], containing: "Decode"),
                      "The fetched phase and upcoming decode must have distinct visible cues")

        setStepSize(in: app, choice: "One instruction")
        XCTAssertTrue(waitForValue(step, equals: "One instruction"),
                      "The selected instruction-sized action is hidden from the workbench")
        step.tap()
        XCTAssertEqual(cycleReadout(in: app).label, "3 cycles")
        XCTAssertEqual(app.staticTexts["programCounterReadout"].label, "0x04")
        XCTAssertTrue(app.staticTexts["1 ops"].exists)
        XCTAssertTrue(waitForLabel(app.staticTexts["workbenchLastPhase"], containing: "Execute"))
        XCTAssertTrue(waitForLabel(app.staticTexts["workbenchNextPhase"], containing: "Fetch"))
        app.buttons["Rewind one step"].tap()
        XCTAssertEqual(cycleReadout(in: app).label, "1 cycles",
                       "Instruction-sized Step must remain one undo action")
        XCTAssertEqual(app.staticTexts["programCounterReadout"].label, "0x00")

        setStepSize(in: app, choice: "One microcycle")
        XCTAssertTrue(waitForValue(step, equals: "One microcycle"))
        step.tap()
        XCTAssertEqual(cycleReadout(in: app).label, "2 cycles")
        XCTAssertTrue(waitForLabel(app.staticTexts["workbenchLastPhase"], containing: "Decode"))
        XCTAssertTrue(waitForLabel(app.staticTexts["workbenchNextPhase"], containing: "Execute"))

        let assembly = app.buttons["inspectLayer.code"]
        reveal(assembly, in: app)
        assembly.tap()
        let inspect = app.buttons["inspectInstruction.0"]
        revealWorkbenchContent(inspect, in: app)
        let bytes = app.descendants(matching: .any).matching(identifier: "instructionBytes.0").firstMatch
        XCTAssertTrue(waitForValue(bytes, equals: "0x01 0x00 0x1B 0x00"))
        inspect.tap()
        let selectedAddress = app.staticTexts["selectedMemoryAddress"]
        revealWorkbenchContent(selectedAddress, in: app)
        XCTAssertEqual(selectedAddress.label, "0x00 · Code",
                       "Inspect instruction must select its actual opcode address in RAM")
        XCTAssertEqual(cycleReadout(in: app).label, "2 cycles",
                       "Navigating to bytes must not advance the machine")
        XCTAssertTrue(waitForLabel(app.buttons["runMachine"], containing: "Run"))
        attachScreenshot(app, named: "Visible step size and instruction-to-RAM inspection")
    }

    @MainActor
    func testGuidedLoadExplainsActualFetchDecodeAndExecute() throws {
        let app = launch(source: Fixture.guidedPixel)
        defer { app.terminate() }
        openGuidedInstruction(in: app)
        assertGuidedText("guideInstruction", equals: "0x00  LDI R0, 27", in: app)
        let bytes = app.descendants(matching: .any).matching(identifier: "guideInstructionBytes").firstMatch
        revealGuided(bytes, identifier: "instructionBytes", in: app)
        XCTAssertTrue(isVisibleGuidedContent(bytes, in: app))
        XCTAssertTrue(waitForValue(bytes, equals: "0x01 0x00 0x1B 0x00"),
                      "The actual instruction bytes were not exposed as their accessibility value")
        assertGuidedText("guideCompleted", equals: "Paused · Next performs exactly one microcycle", in: app)
        let nextFrame = app.buttons["guideNext"].frame
        assertGuidedText("guideMachineState", equals: "PC 0x00 · 0 ops · 0 cycles", in: app)

        advanceGuidedPhase(to: "Fetch", in: app)
        assertGuidedText("guideUpcomingPhase", equals: "Next: Decode", in: app)
        XCTAssertTrue(waitForValue(app.buttons["guideLayer.memory"], equals: "Read, Unchanged"),
                      "Instruction Fetch must show a RAM read without implying that RAM changed")
        let cue = app.descendants(matching: .any).matching(identifier: "guideExecutionCue").firstMatch
        XCTAssertTrue(isVisibleGuidedContent(cue, in: app))
        XCTAssertTrue(waitForLabel(cue, containing: "RAM 0x00–0x03. Fetched. Instruction latch."))
        assertFrame(guidedPrimaryAction(in: app).frame, equals: nextFrame, context: "Guided Next control")
        assertGuidedText("guideMachineState", equals: "PC 0x00 · 0 ops · 1 cycles", in: app)
        advanceGuidedPhase(to: "Decode", in: app)
        assertGuidedText("guideUpcomingPhase", equals: "Next: Execute", in: app)
        assertFrame(guidedPrimaryAction(in: app).frame, equals: nextFrame, context: "Guided Next control")
        assertGuidedText("guideMachineState", equals: "PC 0x00 · 0 ops · 2 cycles", in: app)
        advanceGuidedPhase(to: "Execute", in: app)
        assertFrame(guidedPrimaryAction(in: app).frame, equals: nextFrame, context: "Guided Next control")
        assertGuidedText("guideMachineState", equals: "PC 0x04 · 1 ops · 3 cycles", in: app)
        assertGuidedCompletion(in: app)
        assertGuidedText("guideUpcomingPhase", equals: "Next: instruction complete", in: app)
        assertGuidedText("guidedR0", equals: "R0: 0 → 27 · Changed", in: app)
        assertGuidedText("guideSelectedLayer", equals: "Registers", in: app)
        XCTAssertTrue(waitForValue(app.buttons["guideLayer.registers"], equals: "Written, Changed"))
        XCTAssertTrue(waitForValue(app.buttons["guideLayer.os"], equals: "No access, Unchanged"),
                      "An ordinary immediate load must not imply OS involvement")
        XCTAssertTrue(waitForLabel(cue, containing: "Immediate 27. Copied. R0 = 27."))
        let register = app.staticTexts["guidedR0"]
        XCTAssertTrue(isVisibleGuidedContent(register, in: app))
        assertGuidedText("guideUpcomingPhase", equals: "Next: instruction complete", in: app)
        XCTAssertTrue(isVisibleGuidedContent(register, in: app),
                      "Completion feedback required leaving the visible Registers lane")
        assertFrame(guidedPrimaryAction(in: app).frame, equals: nextFrame, context: "Guided Next control")
        attachScreenshot(app, named: "Guided LDI actual register write")

        closeGuidedInstruction(in: app)
        assertWorkbenchState(in: app, pc: "0x04", operations: 1, cycles: 3,
                             registerZero: "27, hex 1B", expectedRate: "2 cycles/s")
    }

    @MainActor
    func testGuidedSystemCallShowsArgumentPrivilegeDriverAndReturn() throws {
        let app = launch(source: Fixture.guidedPixel)
        defer { app.terminate() }
        openGuidedInstruction(in: app)
        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        assertGuidedCompletion(in: app)
        app.buttons["guideNextInstruction"].tap()
        assertGuidedText("guideInstruction", equals: "0x04  LDI R1, 3", in: app)
        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        assertGuidedCompletion(in: app)
        assertGuidedText("guidedR1", equals: "R1: 0 → 3 · Changed", in: app)
        app.buttons["guideNextInstruction"].tap()
        assertGuidedText("guideInstruction", equals: "0x08  SYS 1", in: app)

        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        assertGuidedText("guidedCapturedArguments", equals: "Captured arguments: R0=27, R1=3, R2=0, R3=0", in: app)
        advanceGuidedPhase(to: "Trap", in: app)
        assertGuidedText("guidedPrivilege", equals: "Privilege: User → Kernel", in: app)
        assertGuidedText("guideSelectedLayer", equals: "OS", in: app)
        advanceGuidedPhase(to: "Kernel", in: app)
        advanceGuidedPhase(to: "Driver", in: app)
        assertGuidedText("guidedMemoryWrite", equals: "0xDB: 0 → 3", in: app)
        assertGuidedText("guideSelectedLayer", equals: "Memory", in: app)
        XCTAssertTrue(waitForValue(app.buttons["guideLayer.memory"], equals: "Written, Changed"))
        let cue = app.descendants(matching: .any).matching(identifier: "guideExecutionCue").firstMatch
        XCTAssertTrue(waitForLabel(cue, containing: "Trusted driver. Written. Display RAM 0xDB."))
        attachScreenshot(app, named: "Guided SYS1 actual framebuffer driver write")
        advanceGuidedPhase(to: "Return", in: app)
        assertGuidedCompletion(in: app)
        assertGuidedText("guideMachineState", equals: "PC 0x0C · 3 ops · 13 cycles", in: app)
        assertGuidedText("guidedPrivilege", equals: "Privilege: Kernel → User", in: app)
        assertGuidedText("guidedCapturedArguments", equals: "Captured arguments: R0=27, R1=3, R2=0, R3=0", in: app)

        closeGuidedInstruction(in: app)
        scrollToTop(in: app)
        XCTAssertEqual(cycleReadout(in: app).label, "13 cycles")
        XCTAssertTrue(app.staticTexts["3 ops"].exists)
        XCTAssertEqual(app.staticTexts["programCounterReadout"].label, "0x0C")
        assertPixel(app, x: 3, y: 3, palette: "Violet")
        assertPixel(app, x: 2, y: 3, palette: "Off")
        assertPixel(app, x: 3, y: 2, palette: "Off")
        XCTAssertTrue(waitForLabel(app.buttons["runMachine"], containing: "Run"))
        XCTAssertTrue(waitForLabel(app.staticTexts["playbackRateReadout"], containing: "2 cycles/s"))
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        attachScreenshot(app, named: "Guided syscall returned with the real violet pixel")
    }

    @MainActor
    func testGuidedBackRestartAndDonePreserveMachineAndSpeed() throws {
        let app = launch(source: Fixture.guidedPixel)
        defer { app.terminate() }
        setPlaybackSpeed(in: app, position: 0, expectedRate: "0.5 cycles/s")
        openGuidedInstruction(in: app)
        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        assertGuidedCompletion(in: app)
        app.buttons["guidePrevious"].tap()
        assertGuidedText("guidePhase", equals: "Decode", in: app)
        assertGuidedText("guideMachineState", equals: "PC 0x00 · 0 ops · 2 cycles", in: app)
        assertGuidedText("guidedR0", equals: "R0: 0 → 0 · Unchanged", in: app)
        XCTAssertTrue(app.buttons["guideNext"].isEnabled)
        closeGuidedInstruction(in: app)
        // Inspect the real workbench after Back, so a presentation-only replay
        // cannot satisfy the restoration assertion.
        assertWorkbenchState(in: app, pc: "0x00", operations: 0, cycles: 2,
                             registerZero: "0, hex 00", expectedRate: "0.5 cycles/s")

        app.buttons["Reset machine"].tap()
        scrollToTop(in: app)
        openGuidedInstruction(in: app)
        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        app.buttons["guideRestart"].tap()
        assertGuidedText("guidePhase", equals: "Ready for Fetch", in: app)
        assertGuidedText("guideMachineState", equals: "PC 0x00 · 0 ops · 0 cycles", in: app)
        assertGuidedText("guidedR0", equals: "R0: 0 → 0 · Unchanged", in: app)
        XCTAssertFalse(app.buttons["guidePrevious"].isEnabled)
        XCTAssertFalse(app.buttons["guideNextInstruction"].exists)
        for phase in ["Fetch", "Decode", "Execute"] { advanceGuidedPhase(to: phase, in: app) }
        assertGuidedCompletion(in: app)
        closeGuidedInstruction(in: app)
        assertWorkbenchState(in: app, pc: "0x04", operations: 1, cycles: 3,
                             registerZero: "27, hex 1B", expectedRate: "0.5 cycles/s")
        attachScreenshot(app, named: "Guided restoration keeps actual machine and selected slow pace")
    }

    @MainActor
    func testGuidedFaultRemainsVisibleWhileInspectingOSAndBackRecovers() throws {
        let app = launch(source: Fixture.guidedFault)
        defer { app.terminate() }
        openGuidedInstruction(in: app)
        for phase in ["Fetch", "Decode"] {
            advanceGuidedPhase(to: phase, in: app)
        }
        assertGuidedText("guidedPrivilege", equals: "Privilege: User → User", in: app)
        let privilege = app.staticTexts["guidedPrivilege"]
        XCTAssertTrue(isVisibleGuidedContent(privilege, in: app),
                      "The OS lane must be visible before the protected memory write")
        let osFrame = privilege.frame
        advanceGuidedPhase(to: "Execute", in: app)
        assertGuidedText("guidePinnedFault", equals: "Fault: User code cannot write display RAM at 192; use SYS 1 or SYS 2.", in: app)
        assertGuidedText("guideUpcomingPhase", equals: "Next: program stopped", in: app)
        XCTAssertTrue(isVisibleGuidedContent(privilege, in: app),
                      "Fault feedback required leaving the inspected OS lane")
        assertFrame(privilege.frame, equals: osFrame, context: "Guided OS privilege row")
        XCTAssertFalse(app.buttons["guideNext"].exists)
        XCTAssertFalse(app.buttons["guideNextInstruction"].isEnabled)
        XCTAssertTrue(app.buttons["guidePrevious"].isEnabled)
        XCTAssertTrue(app.buttons["guideRestart"].isEnabled)
        attachScreenshot(app, named: "Guided display-write protection fault remains visible beside OS values")

        app.buttons["guidePrevious"].tap()
        assertGuidedText("guidePhase", equals: "Decode", in: app)
        XCTAssertFalse(app.staticTexts["guidePinnedFault"].exists)
        assertGuidedText("guideUpcomingPhase", equals: "Next: Execute", in: app)
        XCTAssertTrue(isVisibleGuidedContent(privilege, in: app),
                      "Back unexpectedly moved away from the OS lane")
        XCTAssertTrue(app.buttons["guideNext"].isEnabled)
        assertGuidedText("guidedPrivilege", equals: "Privilege: User → User", in: app)
        closeGuidedInstruction(in: app)
        XCTAssertFalse(app.staticTexts["Machine fault"].exists,
                       "Back did not clear the actual machine's protected-write fault")
        attachScreenshot(app, named: "Back recovers guided memory protection without resetting the program")
    }

    @MainActor
    func testMemoryProbeFlipsBytesAndRewindRestoresOutput() throws {
        let app = launch(source: Fixture.halt)
        defer { app.terminate() }
        app.buttons["Pixel 0, 0"].tap()
        let bitZero = app.buttons["Bit 0"]
        reveal(bitZero, in: app)
        XCTAssertTrue(bitZero.isHittable)
        XCTAssertEqual(bitZero.value as? String, "Zero")
        bitZero.tap()
        XCTAssertTrue(waitForValue(bitZero, equals: "One"))
        app.buttons["Bit 1"].tap()
        XCTAssertTrue(waitForValue(app.buttons["Bit 1"], equals: "One"))
        app.buttons["Bit 7"].tap()
        XCTAssertTrue(waitForValue(app.buttons["Bit 7"], equals: "One"))
        XCTAssertTrue(app.staticTexts["Probe wrote 0x83 at 0xC0."].waitForExistence(timeout: 4))

        scrollToTop(in: app)
        assertPixel(app, x: 0, y: 0, palette: "Violet")
        assertPixel(app, x: 1, y: 0, palette: "Off")
        // Keep the byte probe visible while checking each atomic rewind.
        // SwiftUI may omit or retain stale values for offscreen AX children.
        reveal(app.buttons["Bit 7"], in: app)
        app.buttons["Rewind one step"].tap()
        reveal(app.buttons["Bit 7"], in: app)
        XCTAssertTrue(waitForValue(app.buttons["Bit 7"], equals: "Zero"),
                      "First rewind did not restore byte 3 from byte 131")
        XCTAssertTrue(waitForValue(app.buttons["Bit 1"], equals: "One"))
        app.buttons["Rewind one step"].tap()
        reveal(app.buttons["Bit 1"], in: app)
        XCTAssertTrue(waitForValue(app.buttons["Bit 1"], equals: "Zero"),
                      "Second rewind did not restore byte 1 from byte 3")
        XCTAssertTrue(waitForValue(bitZero, equals: "One"))
        app.buttons["Rewind one step"].tap()
        reveal(bitZero, in: app)
        XCTAssertTrue(waitForValue(bitZero, equals: "Zero"),
                      "Third rewind did not restore byte zero")
        scrollToTop(in: app)
        assertPixel(app, x: 0, y: 0, palette: "Off")
        XCTAssertFalse(app.buttons["Rewind one step"].isEnabled)

        reveal(bitZero, in: app)
        for _ in 0..<10 {
            bitZero.tap()
            XCTAssertTrue(waitForValue(bitZero, equals: "One"))
            app.buttons["Rewind one step"].tap()
            XCTAssertTrue(waitForValue(bitZero, equals: "Zero"))
        }
        scrollToTop(in: app)
        assertPixel(app, x: 0, y: 0, palette: "Off")
        attachScreenshot(app, named: "Byte probe and repeated rewind")
    }

    @MainActor
    func testPaintedDrawingBuildsAndRunsAsSoftware() throws {
        let app = launch(source: Fixture.halt)
        defer { app.terminate() }
        setPlaybackSpeed(in: app, position: 1, expectedRate: "8 cycles/s")
        let draw = app.buttons["Draw"]
        reveal(draw, in: app)
        draw.tap()
        XCTAssertTrue(app.navigationBars["Draw software"].waitForExistence(timeout: 5))

        let clear = app.buttons["Clear"]
        revealAboveFooter(clear, footer: app.buttons["buildDrawing"], in: app)
        clear.tap()
        XCTAssertTrue(app.navigationBars["Draw software"].exists,
                      "The drawing sheet disappeared before painting")
        // Do not drag downward past the modal's top: UIKit treats that as
        // interactive dismissal. Select the presented, hittable canvas node.
        let paintedPixels = app.buttons.matching(identifier: "Pixel 3, 3")
        guard let paintedPixel = paintedPixels.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("The presented drawing canvas has no hittable pixel (3, 3)")
            return
        }
        paintedPixel.tap()
        XCTAssertTrue(waitForValue(paintedPixel, equals: "Cyan"),
                      "Touching the WYSIWYG pixel did not change its color")
        XCTAssertTrue(app.navigationBars["Draw software"].exists,
                      "Painting dismissed the drawing sheet")
        app.buttons["buildDrawing"].tap()
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Draw software"]))
        XCTAssertTrue(app.staticTexts.matching(identifier: "HALTED").firstMatch.waitForExistence(timeout: 240),
                      "Generated 64-pixel program failed to complete")
        scrollToTop(in: app)
        XCTAssertTrue(app.staticTexts["YOUR SPRITE"].exists)
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        for y in 0..<8 {
            for x in 0..<8 {
                assertPixel(app, x: x, y: y, palette: x == 3 && y == 3 ? "Cyan" : "Off")
            }
        }
        attachScreenshot(app, named: "One painted pixel reproduced by generated assembly")
    }

    @MainActor
    func testDrawingBuildRetainsNormalPlaybackSpeed() throws {
        let app = launch(source: Fixture.halt)
        defer { app.terminate() }
        setNormalPlaybackSpeed(in: app)
        XCTAssertTrue(waitForLabel(app.staticTexts["playbackRateReadout"], containing: "2 cycles/s"))
        let draw = app.buttons["Draw"]
        reveal(draw, in: app)
        draw.tap()
        XCTAssertTrue(app.navigationBars["Draw software"].waitForExistence(timeout: 5))
        app.buttons["buildDrawing"].tap()
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Draw software"]))
        let transport = app.buttons["runMachine"]
        XCTAssertTrue(waitForLabel(transport, containing: "Pause"))
        XCTAssertTrue(waitForLabel(app.staticTexts["playbackRateReadout"], containing: "2 cycles/s"),
                      "Build & run replaced the user's chosen normal speed")
        transport.tap()
        XCTAssertTrue(waitForLabel(transport, containing: "Run"))
        XCTAssertTrue(waitForLabel(app.staticTexts["playbackRateReadout"], containing: "2 cycles/s"))
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
        attachScreenshot(app, named: "Drawing starts at the retained readable normal speed")
    }

    @MainActor
    func testRepeatedSheetPresentationAndLandscapeLargeTextRemainUsable() throws {
        let app = launch(source: Fixture.halt, largeText: true)
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        for iteration in 0..<3 {
            for (button, navigationTitle) in [("Layers", "Every layer"), ("Programs", "Program library"), ("Draw", "Draw software")] {
                let opener = app.buttons[button]
                reveal(opener, in: app)
                opener.tap()
                XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 5),
                              "Sheet \(navigationTitle) failed on repetition \(iteration)")
                app.buttons["Done"].tap()
                XCTAssertTrue(waitForDisappearance(app.navigationBars[navigationTitle]))
                XCTAssertTrue(app.buttons["runMachine"].isHittable)
            }
            scrollToTop(in: app)
            app.buttons["Machine specification and help"].tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
            XCTAssertTrue(waitForDisappearance(app.buttons["Done"]))
        }

        let gates = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Logic & silicon")).firstMatch
        reveal(gates, in: app)
        gates.tap()
        XCTAssertTrue(app.navigationBars["Gate bench"].waitForExistence(timeout: 5))
        let xor = app.buttons["Select XOR operation"]
        reveal(xor, in: app)
        xor.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "XOR lights a result bit")).firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Gate bench"]))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["runMachine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["runMachine"].isHittable, "Landscape obscured the transport")
        app.buttons["stepMachine"].tap()
        app.buttons["Reset machine"].tap()
        attachScreenshot(app, named: "Landscape with accessibility largest text requested")
        XCUIDevice.shared.orientation = .portrait
        scrollToTop(in: app)
        reveal(app.buttons["hardwareInput"], in: app)
        XCTAssertTrue(app.buttons["hardwareInput"].isHittable)
        app.buttons["hardwareInput"].tap()
        XCTAssertTrue(waitForValue(app.buttons["hardwareInput"], equals: "High, one"))
        attachScreenshot(app, named: "Portrait after sheet orientation stress")
    }

    @MainActor
    private func launch(source: String, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AssemblerToy.source", "HALT", "-AssemblerToy.bareMetal", "NO",
                               "-AssemblerToy.playbackSpeed", "1"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["runMachine"].waitForExistence(timeout: 15), "The workbench did not launch")
        XCTAssertTrue(app.staticTexts["YOUR PROGRAM"].waitForExistence(timeout: 5),
                      "The source launch argument was not restored. A fallback sample must never satisfy this test.")
        XCTAssertEqual(cycleReadout(in: app).label, "0 cycles", "Fixture must start without execution")

        openAssemblyEditor(in: app)
        let editor = app.textViews["Assembly source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(editor, equals: "HALT"),
                      "The exact single-line baseline was not restored in the normal editor")
        if source != "HALT" { replaceSource(in: editor, with: source) }
        app.buttons["Assemble & load"].tap()
        XCTAssertTrue(waitForDisappearance(editor), "The normal editor could not assemble the fixture")
        assertLoadedFixture(source, in: app)
        let machine = app.buttons["inspectLayer.machine"]
        reveal(machine, in: app)
        machine.tap()
        scrollToTop(in: app)
        XCTAssertEqual(cycleReadout(in: app).label, "0 cycles")
        return app
    }

    @MainActor
    private func openAssemblyEditor(in app: XCUIApplication) {
        let assembly = app.buttons["inspectLayer.code"]
        reveal(assembly, in: app)
        assembly.tap()
        let edit = app.buttons["editAssemblySource"]
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.navigationBars["Assembly editor"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func replaceSource(in editor: XCUIElement, with source: String) {
        let previous = editor.value as? String ?? ""
        // Tap below the short fixture so the insertion point is at its end,
        // then use real keyboard editing instead of assigning accessibility data.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count + 1))
        editor.typeText(source)
        XCTAssertTrue(waitForValue(editor, equals: source),
                      "The native source edit did not replace the complete fixture")
    }

    @MainActor
    private func assertLoadedFixture(_ source: String, in app: XCUIApplication) {
        let count: Int
        let firstBytes: String
        let lastBytes: String
        switch source {
        case Fixture.redRow:
            count = 8; firstBytes = "01 00 00 00"; lastBytes = "17 06 00 00"
        case Fixture.continuousFill:
            count = 5; firstBytes = "01 00 00 00"; lastBytes = "0E 08 00 00"
        case Fixture.amberPixel:
            count = 4; firstBytes = "01 00 00 00"; lastBytes = "17 06 00 00"
        case Fixture.guidedPixel:
            count = 4; firstBytes = "01 00 1B 00"; lastBytes = "18 00 00 00"
        case Fixture.guidedLoadOnly:
            count = 2; firstBytes = "01 00 1B 00"; lastBytes = "18 00 00 00"
        case Fixture.guidedFault:
            count = 2; firstBytes = "0A 00 C0 00"; lastBytes = "18 00 00 00"
        default:
            count = 1; firstBytes = "18 00 00 00"; lastBytes = "18 00 00 00"
        }
        let first = app.descendants(matching: .any).matching(identifier: "instructionBytes.0").firstMatch
        let last = app.descendants(matching: .any).matching(identifier: "instructionBytes.\((count - 1) * 4)").firstMatch
        let formattedFirst = firstBytes.split(separator: " ").map { "0x\($0)" }.joined(separator: " ")
        let formattedLast = lastBytes.split(separator: " ").map { "0x\($0)" }.joined(separator: " ")
        XCTAssertTrue(first.waitForExistence(timeout: 4) && waitForValue(first, equals: formattedFirst),
                      "The assembled fixture's first instruction bytes were not loaded")
        XCTAssertTrue(last.waitForExistence(timeout: 4) && waitForValue(last, equals: formattedLast),
                      "The assembled fixture's final instruction bytes were not loaded")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Breakpoint at address")).count, count,
                       "The assembled fixture has an unexpected number of instruction rows")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 12) {
        for _ in 0..<attempts {
            if isVisibleContent(element, in: app) { return }
            let window = visibleContentWindow(in: app)
            let targetAbove = element.exists && element.frame.minY < window.minY
            dragContent(in: app, window: window, towardBottom: !targetAbove)
        }
        XCTAssertTrue(isVisibleContent(element, in: app),
                      "Could not reveal the complete control above the actual footer: \(element)")
    }

    @MainActor
    private func revealWorkbenchContent(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
    }

    @MainActor
    private func visibleContentWindow(in app: XCUIApplication) -> CGRect {
        var top = app.frame.minY
        let status = app.statusBars.firstMatch
        if status.exists { top = max(top, status.frame.maxY) }
        let navigation = app.navigationBars.firstMatch
        if navigation.exists && navigation.isHittable { top = max(top, navigation.frame.maxY) }
        // The first transport row sits above the last/next readouts. Derive the
        // band from its actual visible controls, rather than a screen fraction
        // or the second footer row that could accept obscured content.
        let identifiers = ["runMachine", "stepMachine", "Reset machine", "Rewind one step", "buildDrawing"]
        let controls = identifiers.map { app.buttons[$0] }.filter {
            $0.exists && $0.isHittable && $0.frame.width > 0 && $0.frame.height > 0
        }
        let bottom = controls.map { $0.frame.minY }.min().map { $0 - 8 } ?? app.frame.maxY
        return CGRect(x: app.frame.minX, y: top, width: app.frame.width,
                      height: max(0, bottom - top))
    }

    @MainActor
    private func isVisibleContent(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists && element.isHittable else { return false }
        let frame = element.frame
        return frame.width > 0 && frame.height > 0 && visibleContentWindow(in: app).contains(frame)
    }

    @MainActor
    private func dragContent(in app: XCUIApplication, window: CGRect, towardBottom: Bool) {
        XCTAssertGreaterThan(window.height, 60, "The shipping UI has no usable visible content band")
        let upper = (window.minY + window.height * 0.28 - app.frame.minY) / app.frame.height
        let lower = (window.minY + window.height * 0.80 - app.frame.minY) / app.frame.height
        // The outer gutter is outside the direct-manipulation canvas.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: towardBottom ? lower : upper))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: towardBottom ? upper : lower))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func revealAboveFooter(_ element: XCUIElement, footer: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            XCTAssertTrue(app.navigationBars["Draw software"].exists,
                          "Drawing sheet disappeared while revealing its controls")
            if element.exists && footer.exists && element.isHittable,
               element.frame.maxY <= footer.frame.minY - 8 { return }
            // Transparent glass can leave a covered content control marked
            // hittable. Scroll its full frame above the fixed footer first.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.82))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.32)))
        }
        XCTAssertTrue(element.exists && element.isHittable && element.frame.maxY <= footer.frame.minY - 8,
                      "Could not reveal the drawing control above the build footer")
    }

    @MainActor
    private func scrollToTop(in app: XCUIApplication) {
        let header = app.buttons["Machine specification and help"]
        for _ in 0..<12 {
            if isVisibleContent(header, in: app) { return }
            dragContent(in: app, window: visibleContentWindow(in: app), towardBottom: false)
        }
        XCTAssertTrue(isVisibleContent(header, in: app), "Could not reveal the complete workbench header")
    }

    @MainActor
    private func cycleReadout(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9,]+ cycles")).firstMatch
    }

    @MainActor
    private func openGuidedInstruction(in app: XCUIApplication) {
        let opener = app.buttons["guidedModeButton"]
        reveal(opener, in: app)
        opener.tap()
        XCTAssertTrue(app.navigationBars["Guided instruction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guideDone"].isHittable)
        assertGuidedText("guidePhase", equals: "Ready for Fetch", in: app)
        assertGuidedText("guideUpcomingPhase", equals: "Next: Fetch", in: app)
        XCTAssertFalse(app.buttons["guidePrevious"].isEnabled)
    }

    @MainActor
    private func closeGuidedInstruction(in app: XCUIApplication) {
        app.buttons["guideDone"].tap()
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Guided instruction"]),
                      "Done did not return to the real workbench")
        XCTAssertTrue(waitForLabel(app.buttons["runMachine"], containing: "Run"))
    }

    @MainActor
    private func advanceGuidedPhase(to phase: String, in app: XCUIApplication) {
        let next = app.buttons["guideNext"]
        XCTAssertTrue(next.isHittable && next.isEnabled, "Guide cannot advance to \(phase)")
        next.tap()
        assertGuidedText("guidePhase", equals: phase, in: app)
    }

    @MainActor
    private func assertGuidedCompletion(in app: XCUIApplication) {
        assertGuidedText("guideCompleted", equals: "Instruction complete · choose Next instruction when ready", in: app)
        XCTAssertFalse(app.buttons["guideNext"].exists,
                       "A completed walkthrough still offers another phase of the same instruction")
        XCTAssertTrue(app.buttons["guideNextInstruction"].isEnabled)
    }

    @MainActor
    private func guidedPrimaryAction(in app: XCUIApplication) -> XCUIElement {
        let next = app.buttons["guideNext"]
        return next.exists ? next : app.buttons["guideNextInstruction"]
    }

    @MainActor
    private func assertCompactGuidedTransport(in app: XCUIApplication) {
        let controls = [app.buttons["guidePrevious"], app.buttons["guideRestart"], guidedPrimaryAction(in: app)]
        let center = controls[0].frame.midY
        for control in controls {
            // Back/Restart are deliberately disabled at entry, but their
            // visible frames must still fit the same compact action row.
            XCTAssertTrue(control.exists && app.frame.contains(control.frame),
                          "The complete guide action is outside the visible screen")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertEqual(control.frame.midY, center, accuracy: 2,
                           "Largest text split the guide actions into multiple rows")
        }
        let band = controls.map { $0.frame.maxY }.max()! - controls.map { $0.frame.minY }.min()!
        XCTAssertLessThanOrEqual(band, 88,
                                 "The guide must not turn phase/instruction labels into a tall bottom panel")
        XCTAssertTrue(guidedPrimaryAction(in: app).isHittable)
    }

    @MainActor
    private func assertGuidedText(_ identifier: String, equals text: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let visibleIdentifier = identifier
        let element = app.descendants(matching: .any).matching(identifier: visibleIdentifier).firstMatch
        revealGuided(element, identifier: visibleIdentifier, in: app)
        // Native accessibility queries can consume several seconds on this
        // simulator. Accept an already-settled exact label before scheduling
        // a waiter; visibility still requires the complete content frame.
        if element.label == text { return }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed,
                       "Incorrect guided readout for \(identifier): \(element.label)", file: file, line: line)
    }

    @MainActor
    private func revealGuided(_ element: XCUIElement, identifier: String, in app: XCUIApplication) {
        let scroll = app.scrollViews.matching(identifier: "guidedInstructionScroll").firstMatch
        XCTAssertTrue(scroll.exists, "The actual guided scroll surface is missing")
        if identifier == "guidePinnedFault" {
            XCTAssertTrue(element.exists && element.isHittable && app.frame.contains(element.frame),
                          "The complete actual fault is not visible above the compact guide controls")
            return
        }
        if isVisibleGuidedContent(element, in: app) { return }
        let layer: String?
        switch identifier {
        case "guidedR0", "guidedR1", "guidedR2", "guidedR3": layer = "registers"
        case "guidedMemoryWrite": layer = "memory"
        case "guidedPrivilege", "guidedCapturedArguments": layer = "os"
        default: layer = nil
        }
        if let layer {
            let chip = app.buttons["guideLayer.\(layer)"]
            seekVisibleGuided(chip, in: app, scroll: scroll)
            XCTAssertTrue(isVisibleGuidedContent(chip, in: app),
                          "The real \(layer) navigation chip is clipped or covered by the footer")
            chip.tap()
            XCTAssertTrue(element.waitForExistence(timeout: 4),
                          "Native \(layer) navigation did not present \(identifier)")
            seekVisibleGuided(element, in: app, scroll: scroll)
            return
        }
        seekVisibleGuided(element, in: app, scroll: scroll)
    }

    @MainActor
    private func seekVisibleGuided(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement) {
        for _ in 0..<10 {
            if isVisibleGuidedContent(element, in: app) { return }
            let window = guidedContentWindow(in: app).intersection(scroll.frame)
            let targetAbove = element.exists && element.frame.minY < window.minY
            dragGuidedContent(in: app, scroll: scroll, towardBottom: !targetAbove)
        }
        XCTAssertTrue(isVisibleGuidedContent(element, in: app),
                      "Could not reveal the complete guided readout \(element) above the footer")
    }

    @MainActor
    private func guidedContentWindow(in app: XCUIApplication) -> CGRect {
        let navigationBottom = app.navigationBars["Guided instruction"].frame.maxY
        let controls = [app.buttons["guidePrevious"], app.buttons["guideRestart"], guidedPrimaryAction(in: app)]
        var footerTop = (controls.filter { $0.exists }.map { $0.frame.minY }.min() ?? app.frame.maxY) - 8
        let fault = app.staticTexts["guidePinnedFault"]
        if fault.exists { footerTop = min(footerTop, fault.frame.minY - 8) }
        return CGRect(x: app.frame.minX, y: navigationBottom,
                      width: app.frame.width, height: max(0, footerTop - navigationBottom))
    }

    @MainActor
    private func isVisibleGuidedContent(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        return frame.width > 0 && frame.height > 0 && guidedContentWindow(in: app).contains(frame)
    }

    @MainActor
    private func dragGuidedContent(in app: XCUIApplication, scroll: XCUIElement, towardBottom: Bool) {
        // AX may mark footer-covered content hittable and report a scroll frame
        // that extends underneath the footer. Derive the real content band from
        // the visible navigation bar and compact action row before every gesture.
        let window = guidedContentWindow(in: app).intersection(scroll.frame)
        XCTAssertGreaterThan(window.height, 60, "The guide has no usable visible scroll content")
        let upper = (window.minY + window.height * 0.28 - scroll.frame.minY) / scroll.frame.height
        let lower = (window.minY + window.height * 0.80 - scroll.frame.minY) / scroll.frame.height
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: towardBottom ? lower : upper))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: towardBottom ? upper : lower))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func assertWorkbenchState(in app: XCUIApplication, pc: String, operations: Int, cycles: Int,
                                      registerZero: String, expectedRate: String) {
        scrollToTop(in: app)
        XCTAssertEqual(cycleReadout(in: app).label, "\(cycles) cycles")
        XCTAssertTrue(app.staticTexts["\(operations) ops"].exists)
        XCTAssertEqual(app.staticTexts["programCounterReadout"].label, pc)
        XCTAssertTrue(waitForLabel(app.buttons["runMachine"], containing: "Run"))
        XCTAssertTrue(waitForLabel(app.staticTexts["playbackRateReadout"], containing: expectedRate))
        let register = app.buttons["Register 0"]
        reveal(register, in: app)
        XCTAssertTrue(waitForValue(register, equals: registerZero))
        XCTAssertFalse(app.staticTexts["Machine fault"].exists)
    }

    @MainActor
    private func setPlaybackSpeed(in app: XCUIApplication, position: CGFloat, expectedRate: String) {
        openExecutionControls(in: app)
        let slider = app.sliders["playbackSpeedSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        reveal(slider, in: app)
        slider.adjust(toNormalizedSliderPosition: position)
        XCTAssertTrue(waitForLabel(app.staticTexts["controlsPlaybackRateReadout"], containing: expectedRate),
                      "The native slider did not select \(expectedRate)")
        closeExecutionControls(in: app)
        XCTAssertTrue(waitForLabel(app.staticTexts["playbackRateReadout"], containing: expectedRate))
    }

    @MainActor
    private func setNormalPlaybackSpeed(in app: XCUIApplication) {
        openExecutionControls(in: app)
        let normal = app.buttons["normalPlaybackSpeed"]
        reveal(normal, in: app)
        normal.tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["controlsPlaybackRateReadout"], containing: "2 cycles/s"))
        closeExecutionControls(in: app)
    }

    @MainActor
    private func setStepSize(in app: XCUIApplication, choice: String) {
        openExecutionControls(in: app)
        let picker = app.segmentedControls["stepSizeControl"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let option = picker.buttons[choice]
        reveal(option, in: app)
        option.tap()
        closeExecutionControls(in: app)
    }

    @MainActor
    private func openExecutionControls(in app: XCUIApplication) {
        let opener = app.buttons["executionControlsButton"]
        XCTAssertTrue(opener.exists && opener.isHittable, "The compact execution-controls affordance is unavailable")
        opener.tap()
        XCTAssertTrue(app.navigationBars["Execution controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["executionControlsDone"].isHittable)
    }

    @MainActor
    private func closeExecutionControls(in app: XCUIApplication) {
        app.buttons["executionControlsDone"].tap()
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Execution controls"]),
                      "Done did not return from execution controls to the workbench")
    }

    @MainActor
    @discardableResult
    private func sampleCycleAdvance(in app: XCUIApplication, maximumRate: Double) -> Int {
        let before = Int(cycleReadout(in: app).label.filter(\.isNumber)) ?? -1
        XCTAssertGreaterThanOrEqual(before, 0)
        let started = ProcessInfo.processInfo.systemUptime
        let window = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: NSObject())
        window.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [window], timeout: 2), .completed)
        let after = Int(cycleReadout(in: app).label.filter(\.isNumber)) ?? -1
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let advanced = after - before
        XCTAssertGreaterThanOrEqual(advanced, 0, "Changing speed rewound or reset the machine")
        // Include snapshot latency and a small allowance for the 450-ms
        // smooth speed ramp and integer cycle boundaries. This still rejects
        // the old default60/forced240 behavior by a large margin.
        XCTAssertLessThanOrEqual(Double(advanced), maximumRate * elapsed + 4,
                                 "Playback advanced faster than its readable selected rate")
        return advanced
    }

    @MainActor
    private func assertFrame(_ actual: CGRect, equals expected: CGRect, context: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1,
                       "\(context) moved horizontally during execution", file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1,
                       "\(context) moved vertically during execution", file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1,
                       "\(context) changed width during execution", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1,
                       "\(context) changed height during execution", file: file, line: line)
    }

    @MainActor
    private func assertPixel(_ app: XCUIApplication, x: Int, y: Int, palette: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let pixel = app.buttons.matching(identifier: "Pixel \(x), \(y)").firstMatch
        XCTAssertTrue(pixel.exists, "Missing pixel (\(x), \(y))", file: file, line: line)
        XCTAssertTrue(waitForValue(pixel, equals: palette), "Wrong pixel (\(x), \(y)); actual \(String(describing: pixel.value))", file: file, line: line)
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 4) == .completed
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, equals value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 4) == .completed
    }

    @MainActor
    private func waitForDisappearance(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum Fixture {
    static let halt = "HALT"
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
    static let guidedPixel = """
    LDI R0, 27
    LDI R1, 3
    SYS 1
    HALT
    """
    static let guidedLoadOnly = """
    LDI R0, 27
    HALT
    """
    static let guidedFault = """
    ST R0, 192
    HALT
    """
}
