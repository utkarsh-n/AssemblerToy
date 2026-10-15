import SwiftUI
import AssemblerCore

struct MemoryInspectorView: View {
    let session: MachineSession
    @State private var bank = 3
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var addressDetailHeight = 52.0
    private let names = ["Code A", "Code B", "Data", "Display"]

    var body: some View {
        VStack(spacing: 14) {
            regionMap
            byteInspector
            InstrumentContentPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Physical memory", detail: "256 BYTES")
                    Picker("Memory bank", selection: $bank) {
                        ForEach(0..<4, id: \.self) { Text(names[$0]).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(bank < 2 ? "Instructions occupy four adjacent bytes. Amber marks the fetched instruction." : bank == 2 ? "Data and the descending stack share this region. Your program owns their layout." : "One byte per pixel. The low three bits select one of eight colors.")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                        ForEach((bank * 64)..<((bank + 1) * 64), id: \.self) { address in
                            memoryCell(address)
                        }
                    }
                }
            }
        }
        .onChange(of: session.selectedAddress) { _, address in bank = address / 64 }
        .onChange(of: bank) { _, bank in
            if session.selectedAddress / 64 != bank { session.selectedAddress = bank * 64 }
        }
        .onAppear { bank = session.selectedAddress / 64 }
    }

    private var regionMap: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Memory map").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer()
                    Text("256 bytes").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                }
                HStack(spacing: 5) {
                    regionButton("Code", range: "00–7F", start: 0, end: 128)
                    regionButton("Data & stack", range: "80–BF", start: 128, end: 192)
                    regionButton("Display", range: "C0–FF", start: 192, end: 256)
                }
                HStack(spacing: 8) {
                    Label("Selected", systemImage: "scope").foregroundStyle(InstrumentPalette.actionCyan)
                    Label("Latched", systemImage: "cpu").foregroundStyle(InstrumentPalette.actionAmber)
                    Spacer(minLength: 0)
                    Text("SP 0x\(ToyInk.hex(session.machine.stackPointer))")
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                }.font(.system(.caption2, design: .monospaced))
            }
        }
    }

    private func regionButton(_ title: String, range: String, start: Int, end: Int) -> some View {
        let selected = (start..<end).contains(session.selectedAddress)
        return Button {
            if !selected { session.selectedAddress = start }
        } label: {
            VStack(spacing: 4) {
                Text(title).font(.system(.caption, design: .rounded, weight: .medium))
                Text("0x\(range)").font(.system(.caption2, design: .monospaced))
            }.frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                .background(selected ? InstrumentPalette.actionCyan.opacity(0.10) : .black.opacity(0.15), in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(selected ? InstrumentPalette.actionCyan : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel("\(title), addresses 0x\(range)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var byteInspector: some View {
        let address = session.selectedAddress
        let value = session.machine.memory[address]
        return InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Byte probe", detail: "SELECT & EDIT")
                Text("0x\(ToyInk.hex(address)) · \(address < 128 ? "Code" : address < 192 ? "Data & stack" : "Display")")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan)
                    .accessibilityIdentifier("selectedMemoryAddress")
                HStack {
                    Text("Last phase access").font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
                    Spacer(minLength: 2)
                    AccessBadgesView(read: session.lastExecutionStep?.highlights.readMemory.contains(address) == true,
                                     written: session.lastExecutionStep?.highlights.writtenMemory.contains(address) == true,
                                     changed: session.lastExecutionStep?.highlights.changedMemory.contains(address) == true)
                }
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        decimalReading(value)
                        HStack {
                            Calibration("HEX \(ToyInk.hex(Int(value)))")
                            Spacer()
                            pixelSwatch(address: address, value: value)
                        }
                    }
                } else {
                    HStack {
                        decimalReading(value)
                        Spacer()
                        Calibration("HEX \(ToyInk.hex(Int(value)))")
                        pixelSwatch(address: address, value: value)
                    }
                }
                Text("Tap a bit to flip it · most significant bit at left")
                    .font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
                ByteBits(value: value) { bit in session.writeByte(at: address, value: value ^ (1 << bit)) }
                if address < 128 {
                    let base = address / 4 * 4
                    NamedInstructionBytesView(bytes: Array(session.machine.memory[base..<(base + 4)]),
                                              identifier: "memoryInstructionBytes")
                    Text("Selected field: \(["opcode", "operand A", "operand B", "reserved zero"][address % 4])")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
                InstrumentParameterStepper("ADDRESS", value: Binding(get: { session.selectedAddress }, set: { session.selectedAddress = $0 }), in: 0...255, unit: "DEC")
                InstrumentParameterStepper("VALUE", value: Binding(get: { Int(session.machine.memory[session.selectedAddress]) }, set: { session.writeByte(at: session.selectedAddress, value: UInt8($0)) }), in: 0...255, unit: "DEC")
                ScrollView(.vertical) {
                    Text(addressDescription(address))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(height: addressDetailHeight, alignment: .top)
                    .accessibilityIdentifier("memoryAddressDetailViewport")
                Text("The probe is an external debugger. It can patch any byte, even while a user program is restricted from touching devices.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            }
        }
    }

    private func decimalReading(_ value: UInt8) -> some View {
        ZStack(alignment: .leading) {
            Text("255").hidden().accessibilityHidden(true)
            Text("\(value)")
        }
        .font(.system(.largeTitle, design: .rounded, weight: .light)).monospacedDigit()
        .fixedSize(horizontal: true, vertical: true)
    }

    private func pixelSwatch(address: Int, value: UInt8) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(address >= 192 ? ToyInk.pixels[Int(value & 7)] : Color.clear)
            .frame(width: 34, height: 34).accessibilityHidden(true)
    }

    private func addressDescription(_ address: Int) -> String {
        if address < 128 {
            let base = address / 4 * 4
            let decoded = try? Decoder.decode(Array(session.machine.memory[base..<(base + 4)]))
            return "Instruction at 0x\(ToyInk.hex(base)): \(decoded?.description ?? "invalid encoding")"
        }
        if address >= 192 {
            let pixel = address - 192
            return "Pixel (\(pixel % 8), \(pixel / 8)) → 192 + y × 8 + x = \(address)"
        }
        return "Data and stack RAM: 0x80–0xBF. The stack grows toward lower addresses."
    }

    private func memoryCell(_ address: Int) -> some View {
        let value = session.machine.memory[address]
        let selected = address == session.selectedAddress
        let active = session.machine.currentInstructionAddress.map { ($0..<($0 + 4)).contains(address) } ?? false
        let written = session.lastExecutionStep?.highlights.writtenMemory.contains(address) == true
        let read = session.lastExecutionStep?.highlights.readMemory.contains(address) == true
        return Button { session.selectedAddress = address } label: {
            VStack(spacing: 4) {
                Text(ToyInk.hex(address)).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                Text(ToyInk.hex(Int(value))).font(.system(.body, design: .monospaced, weight: .medium))
                    .foregroundStyle(written || active ? InstrumentPalette.actionAmber : read ? InstrumentPalette.actionCyan : InstrumentPalette.displayInk)
            }.frame(maxWidth: .infinity, minHeight: 54)
                .background(selected ? InstrumentPalette.actionCyan.opacity(0.15) : Color.black.opacity(0.20), in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? InstrumentPalette.actionCyan : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel("Address \(address)").accessibilityValue("\(value), hex \(ToyInk.hex(Int(value)))")
            .accessibilityHint(written ? "Written by the last microcycle." : read ? "Read by the last microcycle." : "Select this byte in the probe.")
    }
}
