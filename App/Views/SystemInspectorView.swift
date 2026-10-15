import SwiftUI
import AssemblerCore

struct SystemInspectorView: View {
    let session: MachineSession
    @ScaledMetric(relativeTo: .caption) private var retentionNoticeHeight = 44.0
    @ScaledMetric(relativeTo: .body) private var consoleHeight = 170.0
    @ScaledMetric(relativeTo: .caption) private var traceHeight = 340.0
    @ScaledMetric(relativeTo: .caption) private var traceRowHeight = 64.0
    @ScaledMetric(relativeTo: .caption2) private var traceHeaderHeight = 22.0
    @ScaledMetric(relativeTo: .caption2) private var tracePhaseWidth = 96.0
    @ScaledMetric(relativeTo: .caption) private var traceMessageHeight = 24.0

    var body: some View {
        VStack(spacing: 14) {
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Privilege boundary", detail: "3 ROLES")
                    ZStack(alignment: .topLeading) {
                        Calibration("CURRENT: BARE METAL").hidden().accessibilityHidden(true)
                        Calibration("CURRENT: \(session.machine.privilege.title.uppercased())", color: InstrumentPalette.actionAmber)
                    }
                    Picker("Execution environment", selection: Binding(get: { session.machine.mode }, set: { session.changeMode($0) })) {
                        ForEach(ExecutionMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(session.machine.mode == .bareMetal ? "Your code writes device memory directly and reads the input port with IN. It owns the whole machine." : "Your code runs as a user process. Direct device access faults. SYS crosses into a trusted kernel, whose driver writes the same physical display.")
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        boundaryNode("USER", active: session.machine.privilege == .user, color: InstrumentPalette.actionCyan)
                        Image(systemName: "arrow.right").font(.caption)
                        boundaryNode("KERNEL", active: session.machine.privilege == .kernel, color: InstrumentPalette.spectrum)
                        Image(systemName: "arrow.right").font(.caption)
                        boundaryNode("DEVICE", active: session.machine.phase == .driver, color: InstrumentPalette.actionAmber)
                    }
                    Text("Changing environment reloads the same program. Try running a direct ST to 0xC0 in User + OS, then rewind and replace it with SYS 1.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
            }
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "System-call table", detail: "SYS n")
                    service(1, "Draw pixel", "R0 = pixel index 0…63; R1 = color 0…7")
                    service(2, "Fill display", "R0 = color 0…7")
                    service(3, "Read input", "R0 ← hardware button value")
                    service(4, "Write console", "R0 = printable ASCII or newline")
                    service(5, "Read clock", "R0 ← modeled cycle count modulo 256")
                    service(6, "Exit process", "Halt the user program")
                    service(7, "Draw pixel (unchecked)", "Like SYS 1, but the index check is deliberately missing")
                    service(8, "Watchdog check-in", "Enables monitoring; then check in every \(Machine.watchdogTimeout) cycles")
                    Text("Services are modeled Swift kernel handlers. They preserve condition flags, so driver calls can appear inside loops. SYS 7 and SYS 8 exist to show how a whole machine can panic.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
            }
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "Watchdog", detail: session.machine.watchdogDeadline == nil ? "OFF" : "ARMED")
                    Text(watchdogStatus).font(.system(.caption, design: .monospaced)).monospacedDigit()
                    Text("A watchdog stops a machine that stops responding. Monitoring starts at the first SYS 8; from then on a check-in must arrive within \(Machine.watchdogTimeout) microcycles or the machine panics.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
            }.accessibilityIdentifier("systemWatchdogPanel")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Console device", detail: "PORT 1")
                    ScrollView(.vertical) {
                        Text(consoleRetentionNotice).font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(height: retentionNoticeHeight, alignment: .top)
                    ScrollView(.vertical) {
                        Text(session.machine.console.isEmpty ? "Waiting for OUT or SYS 4…" : session.machine.console)
                            .font(.system(.body, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    }.frame(height: consoleHeight, alignment: .top)
                        .background(.black.opacity(0.3), in: .rect(cornerRadius: 12))
                        .accessibilityIdentifier("consoleViewport")
                }
            }.accessibilityIdentifier("systemConsolePanel")
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Execution trace", detail: "LATEST 24 EVENTS")
                    Text("Newest first. Swipe within a message to read the complete event.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    traceViewport
                }
            }.accessibilityIdentifier("systemTracePanel")
        }
    }

    private var watchdogStatus: String {
        let machine = session.machine
        if machine.panic?.kind == .watchdogTimeout { return "Timed out after \(machine.watchdogCheckIns) check-ins" }
        guard let deadline = machine.watchdogDeadline else { return "Not monitoring · no check-ins yet" }
        let left = deadline >= machine.cycleCount ? deadline - machine.cycleCount : 0
        return "\(machine.watchdogCheckIns) check-ins · next due within \(left) cycles"
    }

    private var consoleRetentionNotice: String {
        if session.machine.droppedConsoleByteCount > 0 {
            return "Showing the latest \(Machine.consoleCapacity) bytes · \(session.machine.droppedConsoleByteCount) earlier bytes omitted"
        }
        return "Console capacity: \(Machine.consoleCapacity) bytes. New output appears here."
    }

    private var traceViewport: some View {
        let events = Array(session.machine.trace.suffix(24).reversed())
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 6) {
                // Position identities keep the lanes and user scroll offset
                // stable as the latest modeled events replace their contents.
                ForEach(0..<24, id: \.self) { position in
                    traceSlot(events.indices.contains(position) ? events[position] : nil,
                              first: position == 0)
                }
            }
        }.frame(height: traceHeight, alignment: .top)
            .accessibilityIdentifier("executionTraceViewport")
    }

    private func traceSlot(_ event: TraceEvent?, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    Calibration(event?.phase.title.uppercased() ?? "NO EVENT",
                                color: event?.privilege == .kernel ? InstrumentPalette.spectrum : InstrumentPalette.actionAmber)
                        .frame(width: tracePhaseWidth, alignment: .leading)
                    Text(event.map { "\($0.id) cycles" } ?? "Waiting")
                    .font(.system(.caption2, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                }.fixedSize(horizontal: true, vertical: true)
            }.frame(height: traceHeaderHeight, alignment: .top)
            ScrollView(.horizontal) {
                Text(event?.message ?? "Step or run to trace cause and effect.")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.displayInk)
                    .fixedSize(horizontal: true, vertical: true)
            }.frame(height: traceMessageHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: traceRowHeight, alignment: .top)
        .opacity(event != nil || first ? 1 : 0)
        .accessibilityHidden(event == nil && !first)
    }

    private func boundaryNode(_ title: String, active: Bool, color: Color) -> some View {
        Calibration(title, color: active ? color : InstrumentPalette.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.black.opacity(0.15), in: .rect(cornerRadius: 10))
    }

    private func service(_ number: Int, _ title: String, _ contract: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(.title3, design: .monospaced)).foregroundStyle(InstrumentPalette.spectrum).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(contract).font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
            }
        }
    }
}
