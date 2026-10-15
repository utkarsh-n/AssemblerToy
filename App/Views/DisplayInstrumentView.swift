import SwiftUI
import AssemblerCore

struct DisplayInstrumentView: View {
    let session: MachineSession
    var inspectPixel: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var telemetryWidth = 140.0
    @ScaledMetric(relativeTo: .caption) private var instructionHeight = 38.0

    var body: some View {
        MetalHousing {
            VStack(spacing: 14) {
                HStack {
                    Calibration("AT–8 / LIVE OUTPUT", color: InstrumentPalette.actionCyan)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(session.running ? InstrumentPalette.actionAmber : InstrumentPalette.secondaryInk).frame(width: 5, height: 5)
                        Calibration(session.machine.fault != nil ? "FAULT" : session.machine.halted ? "HALTED" : session.running ? "CLOCK ON" : "PAUSED")
                    }
                }
                liveOutput
                HStack {
                    Calibration(session.title.uppercased(), color: InstrumentPalette.displayInk)
                    Spacer()
                    Button { session.setInput(session.machine.inputValue == 0 ? 1 : 0) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(session.machine.inputValue == 0 ? InstrumentPalette.secondaryInk : InstrumentPalette.actionAmber).frame(width: 7, height: 7)
                            Text("INPUT \(session.machine.inputValue)").font(.system(.caption, design: .monospaced, weight: .semibold))
                        }.padding(.horizontal, 12).frame(minHeight: 44)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }.buttonStyle(.plain).accessibilityLabel("Hardware input button")
                        .accessibilityValue(session.machine.inputValue == 0 ? "Low, zero" : "High, one")
                        .accessibilityIdentifier("hardwareInput")
                }
                Text("Touch a pixel to inspect its physical address.")
                    .font(.system(.caption, design: .serif)).italic().foregroundStyle(InstrumentPalette.secondaryInk)
            }
        }
    }

    @ViewBuilder
    private var liveOutput: some View {
        if typeSize.isAccessibilitySize {
            stackedOutput
        } else {
            // The horizontal candidate has a fixed width for this text size.
            // Only available geometry can choose the arrangement; live values
            // cannot make ViewThatFits move the screen or program counter.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    display.frame(width: 176)
                    telemetry.frame(width: telemetryWidth, alignment: .leading)
                }
                stackedOutput
            }
        }
    }

    private var stackedOutput: some View {
        VStack(alignment: .leading, spacing: 14) {
            display.frame(maxWidth: 250).frame(maxWidth: .infinity)
            telemetry
        }
    }

    private var display: some View {
        VStack(spacing: 8) {
            PixelMatrix(pixels: session.machine.framebuffer, selected: session.selectedAddress >= 192 ? session.selectedAddress - 192 : nil, interactive: true) {
                session.selectedAddress = 192 + $0
                inspectPixel()
            }
            Calibration("8 × 8  /  0xC0–0xFF")
        }
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("0x\(ToyInk.hex(session.machine.pc))")
                .font(.system(.largeTitle, design: .rounded, weight: .light)).monospacedDigit()
                .foregroundStyle(InstrumentPalette.displayInk)
                .accessibilityIdentifier("programCounterReadout")
            Calibration("PROGRAM COUNTER")
            VStack(alignment: .leading, spacing: 4) {
                Text("Last: \(session.machine.trace.last?.phase.title ?? "—")")
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                Text("Next: \(session.machine.nextPhase.title)")
                    .foregroundStyle(InstrumentPalette.actionAmber)
            }
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            Text("\(session.machine.privilege.title) privilege")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(session.machine.privilege == .kernel ? InstrumentPalette.spectrum : InstrumentPalette.secondaryInk)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.machine.instructionCount) ops")
                Text("\(session.machine.cycleCount) cycles")
            }
            .font(.system(.caption2, design: .monospaced)).monospacedDigit()
            .foregroundStyle(InstrumentPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            Text(instructionContext)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan)
                .lineLimit(2).frame(height: instructionHeight, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionContext: String {
        guard let address = session.machine.currentInstructionAddress,
              !session.machine.fetchedBytes.isEmpty else {
            return "Next fetch @ 0x\(ToyInk.hex(session.machine.pc))\nLatch empty"
        }
        let instruction = session.machine.currentInstruction?.description
            ?? session.machine.fetchedBytes.map { ToyInk.hex(Int($0)) }.joined(separator: " ")
        return "Latched @ 0x\(ToyInk.hex(address))\n\(instruction)"
    }
}
