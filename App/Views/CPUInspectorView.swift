import SwiftUI
import AssemblerCore

struct CPUInspectorView: View {
    let session: MachineSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var busDescriptionHeight = 44.0
    @ScaledMetric(relativeTo: .title3) private var equationHeight = 38.0
    @ScaledMetric(relativeTo: .caption2) private var evidenceHeight = 30.0

    var body: some View {
        VStack(spacing: 14) {
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Execution path", detail: "ONE CLOCK AT A TIME")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([MicroPhase.fetch, .decode, .execute, .trap, .kernel, .driver, .returnToUser]) { phase in
                                VStack(spacing: 7) {
                                    Image(systemName: phaseSymbol(phase)).font(.title3)
                                    Text(phase.title).font(.system(.caption2, design: .monospaced))
                                }
                                .foregroundStyle(session.machine.nextPhase == phase ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
                                .frame(width: 66, height: 62)
                                .background(.black.opacity(0.16), in: .rect(cornerRadius: 12))
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        phaseReading("LAST COMPLETED", value: session.lastExecutionStep?.event.phase.title
                                     ?? session.machine.trace.last?.phase.title ?? "None")
                        Spacer(minLength: 4)
                        phaseReading("NEXT PHASE", value: session.machine.nextPhase.title,
                                     color: InstrumentPalette.actionAmber)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ExecutionTransferView(cue: ExecutionCue(machine: session.machine, step: session.lastExecutionStep))
                    }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("cpuLastEventViewport")
                    Text("Fetch → Decode → Execute. SYS continues through Trap → Kernel → Driver → Return.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    busReadout
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("cpuExecutionPanel")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Register file", detail: "4 × 8 BITS")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                             count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 6) {
                        ForEach(0..<4, id: \.self) { r in
                            Button { session.selectedRegister = r } label: {
                                VStack(spacing: 6) {
                                    Calibration("R\(r)")
                                    Text("\(session.machine.registers[r])").font(.system(.title2, design: .rounded, weight: .light)).monospacedDigit()
                                        .foregroundStyle(InstrumentPalette.displayInk)
                                        .fixedSize(horizontal: true, vertical: true)
                                    Text(ToyInk.hex(Int(session.machine.registers[r]))).font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(InstrumentPalette.actionCyan)
                                    registerEvidence(r)
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(session.selectedRegister == r ? InstrumentPalette.actionCyan.opacity(0.10) : .black.opacity(0.15), in: .rect(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("Register \(r)")
                                .accessibilityValue("\(session.machine.registers[r]), hex \(ToyInk.hex(Int(session.machine.registers[r])))")
                                .accessibilityHint(registerEvidenceLabel(r))
                        }
                    }
                    ByteBits(value: session.machine.registers[session.selectedRegister]) { bit in
                        let r = session.selectedRegister
                        session.writeRegister(r, value: session.machine.registers[r] ^ (1 << bit))
                    }
                    InstrumentParameterStepper("R\(session.selectedRegister)", value: Binding(get: { Int(session.machine.registers[session.selectedRegister]) }, set: { session.writeRegister(session.selectedRegister, value: UInt8($0)) }), in: 0...255, unit: "DEC")
                    HStack {
                        flag("ZERO", set: session.machine.zeroFlag)
                        flag("CARRY", set: session.machine.carryFlag)
                        Spacer()
                        Calibration("SP \(session.machine.stackPointer)")
                    }
                    Text("Flip a bit or change a register. The next instruction uses your edited value; arithmetic updates the flags.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    Text("Read = used · Written = stored · Δ = value changed in the last phase")
                        .font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("cpuRegisterPanel")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Last ALU operation", detail: "8-BIT RESULT")
                    ScrollView(.horizontal) {
                        Text(aluEquation)
                            .font(.system(.title3, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan)
                            .monospacedDigit().fixedSize(horizontal: true, vertical: true)
                    }.frame(height: equationHeight, alignment: .top)
                    Text("Result is an 8-bit byte. Addition wraps modulo 256; subtraction carry means borrow.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("cpuALUPanel")
        }
    }

    private var aluEquation: String {
        guard let alu = session.machine.lastALU else { return "No arithmetic has executed." }
        return "\(alu.left)  \(alu.operation)  \(alu.right)  →  \(alu.result)"
    }

    private var busReadout: some View {
        let bus = session.machine.bus
        let isolatedPort = bus.map {
            ($0.kind == .deviceRead || $0.kind == .deviceWrite)
                && $0.address.map { $0 < MemoryMap.framebuffer.lowerBound } == true
        } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Label("Instruction fetch", systemImage: "arrow.left.arrow.right").hidden().accessibilityHidden(true)
                Label(bus?.kind.title ?? "Bus idle", systemImage: "arrow.left.arrow.right")
            }
            .font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.actionAmber)
            HStack {
                ZStack(alignment: .leading) {
                    Calibration("ADDRESS").hidden().accessibilityHidden(true)
                    Calibration(isolatedPort ? "PORT" : "ADDRESS")
                }
                valueSlot(bus?.address.map { isolatedPort ? String($0) : "0x\(ToyInk.hex($0))" } ?? "—", reserving: "0xFF")
                Spacer(minLength: 8)
                Calibration("BYTE")
                valueSlot(bus?.value.map { "\($0)" } ?? "—", reserving: "255")
            }
            .font(.system(.caption, design: .monospaced)).monospacedDigit()
            .foregroundStyle(InstrumentPalette.actionAmber)
            messageViewport(bus?.description ?? "No bus transfer in this microcycle.",
                            height: busDescriptionHeight, color: InstrumentPalette.secondaryInk)
        }.accessibilityIdentifier("cpuBusReadout")
    }

    private func valueSlot(_ value: String, reserving maximum: String) -> some View {
        ZStack(alignment: .leading) {
            Text(maximum).hidden().accessibilityHidden(true)
            Text(value)
        }.fixedSize(horizontal: true, vertical: true)
    }

    private func messageViewport(_ message: String, height: CGFloat, color: Color) -> some View {
        ScrollView(.vertical) {
            Text(message).font(.system(.caption, design: .monospaced)).foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(height: height, alignment: .top)
    }

    private func flag(_ name: String, set: Bool) -> some View {
        Calibration("\(name) \(set ? "1" : "0")", color: set ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
    }

    private func phaseReading(_ label: String, value: String,
                              color: Color = InstrumentPalette.actionCyan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Calibration(label)
            Text(value).font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
                .frame(minWidth: 90, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func registerEvidence(_ register: Int) -> some View {
        let highlights = session.lastExecutionStep?.highlights
        let read = highlights?.readRegisters.contains(register) == true
        let written = highlights?.writtenRegisters.contains(register) == true
        let changed = highlights?.changedRegisters.contains(register) == true
        return VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text("Read").foregroundStyle(InstrumentPalette.actionCyan).opacity(read ? 1 : 0.2)
                Text("Written").foregroundStyle(InstrumentPalette.actionAmber).opacity(written ? 1 : 0.2)
            }
            Text(changed ? "Δ Changed" : "Unchanged")
                .foregroundStyle(changed ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
        }
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(height: evidenceHeight)
        .accessibilityHidden(true)
    }

    private func registerEvidenceLabel(_ register: Int) -> String {
        guard let highlights = session.lastExecutionStep?.highlights else { return "Select to edit this register" }
        let access = [highlights.readRegisters.contains(register) ? "Read" : nil,
                      highlights.writtenRegisters.contains(register) ? "Written" : nil]
            .compactMap { $0 }.joined(separator: " and ")
        return "\(access.isEmpty ? "Not accessed" : access) in the last phase. \(highlights.changedRegisters.contains(register) ? "Value changed." : "Value unchanged.") Select to edit."
    }

    private func phaseSymbol(_ phase: MicroPhase) -> String {
        switch phase {
        case .fetch: "memorychip"
        case .decode: "barcode"
        case .execute: "cpu"
        case .trap: "arrow.up.right"
        case .kernel: "shield.lefthalf.filled"
        case .driver: "display"
        default: "arrow.turn.down.left"
        }
    }
}
