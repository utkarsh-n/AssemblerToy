import SwiftUI
import AssemblerCore

/// The four positions of the AT-8 encoding stay visible beside their values.
struct NamedInstructionBytesView: View {
    let bytes: [UInt8]
    var identifier = "instructionBytes"
    @Environment(\.dynamicTypeSize) private var typeSize
    private let roles = ["OPCODE", "A", "B", "RESERVED"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                 count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(roles[index])
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                    Text(index < bytes.count ? "0x\(ToyInk.hex(Int(bytes[index])))" : "—")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .monospacedDigit().foregroundStyle(InstrumentPalette.actionCyan)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(.black.opacity(0.18), in: .rect(cornerRadius: 8))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instruction bytes")
        .accessibilityValue(bytes.map { "0x\(ToyInk.hex(Int($0)))" }.joined(separator: " "))
        .accessibilityHint("Four fields in order: opcode, operand A, operand B, reserved zero.")
        .accessibilityIdentifier(identifier)
    }
}

struct AccessBadgesView: View {
    var read = false
    var written = false
    var changed = false

    var body: some View {
        HStack(spacing: 5) {
            if read { badge("Read", symbol: "arrow.down.left", color: InstrumentPalette.actionCyan) }
            if written { badge("Written", symbol: "arrow.up.right", color: InstrumentPalette.actionAmber) }
            if changed { badge("Changed", symbol: "equal.slash", color: InstrumentPalette.actionAmber) }
            if !read && !written && !changed {
                Text("Untouched").font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
            }
        }
    }

    private func badge(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.08), in: .capsule)
    }
}
