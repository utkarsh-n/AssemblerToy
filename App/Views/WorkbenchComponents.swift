import SwiftUI
import AssemblerCore

enum ToyInk {
    static let pixels: [Color] = [Color(red: 0.025, green: 0.045, blue: 0.055), InstrumentPalette.actionCyan,
        InstrumentPalette.actionAmber, InstrumentPalette.spectrum, Color(red: 0.39, green: 0.95, blue: 0.61),
        Color(red: 1, green: 0.37, blue: 0.42), InstrumentPalette.displayInk, InstrumentPalette.waveDepth]
    static let names = ["Off", "Cyan", "Amber", "Violet", "Green", "Red", "White", "Blue"]
    static func hex(_ value: Int) -> String { String(format: "%02X", value) }
    static func bits(_ value: UInt8) -> String {
        String((0..<8).reversed().map { value & (1 << $0) == 0 ? "0" : "1" })
    }
}

struct Calibration: View {
    let text: String
    var color: Color = InstrumentPalette.secondaryInk
    init(_ text: String, color: Color = InstrumentPalette.secondaryInk) {
        self.text = text; self.color = color
    }
    var body: some View {
        Text(text).font(.system(.caption2, design: .monospaced, weight: .medium))
            .tracking(1.4).foregroundStyle(color)
    }
}

struct SectionHeading: View {
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer(minLength: 8)
            Calibration(detail)
        }
    }
}

struct PixelMatrix: View {
    let pixels: [UInt8]
    var selected: Int? = nil
    var interactive = false
    var action: (Int) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { y in
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { x in
                        let i = y * 8 + x
                        let colorIndex = i < pixels.count ? Int(pixels[i] & 7) : 0
                        Button { action(i) } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ToyInk.pixels[colorIndex])
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(selected == i ? Color.white : Color.white.opacity(0.08), lineWidth: selected == i ? 2 : 0.5)
                                }
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .disabled(!interactive)
                        .accessibilityLabel("Pixel \(x), \(y)")
                        .accessibilityValue(ToyInk.names[colorIndex])
                    }
                }
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 12))
        .instrumentControlOwnsTouches(identifier: "pixelMatrix")
    }
}

struct MetalHousing<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(18)
            .background(LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.12), Color(red: 0.018, green: 0.03, blue: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.03), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.5), radius: 15, y: 8)
    }
}

struct ByteBits: View {
    let value: UInt8
    var action: ((Int) -> Void)? = nil
    var body: some View {
        HStack(spacing: 5) {
            ForEach((0..<8).reversed(), id: \.self) { bit in
                let high = value & (1 << bit) != 0
                Button { action?(bit) } label: {
                    Text(high ? "1" : "0")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(high ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(high ? InstrumentPalette.actionCyan.opacity(0.12) : Color.black.opacity(0.25), in: .rect(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(action == nil)
                    .accessibilityLabel("Bit \(bit)").accessibilityValue(high ? "One" : "Zero")
                    .accessibilityHint(action == nil ? "" : "Double tap to flip this bit")
            }
        }
        .instrumentControlOwnsTouches(identifier: "byteBits")
    }
}

/// A whole-machine stop, shown in the shape of a real panic log.
struct PanicReportPanel: View {
    let panic: KernelPanic

    var body: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("Kernel panic · \(panic.kind.title)", systemImage: "exclamationmark.octagon")
                    .foregroundStyle(ToyInk.pixels[5])
                Text(panic.kind.explanation).font(.subheadline)
                ScrollView(.horizontal) {
                    Text(panic.log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstrumentPalette.displayInk)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(10)
                }
                .background(.black.opacity(0.3), in: .rect(cornerRadius: 10))
                .accessibilityLabel(panic.log)
                Text("A real computer restarts at this point. Here the stopped state stays inspectable: Rewind to the moment before, or Reset to reboot.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("kernelPanicPanel")
    }
}
