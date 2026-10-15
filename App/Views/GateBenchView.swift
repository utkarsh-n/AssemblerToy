import SwiftUI

/// An ideal digital circuit bench. Values are unsigned eight-bit words.
struct GateBenchView: View {
    @State private var a: UInt8
    @State private var b: UInt8
    @State private var operation: BenchOperation = .add
    @State private var selectedBit = 0
    @State private var gateOn = true
    @State private var sourceOn = true

    init(a: UInt8 = 5, b: UInt8 = 3) {
        _a = State(initialValue: a)
        _b = State(initialValue: b)
    }

    private var result: UInt8 {
        switch operation {
        case .add: a &+ b
        case .and: a & b
        case .or: a | b
        case .xor: a ^ b
        }
    }

    private var carryOut: Bool { Int(a) + Int(b) > 255 }
    private var signedOverflow: Bool { ((a ^ result) & (b ^ result) & 0x80) != 0 }

    private var stages: [FullAdderStage] {
        var carry = false
        return (0..<8).map { bit in
            let first = bitValue(a, bit)
            let second = bitValue(b, bit)
            let sum = (first != second) != carry
            let nextCarry = (first && second) || (carry && (first != second))
            let stage = FullAdderStage(bit: bit, a: first, b: second,
                                       carryIn: carry, sum: sum, carryOut: nextCarry)
            carry = nextCarry
            return stage
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                operandsPanel
                outputPanel
                if operation == .add {
                    ripplePanel
                } else {
                    logicPanel
                }
                transistorPanel
                limitsPanel
            }
            .padding(16)
        }
        .background { InstrumentDesignBackground() }
        .foregroundStyle(InstrumentPalette.displayInk)
        .preferredColorScheme(.dark)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            benchEyebrow("BARE METAL · DIGITAL LOGIC")
            Text("Gate bench")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("Flip a wire. Follow the value.")
                .font(.subheadline)
                .foregroundStyle(InstrumentPalette.secondaryInk)
        }
    }

    private var operandsPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    benchEyebrow("INPUT WORDS")
                    Spacer()
                    InstrumentGlassIconButton("arrow.counterclockwise", label: "Reset operands to five and three") {
                        a = 5
                        b = 3
                    }
                }
                OperandBitRow(name: "A", value: $a, color: InstrumentPalette.actionCyan)
                OperandBitRow(name: "B", value: $b, color: InstrumentPalette.actionAmber)
                Text("Bit 7 is the most significant bit; bit 0 has weight 1. Each lit switch contributes 2ᵇ to its word.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BenchOperation.allCases) { item in
                            Button {
                                operation = item
                            } label: {
                                Text(item.rawValue)
                                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                    .frame(minWidth: 60, minHeight: 44)
                                    .foregroundStyle(operation == item ? InstrumentPalette.canvas : InstrumentPalette.displayInk)
                                    .background(operation == item ? InstrumentPalette.actionCyan : InstrumentPalette.canvas, in: .capsule)
                                    .overlay { Capsule().strokeBorder(InstrumentPalette.actionCyan.opacity(0.22), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(item.rawValue) operation")
                            .accessibilityAddTraits(operation == item ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private var outputPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 14) {
                benchEyebrow("ALU OUTPUT")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(a) \(operation.symbol) \(b)")
                        .font(.system(.title3, design: .monospaced))
                    Text("=")
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                    Text("\(result)")
                        .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                        .foregroundStyle(InstrumentPalette.actionCyan)
                }
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                Text(binaryWord(result))
                    .font(.system(.title2, design: .monospaced, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(InstrumentPalette.actionCyan)
                    .accessibilityLabel("Result bits, \(binaryWord(result))")
                HStack(spacing: 10) {
                    benchFlag("CARRY", value: operation == .add ? (carryOut ? "1" : "0") : "N/A",
                              active: operation == .add && carryOut)
                    benchFlag("SIGNED V", value: operation == .add ? (signedOverflow ? "1" : "0") : "N/A",
                              active: operation == .add && signedOverflow)
                    benchFlag("ZERO", value: result == 0 ? "1" : "0", active: result == 0)
                }
                Text(operation == .add
                     ? "R = (A + B) mod 256. Carry means the unsigned sum exceeded 255. Signed overflow means two values of the same sign produced the opposite sign in two’s complement (−128…127)."
                     : "\(operation.rawValue) works on eight independent pairs of bits. Carry and arithmetic overflow do not apply to this logic operation.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ripplePanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 14) {
                benchEyebrow("EIGHT FULL ADDERS · LOW TO HIGH")
                Text("Carry ripples into the next bit.")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(stages) { stage in
                            Button {
                                selectedBit = stage.bit
                            } label: {
                                VStack(spacing: 5) {
                                    Text("b\(stage.bit)").foregroundStyle(InstrumentPalette.secondaryInk)
                                    Text("\(digit(stage.a))+\(digit(stage.b))")
                                    Text("C\(digit(stage.carryIn)) → \(digit(stage.sum))")
                                        .foregroundStyle(stage.sum ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                                    Text("out \(digit(stage.carryOut))")
                                        .foregroundStyle(stage.carryOut ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
                                }
                                .font(.system(.caption2, design: .monospaced))
                                .frame(width: 68, height: 92)
                                .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13)
                                        .strokeBorder(selectedBit == stage.bit ? InstrumentPalette.actionCyan : .white.opacity(0.1), lineWidth: selectedBit == stage.bit ? 2 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Full adder bit \(stage.bit)")
                            .accessibilityValue("A \(digit(stage.a)), B \(digit(stage.b)), carry in \(digit(stage.carryIn)), sum \(digit(stage.sum)), carry out \(digit(stage.carryOut))")
                            .accessibilityAddTraits(selectedBit == stage.bit ? .isSelected : [])
                            if stage.bit < 7 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(stage.carryOut ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk.opacity(0.4))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                InstrumentParameterStepper("INSPECT BIT", value: $selectedBit, in: 0...7, unit: "")
                FullAdderDrawing(stage: stages[selectedBit])
                    .frame(height: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Bit \(selectedBit) full adder: input A \(digit(stages[selectedBit].a)), input B \(digit(stages[selectedBit].b)), carry in \(digit(stages[selectedBit].carryIn)). Sum \(digit(stages[selectedBit].sum)), carry out \(digit(stages[selectedBit].carryOut)).")
                Text("S = A ⊕ B ⊕ Cᵢₙ\nCₒᵤₜ = (A ∧ B) ∨ (Cᵢₙ ∧ (A ⊕ B))")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(InstrumentPalette.actionCyan)
                    .fixedSize(horizontal: false, vertical: true)
                Text("⊕ XOR · ∧ AND · ∨ OR. C₀ starts at 0. The carry from bit 7 becomes the carry flag; it is not stored in the eight-bit result.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                fullAdderTruthTable
            }
        }
    }

    private var fullAdderTruthTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            benchEyebrow("FULL ADDER TRUTH TABLE")
            HStack {
                ForEach(["A", "B", "Cᵢₙ", "S", "Cₒᵤₜ"], id: \.self) { label in
                    Text(label).frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(InstrumentPalette.secondaryInk)
            ForEach(0..<8, id: \.self) { row in
                let first = (row >> 2) & 1
                let second = (row >> 1) & 1
                let carry = row & 1
                let total = first + second + carry
                let chosen = (first == 1) == stages[selectedBit].a
                    && (second == 1) == stages[selectedBit].b
                    && (carry == 1) == stages[selectedBit].carryIn
                HStack {
                    ForEach(Array([first, second, carry, total & 1, total >> 1].enumerated()), id: \.offset) { _, value in
                        Text("\(value)").frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
                .foregroundStyle(chosen ? InstrumentPalette.actionCyan : InstrumentPalette.displayInk)
                .background(chosen ? InstrumentPalette.actionCyan.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
            }
        }
        .font(.system(.caption, design: .monospaced))
        .accessibilityElement(children: .combine)
    }

    private var logicPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 14) {
                benchEyebrow("PARALLEL BIT LOGIC")
                Text(operation.explanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                InstrumentParameterStepper("INSPECT BIT", value: $selectedBit, in: 0...7, unit: "")
                HStack(spacing: 10) {
                    signalTile("A\(selectedBit)", on: bitValue(a, selectedBit))
                    Text(operation.symbol).foregroundStyle(InstrumentPalette.secondaryInk)
                    signalTile("B\(selectedBit)", on: bitValue(b, selectedBit))
                    Text("=").foregroundStyle(InstrumentPalette.secondaryInk)
                    signalTile("R\(selectedBit)", on: bitValue(result, selectedBit))
                }
                HStack {
                    Text("A  B").frame(maxWidth: .infinity)
                    Text(operation.rawValue).frame(maxWidth: .infinity)
                }
                .foregroundStyle(InstrumentPalette.secondaryInk)
                ForEach(0..<4, id: \.self) { row in
                    let first = (row >> 1) & 1
                    let second = row & 1
                    HStack {
                        Text("\(first)  \(second)").frame(maxWidth: .infinity)
                        Text("\(operation.evaluate(first, second))").frame(maxWidth: .infinity)
                    }
                }
                .font(.system(.subheadline, design: .monospaced))
            }
        }
    }

    private var transistorPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 14) {
                benchEyebrow("ONE CONTROLLED SWITCH")
                Text("A gate signal opens a path.")
                    .font(.headline)
                ControlledSwitchDrawing(sourceOn: sourceOn, gateOn: gateOn)
                    .frame(height: 128)
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    switchButton("SOURCE", on: $sourceOn, color: InstrumentPalette.actionCyan)
                    switchButton("GATE", on: $gateOn, color: InstrumentPalette.actionAmber)
                }
                HStack {
                    signalTile("OUTPUT", on: sourceOn && gateOn)
                    Text("OUT = SOURCE ∧ GATE")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                }
                Text("This is a conceptual transistor-controlled switch: gate = 1 closes the signal path; gate = 0 breaks it. Real CMOS gates combine transistor networks, power rails and an output node. One switch alone is not a complete CMOS AND gate.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var limitsPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 7) {
                benchEyebrow("MODEL LIMITS")
                Text("Ideal digital gates: 0 and 1, exact Boolean logic, no voltage, current, capacitance or propagation-time simulation. The ripple diagram shows dependency order, not measured transistor timing.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func switchButton(_ name: String, on: Binding<Bool>, color: Color) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack {
                Image(systemName: on.wrappedValue ? "circle.fill" : "circle")
                Text("\(name)  \(on.wrappedValue ? "1" : "0")")
            }
            .font(.system(.subheadline, design: .monospaced, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(on.wrappedValue ? color : InstrumentPalette.secondaryInk)
            .background(InstrumentPalette.canvas, in: .capsule)
            .overlay { Capsule().strokeBorder(color.opacity(on.wrappedValue ? 0.7 : 0.18), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name.lowercased()) signal")
        .accessibilityValue(on.wrappedValue ? "One, on" : "Zero, off")
        .accessibilityHint("Double tap to flip the signal")
    }
}

private enum BenchOperation: String, CaseIterable, Identifiable {
    case add = "ADD", and = "AND", or = "OR", xor = "XOR"
    var id: Self { self }
    var symbol: String {
        switch self { case .add: "+"; case .and: "∧"; case .or: "∨"; case .xor: "⊕" }
    }
    var explanation: String {
        switch self {
        case .add: "Add two words using a carry chain."
        case .and: "AND lights a result bit only when both input bits are 1. Rᵢ = Aᵢ ∧ Bᵢ."
        case .or: "OR lights a result bit when either input bit is 1. Rᵢ = Aᵢ ∨ Bᵢ."
        case .xor: "XOR lights a result bit when the input bits differ. Rᵢ = Aᵢ ⊕ Bᵢ."
        }
    }
    func evaluate(_ a: Int, _ b: Int) -> Int {
        switch self { case .add: (a + b) & 1; case .and: a & b; case .or: a | b; case .xor: a ^ b }
    }
}

private struct FullAdderStage: Identifiable {
    let bit: Int
    let a: Bool
    let b: Bool
    let carryIn: Bool
    let sum: Bool
    let carryOut: Bool
    var id: Int { bit }
}

private struct OperandBitRow: View {
    let name: String
    @Binding var value: UInt8
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(name).font(.system(.headline, design: .monospaced))
                Spacer()
                Text("\(value) DEC · 0x\(String(format: "%02X", value))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array((0..<8).reversed()), id: \.self) { bit in
                        Button { value ^= UInt8(1 << bit) } label: {
                            VStack(spacing: 5) {
                                Text("\(bit)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(InstrumentPalette.secondaryInk)
                                Text(bitValue(value, bit) ? "1" : "0")
                                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(bitValue(value, bit) ? color : InstrumentPalette.secondaryInk)
                                Circle()
                                    .fill(bitValue(value, bit) ? color : color.opacity(0.08))
                                    .frame(width: 5, height: 5)
                            }
                            .frame(width: 44, height: 72)
                            .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 11))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(color.opacity(bitValue(value, bit) ? 0.5 : 0.13), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(name) bit \(bit), weight \(1 << bit)")
                        .accessibilityValue(bitValue(value, bit) ? "One" : "Zero")
                        .accessibilityHint("Double tap to flip this bit")
                    }
                }
            }
        }
    }
}

private struct FullAdderDrawing: View {
    let stage: FullAdderStage

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Canvas { context, size in
                    func wire(_ points: [CGPoint], on: Bool, carry: Bool = false) {
                        var path = Path()
                        path.addLines(points)
                        context.stroke(path, with: .color(on ? (carry ? InstrumentPalette.actionAmber : InstrumentPalette.actionCyan) : InstrumentPalette.secondaryInk.opacity(0.25)), lineWidth: on ? 3 : 1.5)
                    }
                    let left = size.width * 0.16
                    let right = size.width * 0.84
                    wire([CGPoint(x: left, y: 38), CGPoint(x: size.width * 0.42, y: 38), CGPoint(x: size.width * 0.42, y: 71)], on: stage.a)
                    wire([CGPoint(x: left, y: 88), CGPoint(x: size.width * 0.36, y: 88)], on: stage.b)
                    wire([CGPoint(x: left, y: 142), CGPoint(x: size.width * 0.44, y: 142), CGPoint(x: size.width * 0.44, y: 109)], on: stage.carryIn, carry: true)
                    wire([CGPoint(x: size.width * 0.64, y: 76), CGPoint(x: right, y: 76), CGPoint(x: right, y: 44)], on: stage.sum)
                    wire([CGPoint(x: size.width * 0.64, y: 101), CGPoint(x: right, y: 101), CGPoint(x: right, y: 140)], on: stage.carryOut, carry: true)
                }
                circuitLabel("A \(digit(stage.a))", on: stage.a)
                    .position(x: width * 0.1, y: 38)
                circuitLabel("B \(digit(stage.b))", on: stage.b)
                    .position(x: width * 0.1, y: 88)
                circuitLabel("Cᵢₙ \(digit(stage.carryIn))", on: stage.carryIn, amber: true)
                    .position(x: width * 0.1, y: 142)
                VStack(spacing: 4) {
                    Text("FULL").tracking(2)
                    Text("ADDER").tracking(2)
                    Text("b\(stage.bit)").foregroundStyle(InstrumentPalette.actionCyan)
                }
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .frame(width: width * 0.28, height: 67)
                .background(InstrumentPalette.content, in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(InstrumentPalette.actionCyan.opacity(0.5), lineWidth: 1) }
                .position(x: width * 0.5, y: 89)
                circuitLabel("S \(digit(stage.sum))", on: stage.sum)
                    .position(x: width * 0.86, y: 36)
                circuitLabel("Cₒᵤₜ \(digit(stage.carryOut))", on: stage.carryOut, amber: true)
                    .position(x: width * 0.86, y: 148)
            }
        }
        .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 16))
    }

    private func circuitLabel(_ text: String, on: Bool, amber: Bool = false) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .foregroundStyle(on ? (amber ? InstrumentPalette.actionAmber : InstrumentPalette.actionCyan) : InstrumentPalette.secondaryInk)
            .padding(5)
            .background(InstrumentPalette.canvas)
    }
}

private struct ControlledSwitchDrawing: View {
    let sourceOn: Bool
    let gateOn: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Canvas { context, size in
                let center = size.width / 2
                let y: CGFloat = 73
                func wire(_ points: [CGPoint], color: Color) {
                    var path = Path()
                    path.addLines(points)
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                let sourceColor = sourceOn ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk.opacity(0.3)
                let outputColor = sourceOn && gateOn ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk.opacity(0.3)
                wire([CGPoint(x: 24, y: y), CGPoint(x: center - 30, y: y)], color: sourceColor)
                wire([CGPoint(x: center + 30, y: y), CGPoint(x: size.width - 24, y: y)], color: outputColor)
                wire([CGPoint(x: center - 30, y: y), CGPoint(x: center + 30, y: gateOn ? y : y - 30)], color: gateOn ? sourceColor : InstrumentPalette.secondaryInk)
                wire([CGPoint(x: center, y: 25), CGPoint(x: center, y: 43)], color: gateOn ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk.opacity(0.3))
                for x in [center - 30, center + 30] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(InstrumentPalette.displayInk))
                }
            }
            Text("GATE \(digit(gateOn))")
                .foregroundStyle(gateOn ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
                .position(x: width / 2, y: 15)
            Text("IN \(digit(sourceOn))")
                .foregroundStyle(sourceOn ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                .position(x: 46, y: 109)
            Text("OUT \(digit(sourceOn && gateOn))")
                .foregroundStyle(sourceOn && gateOn ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                .position(x: width - 46, y: 109)
        }
        .font(.system(.caption, design: .monospaced, weight: .medium))
        .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 16))
    }
}

private func benchEyebrow(_ text: String) -> some View {
    Text(text)
        .font(.system(.caption2, design: .monospaced, weight: .medium))
        .tracking(1.2)
        .foregroundStyle(InstrumentPalette.secondaryInk)
}

private func benchFlag(_ title: String, value: String, active: Bool) -> some View {
    VStack(spacing: 5) {
        Text(title).font(.system(.caption2, design: .monospaced))
        Text(value).font(.system(.headline, design: .monospaced))
    }
    .frame(maxWidth: .infinity, minHeight: 56)
    .foregroundStyle(active ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk)
    .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 11))
    .accessibilityElement(children: .combine)
}

private func signalTile(_ name: String, on: Bool) -> some View {
    VStack(spacing: 5) {
        Text(name).font(.system(.caption2, design: .monospaced))
        Text(digit(on)).font(.system(.title2, design: .monospaced, weight: .semibold))
    }
    .frame(maxWidth: .infinity, minHeight: 60)
    .foregroundStyle(on ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
    .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 11))
    .accessibilityElement(children: .combine)
}

private func bitValue(_ value: UInt8, _ bit: Int) -> Bool { value & UInt8(1 << bit) != 0 }
private func digit(_ value: Bool) -> String { value ? "1" : "0" }
private func binaryWord(_ value: UInt8) -> String { String(repeating: "0", count: 8 - String(value, radix: 2).count) + String(value, radix: 2) }
