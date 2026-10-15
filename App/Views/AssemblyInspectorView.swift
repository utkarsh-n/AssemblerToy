import SwiftUI
import AssemblerCore

struct AssemblyInspectorView: View {
    let session: MachineSession
    let edit: () -> Void
    var inspectBytes: (Int) -> Void = { _ in }
    var body: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeading(title: "Source → machine code", detail: "AT–8")
                    Button("Edit", action: { session.running = false; edit() })
                        .frame(minHeight: 44).buttonStyle(.glass)
                        .accessibilityIdentifier("editAssemblySource")
                }
                Text("One instruction → four bytes. Inspect bytes opens the exact address in Memory.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                ForEach(session.program.instructions) { row in instructionRow(row) }
                if session.program.dataBytes.contains(where: { $0 != 0 }) {
                    Text("The loader also copies the .byte section into 0x80–0xBF. Inspect it in Memory.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
                DisclosureGroup("Encoding & breakpoints") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Opcode chooses the operation. A and B hold its register indexes, byte values or addresses. Reserved must be zero.")
                        Text("The circle beside an instruction stops Run before its Fetch. Filled means the breakpoint is enabled.")
                        Text("The CPU executes RAM bytes. Patching Memory changes execution; source remains a record of what you assembled.")
                    }.font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                        .padding(.top, 8)
                }.font(.subheadline).tint(InstrumentPalette.actionCyan)
            }
        }
    }

    private func instructionRow(_ row: InstructionRow) -> some View {
        let bytes = Array(session.machine.memory[row.address..<(row.address + 4)])
        let patched = bytes != row.bytes
        let current = session.machine.currentInstructionAddress == row.address
        let upcoming = session.machine.nextPhase == .fetch && session.machine.pc == row.address && !session.machine.isFinished
        return HStack(alignment: .top, spacing: 8) {
            Button {
                if session.breakpoints.contains(row.address) { session.breakpoints.remove(row.address) }
                else { session.breakpoints.insert(row.address) }
            } label: {
                Image(systemName: session.breakpoints.contains(row.address) ? "circle.inset.filled" : "circle")
                    .foregroundStyle(session.breakpoints.contains(row.address) ? ToyInk.pixels[5] : InstrumentPalette.secondaryInk.opacity(0.5))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Breakpoint at address \(row.address)")
                .accessibilityValue(session.breakpoints.contains(row.address) ? "Enabled" : "Disabled")
                .accessibilityHint("Stops Run before fetching this instruction.")
            VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("0x\(ToyInk.hex(row.address))  \(row.instruction.description)")
                            .font(.system(.subheadline, design: .monospaced, weight: .medium))
                            .foregroundStyle(current ? InstrumentPalette.actionAmber : InstrumentPalette.displayInk)
                        Spacer(minLength: 4)
                        if upcoming { Text("Next").font(.caption2).foregroundStyle(InstrumentPalette.actionCyan) }
                        else if current { Text("Latched").font(.caption2).foregroundStyle(InstrumentPalette.actionAmber) }
                    }
                    NamedInstructionBytesView(bytes: bytes, identifier: "instructionBytes.\(row.address)")
                    HStack {
                        Button {
                            session.selectedAddress = row.address
                            inspectBytes(row.address)
                        } label: {
                            Label("Inspect bytes", systemImage: "arrow.right.circle")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .frame(minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(InstrumentPalette.actionCyan)
                            .accessibilityIdentifier("inspectInstruction.\(row.address)")
                            .accessibilityHint("Opens Memory at 0x\(ToyInk.hex(row.address)).")
                        Spacer(minLength: 2)
                        if patched {
                            Label("Patched", systemImage: "pencil.tip")
                                .font(.caption2).foregroundStyle(InstrumentPalette.actionAmber)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(8)
            .background(.black.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

struct SourceEditorView: View {
    let session: MachineSession
    @State private var draft: String
    @State private var mode: ExecutionMode
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: MachineSession) {
        self.session = session
        _draft = State(initialValue: session.source)
        _mode = State(initialValue: session.machine.mode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentDesignBackground()
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Privilege", selection: $mode) {
                        ForEach(ExecutionMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Calibration("ASSEMBLE → LOAD → FETCH → EXECUTE")
                    TextEditor(text: $draft).font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8).background(InstrumentPalette.content, in: .rect(cornerRadius: 14))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityLabel("Assembly source editor")
                    if let error {
                        ScrollView { Text(error).font(.system(.caption, design: .monospaced)).foregroundStyle(ToyInk.pixels[5]).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140)
                    }
                    Text("R0–R3 · decimal / 0x hex / 0b binary · labels: · ; comments\nData: .org 128 followed by .byte values. Up to 32 instructions.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    Button {
                        do {
                            try session.assemble(draft, mode: mode)
                            session.title = "Your program"
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    } label: { Label("Assemble & load", systemImage: "shippingbox").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.glassProminent)
                }.padding(16)
            }.navigationTitle("Assembly editor").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct ExampleLibraryView: View {
    let session: MachineSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SheetShell(title: "Program library") {
            VStack(spacing: 14) {
                Text("Load a working experiment, then run it or step through the mechanism.")
                    .font(.subheadline).foregroundStyle(InstrumentPalette.secondaryInk)
                ForEach(ExampleCatalog.examples) { example in
                    InstrumentContentPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Calibration(example.mode.title.uppercased(), color: example.mode == .user ? InstrumentPalette.spectrum : InstrumentPalette.actionCyan)
                            Text(example.name).font(.system(.title3, design: .rounded, weight: .semibold))
                            Text(example.summary).font(.subheadline)
                            ForEach(example.goals, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(InstrumentPalette.secondaryInk) }
                            Button("Load experiment") { session.load(example); dismiss() }.buttonStyle(.glass)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
