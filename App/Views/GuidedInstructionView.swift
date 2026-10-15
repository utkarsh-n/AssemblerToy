import SwiftUI
import AssemblerCore

/// Manual inspection of the real interpreter. The session remains the only
/// owner of stepping, history, and exact snapshot restoration.
struct GuidedInstructionView: View {
    let session: MachineSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var initialized = false
    @State private var selectedLayer: GuidedLayer = .cpu
    @State private var expandedLayers: Set<GuidedLayer> = []

    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentDesignBackground()
                if let guide = session.guidedInstruction {
                    if typeSize.isAccessibilitySize {
                        // At large text sizes, all context remains reachable
                        // without squeezing the value pane to zero height.
                        ScrollView {
                            VStack(spacing: 10) {
                                guideContext(guide)
                                selectedPanel(guide)
                            }
                            .padding(12)
                        }
                        .accessibilityIdentifier("guidedInstructionScroll")
                    } else {
                        VStack(spacing: 10) {
                            // Context and manual layer navigation stay in place
                            // while the selected layer's complete facts scroll.
                            guideContext(guide)
                            ScrollView {
                                selectedPanel(guide)
                                    .padding(.bottom, 8)
                            }
                            .accessibilityIdentifier("guidedInstructionScroll")
                        }
                        .padding(.horizontal, 12).padding(.top, 10)
                    }
                } else {
                    ScrollView { stoppedPanel.padding(16) }
                        .accessibilityIdentifier("guidedInstructionScroll")
                }
            }
            .navigationTitle("Guided instruction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        session.endGuidedInstruction()
                        dismiss()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("guideDone")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        }
        .preferredColorScheme(.dark)
        .transaction { $0.animation = nil }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if session.guidedInstruction == nil { session.startGuidedInstruction() }
        }
        .onDisappear { session.endGuidedInstruction() }
    }

    private func guideContext(_ guide: GuidedInstruction) -> some View {
        VStack(spacing: 10) {
            compactPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("0x\(ToyInk.hex(guide.instructionAddress))  \(guide.instruction?.description ?? "Undecoded bytes")")
                        .font(.system(.headline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(InstrumentPalette.displayInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("guideInstruction")
                    NamedInstructionBytesView(bytes: guide.executionBytes, identifier: "guideInstructionBytes")
                    phaseContext(guide)
                    Text("PC 0x\(ToyInk.hex(guide.currentMachine.pc)) · \(guide.currentMachine.instructionCount) ops · \(guide.currentMachine.cycleCount) cycles")
                        .font(.system(.caption2, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                        .accessibilityIdentifier("guideMachineState")
                }
            }
            ExecutionTransferView(cue: ExecutionCue(machine: guide.currentMachine, step: guide.latestStep), identifier: "guideExecutionCue")
            layerSelector(guide)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    private func phaseContext(_ guide: GuidedInstruction) -> some View {
        let phases = plannedPhases(guide)
        return VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(guide.latestStep == nil ? "Paused" : "Completed")
                        .font(.caption2)
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                    Text(guide.latestStep?.executedPhase.title ?? "Ready for \(guide.baseline.nextPhase.title)")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(InstrumentPalette.actionAmber)
                        .accessibilityIdentifier("guidePhase")
                    Text(upcomingPhase(guide))
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(InstrumentPalette.actionCyan)
                        .accessibilityIdentifier("guideUpcomingPhase")
                    Text("Step \(guide.steps.count) / \(phases.count)")
                        .font(.system(.caption2, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                        .accessibilityIdentifier("guideProgress")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(guide.latestStep == nil ? "Paused" : "Completed")
                                .foregroundStyle(InstrumentPalette.secondaryInk)
                            Text(guide.latestStep?.executedPhase.title ?? "Ready for \(guide.baseline.nextPhase.title)")
                                .foregroundStyle(InstrumentPalette.actionAmber)
                                .accessibilityIdentifier("guidePhase")
                        }
                        Text(upcomingPhase(guide))
                            .foregroundStyle(InstrumentPalette.actionCyan)
                            .accessibilityIdentifier("guideUpcomingPhase")
                    }
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    Spacer(minLength: 4)
                    Text("Step \(guide.steps.count) / \(phases.count)")
                        .font(.system(.caption2, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                        .accessibilityIdentifier("guideProgress")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: typeSize.isAccessibilitySize ? 1 : min(4, max(1, phases.count))), spacing: 4) {
                ForEach(phases) { phase in
                    HStack(spacing: 3) {
                        Image(systemName: phaseSymbol(phase, guide: guide))
                            .accessibilityHidden(true)
                        Text(phase.title)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(phaseAccent(phase, guide: guide))
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(phase.title), \(phaseState(phase, guide: guide))")
                }
            }
        }
    }

    private func layerSelector(_ guide: GuidedInstruction) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: typeSize.isAccessibilitySize ? 1 : 5), spacing: 5) {
            ForEach(GuidedLayer.allCases) { layer in
                let selected = selectedLayer == layer
                Button { selectedLayer = layer } label: {
                    VStack(spacing: 3) {
                        Text(layer.title)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(selected ? InstrumentPalette.displayInk : InstrumentPalette.secondaryInk)
                        Text(layerAccess(layer, guide: guide))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(layerAccessAccent(layer, guide: guide))
                        Text(layerDelta(layer, guide: guide))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(layerHasChanges(layer, guide: guide) ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .padding(.vertical, 5)
                    .background(selected ? InstrumentPalette.actionCyan.opacity(0.10) : .black.opacity(0.16), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? InstrumentPalette.actionCyan : .white.opacity(0.12), lineWidth: selected ? 1.5 : 1)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Inspect \(layer.title)")
                .accessibilityValue("\(layerAccess(layer, guide: guide)), \(layerDelta(layer, guide: guide))")
                .accessibilityHint("Shows this layer's actual values for the current microcycle")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("guideLayer.\(layer.id)")
            }
        }
    }

    private func selectedPanel(_ guide: GuidedInstruction) -> some View {
        compactPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(selectedLayer.title, systemImage: layerSymbol(selectedLayer))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(InstrumentPalette.displayInk)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(selectedLayer.title)
                        .accessibilityIdentifier("guideSelectedLayer")
                    Spacer(minLength: 4)
                    Text(guide.latestStep == nil ? "Entry values" : "This microcycle")
                        .font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
                }
                primaryFacts(selectedLayer, guide: guide)
                Text(completionStatus(guide))
                    .font(.caption2)
                    .foregroundStyle(guide.currentMachine.fault == nil ? InstrumentPalette.secondaryInk : InstrumentPalette.actionAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("guideCompleted")
                DisclosureGroup(isExpanded: detailsBinding(selectedLayer)) {
                    VStack(alignment: .leading, spacing: 12) {
                        completeFacts(selectedLayer, guide: guide)
                        fact("Phase explanation", narration(guide))
                            .accessibilityIdentifier("guideNarration")
                        if guide.isPartwayThroughInstruction {
                            Text("This guide began partway through the instruction. Back and Restart restore that exact entry state.")
                                .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                        }
                        if !guide.steps.isEmpty {
                            Text("Microcycle history")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                            ForEach(guide.steps) { step in
                                fact("\(step.id) · \(step.executedPhase.title)", step.explanation)
                            }
                        }
                        Text("AT-8 is a teaching CPU and OS. Values, microcycles and device events come from this running model. Reads leave bytes intact; a write can store the same value.")
                            .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("All \(selectedLayer.title) details", systemImage: "list.bullet.rectangle")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .frame(minHeight: 44)
                }
                .tint(InstrumentPalette.actionCyan)
                .accessibilityIdentifier("guideDetails.\(selectedLayer.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(layerIdentifier(selectedLayer))
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func primaryFacts(_ layer: GuidedLayer, guide: GuidedInstruction) -> some View {
        let before = guide.latestStep?.before ?? guide.baseline
        let after = guide.currentMachine
        switch layer {
        case .assembly:
            if let row = guide.sourceRow {
                fact("Source line \(row.lineNumber)", row.source)
            } else {
                Text("No assembled source row maps to this address.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            }
            changeRows(changes(for: .assembly, guide: guide), empty: "No source or decoder change in this microcycle.")
        case .cpu:
            let important = changes(for: .cpu, guide: guide).filter { !["phase", "nextPhase", "cycleCount"].contains($0.field) }
                + changes(for: .assembly, guide: guide).filter { ["fetchedBytes", "decodedInstruction"].contains($0.field) }
            if important.isEmpty {
                fact("Program counter", "0x\(ToyInk.hex(before.pc)) → 0x\(ToyInk.hex(after.pc))")
                fact("Decoder", after.currentInstruction?.description ?? "Empty")
            } else {
                changeRows(important, empty: "No CPU value change.")
            }
        case .registers:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(0..<4, id: \.self) { register in
                    registerTile(register, guide: guide, before: before, after: after)
                }
            }
        case .memory:
            Text(memoryWriteSummary(guide))
                .font(.system(.caption, design: .monospaced)).monospacedDigit()
                .foregroundStyle(guide.latestStep?.highlights.writtenMemory.isEmpty == false ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guidedMemoryWrite")
            Text(memoryReadSummary(guide))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(InstrumentPalette.actionCyan)
                .fixedSize(horizontal: false, vertical: true)
            Text("Device ports are separate from RAM. Display pixels occupy 0xC0…0xFF.")
                .font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
        case .os:
            Text("Privilege: \(before.privilege.title) → \(after.privilege.title)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(before.privilege == after.privilege ? InstrumentPalette.displayInk : InstrumentPalette.spectrum)
                .accessibilityIdentifier("guidedPrivilege")
            let call = guide.latestStep?.capturedSystemCall ?? after.syscall
            Text(call.map { "Captured arguments: " + $0.arguments.enumerated().map { "R\($0.offset)=\($0.element)" }.joined(separator: ", ") } ?? "Captured arguments: None")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(InstrumentPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guidedCapturedArguments")
            changeRows(changes(for: .os, guide: guide).filter { !["privilege", "arguments"].contains($0.field) }, empty: "OS state unchanged in this microcycle.")
        }
    }

    @ViewBuilder private func completeFacts(_ layer: GuidedLayer, guide: GuidedInstruction) -> some View {
        let before = guide.latestStep?.before ?? guide.baseline
        let after = guide.currentMachine
        switch layer {
        case .assembly:
            fact("Execution bytes", byteString(guide.executionBytes))
            fact("RAM at guide start", byteString(guide.ramBytes))
            Text(guide.sourceRow == nil
                 ? "No assembled source row exists to compare with these execution bytes."
                 : guide.sourceMatchesExecution
                    ? "The execution bytes match the assembled source."
                    : "The execution bytes differ from the assembled source. The CPU follows its fetched bytes.")
                .font(.caption).foregroundStyle(guide.sourceRow != nil && !guide.sourceMatchesExecution ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
            if guide.executionBytes != guide.ramBytes {
                Text("RAM changed after fetch. This instruction uses its latched bytes; a later fetch sees the RAM edit.")
                    .font(.caption).foregroundStyle(InstrumentPalette.actionAmber)
            }
        case .cpu:
            fact("Program counter", "0x\(ToyInk.hex(before.pc)) → 0x\(ToyInk.hex(after.pc))")
            fact("Instruction latch", "\(byteString(before.fetchedBytes)) → \(byteString(after.fetchedBytes))")
            fact("Decoder", "\(before.currentInstruction?.description ?? "Empty") → \(after.currentInstruction?.description ?? "Empty")")
            fact("Next phase", after.nextPhase.title)
            if let alu = after.lastALU {
                fact("ALU", "\(alu.left) \(alu.operation) \(alu.right) → \(alu.result)")
            }
            changeRows(changes(for: .cpu, guide: guide), empty: "No CPU reads, writes or changes yet.")
        case .registers:
            fact("Zero flag", "\(before.zeroFlag ? 1 : 0) → \(after.zeroFlag ? 1 : 0)")
            fact("Carry flag", "\(before.carryFlag ? 1 : 0) → \(after.carryFlag ? 1 : 0)")
            fact("Stack pointer", "\(before.stackPointer) → \(after.stackPointer)")
            Text("Register values are decimal bytes, 0…255. Flags remain unchanged unless this instruction updates them.")
                .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            changeRows(changes(for: .registers, guide: guide), empty: "No register reads or writes yet.")
        case .memory:
            changeRows(changes(for: .memory, guide: guide), empty: "No RAM reads, writes or value changes recorded.")
        case .os:
            let call = guide.latestStep?.capturedSystemCall ?? after.syscall
            fact("Service", call.map { "SYS \($0.service) · \($0.name)" } ?? "None")
            fact("System-call state", after.syscall == nil ? "No pending call" : "Call pending")
            if let bus = guide.latestStep?.event.bus {
                fact("Bus event", "\(bus.kind.title): \(bus.description)")
            } else {
                Text("No device or system-call bus event in this microcycle.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            }
            fact("Console", after.console.isEmpty ? "Empty" : after.console)
            fact("Console bytes emitted / discarded", "\(after.consoleByteCount) / \(after.droppedConsoleByteCount)")
            fact("Input switch", String(after.inputValue))
            changeRows(changes(for: .os, guide: guide), empty: "No OS reads, writes or value changes recorded.")
        }
    }

    private func registerTile(_ register: Int, guide: GuidedInstruction, before: Machine, after: Machine) -> some View {
        let status = registerStatus(register, guide: guide)
        let read = guide.latestStep?.highlights.readRegisters.contains(register) == true
        let written = guide.latestStep?.highlights.writtenRegisters.contains(register) == true
        let changed = guide.latestStep?.highlights.changedRegisters.contains(register) == true
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("R\(register)").foregroundStyle(InstrumentPalette.secondaryInk)
                Spacer(minLength: 4)
                if read { accessBadge("Read", color: InstrumentPalette.actionCyan) }
                if written { accessBadge("Written", color: InstrumentPalette.actionAmber) }
                if changed { accessBadge("Changed", color: InstrumentPalette.actionAmber) }
            }
            .font(.system(.caption2, design: .monospaced))
            Text("R\(register): \(before.registers[register]) → \(after.registers[register]) · \(status)")
                .font(.system(.caption, design: .monospaced)).monospacedDigit()
                .foregroundStyle(status == "Unchanged" ? InstrumentPalette.displayInk : InstrumentPalette.actionAmber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guidedR\(register)")
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(8)
        .background(.black.opacity(0.2), in: .rect(cornerRadius: 10))
    }

    private func changeRows(_ records: [GuidedValueChange], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if records.isEmpty {
                Text(empty).font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            } else {
                ForEach(records) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(change.title)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(InstrumentPalette.displayInk)
                            Spacer(minLength: 4)
                            accessBadge(change.access.title, color: change.access == .read ? InstrumentPalette.actionCyan : InstrumentPalette.actionAmber)
                            if change.didChange && change.access != .changed {
                                accessBadge("Changed", color: InstrumentPalette.actionAmber)
                            } else if !change.didChange && change.access == .write {
                                accessBadge("Same value", color: InstrumentPalette.secondaryInk)
                            }
                        }
                        Text("\(change.before) → \(change.after)")
                            .font(.system(.caption, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(InstrumentPalette.displayInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func accessBadge(_ title: String, color: Color) -> some View {
        Text(title).font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(color.opacity(0.09), in: .rect(cornerRadius: 4))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func compactPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InstrumentPalette.content, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(contrast == .increased ? 0.24 : 0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    private var controls: some View {
        let guide = session.guidedInstruction
        let complete = guide?.isComplete == true
        let fault = guide?.currentMachine.fault ?? session.machine.fault
        return VStack(alignment: .leading, spacing: 8) {
            if let fault {
                Text("Fault: \(fault)")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.actionAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("guidePinnedFault")
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { session.previousGuidedStep() } label: {
                        if typeSize.isAccessibilitySize {
                            Image(systemName: "chevron.left")
                                .frame(minWidth: 64, minHeight: 44)
                        } else {
                            Label("Back", systemImage: "chevron.left")
                                .frame(minWidth: 64, minHeight: 44)
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(guide?.canPrevious != true)
                    .accessibilityLabel("Back")
                    .accessibilityHint("Restores the exact machine state before this microcycle")
                    .accessibilityIdentifier("guidePrevious")
                    Button { session.restartGuidedInstruction() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(guide?.canPrevious != true)
                    .accessibilityLabel("Restart instruction")
                    .accessibilityHint("Restores this instruction's exact entry state")
                    .accessibilityIdentifier("guideRestart")
                    Button {
                        if complete { session.startGuidedInstruction() }
                        else { session.advanceGuidedInstruction() }
                    } label: {
                        if typeSize.isAccessibilitySize {
                            Image(systemName: complete ? "arrow.right.to.line" : "chevron.right")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Label(complete ? "Next instruction" : guide.map { "Next: \($0.currentMachine.nextPhase.title)" } ?? "Next",
                                  systemImage: complete ? "arrow.right.to.line" : "chevron.right")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(.glassProminent).tint(InstrumentPalette.actionCyan)
                    .disabled(complete ? guide?.currentMachine.isFinished != false : guide?.canAdvance != true)
                    .accessibilityLabel(complete ? "Next instruction" : guide.map { "Next: \($0.currentMachine.nextPhase.title)" } ?? "Next")
                    .accessibilityHint(complete ? "Starts a separate walkthrough at the next instruction" : "Performs exactly one microcycle")
                    .accessibilityIdentifier(complete ? "guideNextInstruction" : "guideNext")
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: 600)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(InstrumentPalette.canvas)
    }

    private var stoppedPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(session.machine.isFinished ? "Program has stopped" : "Guide ended",
                      systemImage: session.machine.fault == nil ? "pause.circle" : "exclamationmark.triangle")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(InstrumentPalette.displayInk)
                Text(session.machine.panic.map { "Kernel panic: \($0.reason)" } ?? session.machine.fault.map { "Fault: \($0)" }
                     ?? (session.machine.halted ? "The program has halted." : "The machine is paused at its current state."))
                    .font(.subheadline).foregroundStyle(InstrumentPalette.secondaryInk)
                Text("Reset to the loaded program’s first instruction, or tap Done to keep this state and return to the workbench.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                Button {
                    session.reset()
                    session.startGuidedInstruction()
                } label: {
                    Label("Reset & guide first instruction", systemImage: "arrow.counterclockwise")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent).tint(InstrumentPalette.actionCyan)
                .accessibilityIdentifier("guideResetAndStart")
            }
        }
    }

    private func upcomingPhase(_ guide: GuidedInstruction) -> String {
        if guide.currentMachine.isFinished { return "Next: program stopped" }
        if guide.isComplete { return "Next: instruction complete" }
        return "Next: \(guide.currentMachine.nextPhase.title)"
    }

    private func phaseState(_ phase: MicroPhase, guide: GuidedInstruction) -> String {
        if guide.latestStep?.executedPhase == phase { return "just completed" }
        if guide.steps.contains(where: { $0.executedPhase == phase }) { return "completed" }
        if guide.canAdvance && guide.currentMachine.nextPhase == phase { return "next" }
        return "ahead"
    }

    private func phaseSymbol(_ phase: MicroPhase, guide: GuidedInstruction) -> String {
        switch phaseState(phase, guide: guide) {
        case "just completed", "completed": "checkmark.circle.fill"
        case "next": "arrow.right.circle"
        default: "circle"
        }
    }

    private func phaseAccent(_ phase: MicroPhase, guide: GuidedInstruction) -> Color {
        switch phaseState(phase, guide: guide) {
        case "just completed": InstrumentPalette.actionAmber
        case "completed", "next": InstrumentPalette.actionCyan
        default: InstrumentPalette.secondaryInk
        }
    }

    private func changes(for layer: GuidedLayer, guide: GuidedInstruction) -> [GuidedValueChange] {
        guide.latestStep?.changes.filter { $0.layer == layer } ?? []
    }

    private func layerAccess(_ layer: GuidedLayer, guide: GuidedInstruction) -> String {
        guard let step = guide.latestStep else { return "Ready" }
        let records = changes(for: layer, guide: guide)
        let read: Bool = layer == .registers ? !step.highlights.readRegisters.isEmpty : records.contains { $0.access == .read }
        let written: Bool = layer == .registers ? !step.highlights.writtenRegisters.isEmpty : records.contains { $0.access == .write }
        if read && written { return "Read / Write" }
        if written { return "Written" }
        if read { return "Read" }
        return "No access"
    }

    private func layerHasChanges(_ layer: GuidedLayer, guide: GuidedInstruction) -> Bool {
        changes(for: layer, guide: guide).contains(where: \.didChange)
    }

    private func layerDelta(_ layer: GuidedLayer, guide: GuidedInstruction) -> String {
        guide.latestStep == nil ? "Baseline" : layerHasChanges(layer, guide: guide) ? "Changed" : "Unchanged"
    }

    private func layerAccessAccent(_ layer: GuidedLayer, guide: GuidedInstruction) -> Color {
        let access = layerAccess(layer, guide: guide)
        if access.contains("Write") || access == "Written" { return InstrumentPalette.actionAmber }
        return access == "Read" ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk
    }

    private func detailsBinding(_ layer: GuidedLayer) -> Binding<Bool> {
        Binding(get: { expandedLayers.contains(layer) }, set: { expanded in
            if expanded { expandedLayers.insert(layer) } else { expandedLayers.remove(layer) }
        })
    }

    private func plannedPhases(_ guide: GuidedInstruction) -> [MicroPhase] {
        guard !guide.baseline.isFinished else { return [] }
        let all: [MicroPhase] = guide.instruction?.opcode == .sys
            ? [.fetch, .decode, .execute, .trap, .kernel, .driver, .returnToUser]
            : [.fetch, .decode, .execute]
        if let first = all.firstIndex(of: guide.baseline.nextPhase) { return Array(all[first...]) }
        return [guide.baseline.nextPhase]
    }

    private func narration(_ guide: GuidedInstruction) -> String {
        if let step = guide.latestStep { return step.explanation }
        if let panic = guide.currentMachine.panic { return "This machine has panicked: \(panic.reason). Reset reboots it." }
        if let fault = guide.currentMachine.fault { return "This machine is already stopped by a fault: \(fault)" }
        if guide.currentMachine.halted { return "The machine is already halted. Close the guide to reset or edit the program." }
        return "The machine is paused at \(guide.baseline.nextPhase.title). \(guide.baseline.nextPhase.explanation) Inspect the entry values below, then tap Next."
    }

    private func completionStatus(_ guide: GuidedInstruction) -> String {
        if guide.currentMachine.fault != nil { return "Stopped by a fault · Back or Restart to inspect the cause" }
        if guide.currentMachine.halted { return "Machine halted · Back or Restart remains available" }
        if guide.isComplete { return "Instruction complete · choose Next instruction when ready" }
        return "Paused · Next performs exactly one microcycle"
    }

    private func registerStatus(_ register: Int, guide: GuidedInstruction) -> String {
        guard let highlights = guide.latestStep?.highlights else { return "Unchanged" }
        if highlights.changedRegisters.contains(register) { return "Changed" }
        if highlights.writtenRegisters.contains(register) { return "Written · same value" }
        if highlights.readRegisters.contains(register) { return "Read" }
        return "Unchanged"
    }

    private func memoryWriteSummary(_ guide: GuidedInstruction) -> String {
        guard let step = guide.latestStep, !step.highlights.writtenMemory.isEmpty else { return "RAM writes: None" }
        return step.highlights.writtenMemory.sorted().map { address in
            "0x\(ToyInk.hex(address)): \(step.before.memory[address]) → \(step.after.memory[address])"
        }.joined(separator: "; ")
    }

    private func memoryReadSummary(_ guide: GuidedInstruction) -> String {
        guard let step = guide.latestStep, !step.highlights.readMemory.isEmpty else { return "RAM reads: None" }
        return "RAM reads: " + step.highlights.readMemory.sorted().map { address in
            "0x\(ToyInk.hex(address)) = \(step.before.memory[address])"
        }.joined(separator: ", ")
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(InstrumentPalette.secondaryInk)
            Text(value).font(.system(.caption, design: .monospaced)).monospacedDigit()
                .foregroundStyle(InstrumentPalette.displayInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func byteString(_ bytes: [UInt8]) -> String {
        bytes.isEmpty ? "Empty" : bytes.map { "0x\(ToyInk.hex(Int($0)))" }.joined(separator: " ")
    }

    private func layerSymbol(_ layer: GuidedLayer) -> String {
        switch layer {
        case .assembly: "curlybraces"
        case .cpu: "cpu"
        case .registers: "square.grid.2x2"
        case .memory: "memorychip"
        case .os: "shield.lefthalf.filled"
        }
    }

    private func layerIdentifier(_ layer: GuidedLayer) -> String {
        switch layer {
        case .assembly: "guidedAssemblyLayer"
        case .cpu: "guidedCPULayer"
        case .registers: "guidedRegistersLayer"
        case .memory: "guidedMemoryLayer"
        case .os: "guidedOSLayer"
        }
    }
}
