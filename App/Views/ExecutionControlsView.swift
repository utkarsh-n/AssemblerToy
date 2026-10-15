import SwiftUI

struct ExecutionControlsView: View {
    let session: MachineSession
    @Binding var microStep: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentDesignBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        InstrumentContentPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeading(title: "Step size", detail: "MANUAL")
                                Picker("Step size", selection: $microStep) {
                                    Text("Phase").accessibilityLabel("One microcycle").tag(true)
                                    Text("Instruction").accessibilityLabel("One instruction").tag(false)
                                }.pickerStyle(.segmented)
                                    .accessibilityIdentifier("stepSizeControl")
                                Text(microStep ? "Step advances one microcycle. Fetch, Decode and Execute remain separate." : "Step completes the instruction’s remaining phases. Rewind restores the state before that tap.")
                                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                            }
                        }
                        InstrumentContentPanel {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeading(title: "Playback speed", detail: "CLOCKED")
                                HStack {
                                    Text("\(session.playbackSpeed.formatted(.number.precision(.fractionLength(0...2))))×")
                                        .font(.system(.title2, design: .rounded, weight: .medium)).monospacedDigit()
                                    Spacer()
                                    Text("\(session.cyclesPerSecond.formatted(.number.precision(.fractionLength(0...2)))) cycles/s")
                                        .font(.system(.caption, design: .monospaced)).monospacedDigit()
                                        .accessibilityIdentifier("controlsPlaybackRateReadout")
                                }
                                Slider(value: Binding(get: { log2(session.playbackSpeed) },
                                                      set: { session.playbackSpeed = pow(2, $0) }),
                                       in: -2...2, step: 0.25)
                                    .tint(InstrumentPalette.actionCyan)
                                    .accessibilityLabel("Playback speed")
                                    .accessibilityValue("\(session.playbackSpeed.formatted(.number.precision(.fractionLength(0...2)))) times normal")
                                    .accessibilityIdentifier("playbackSpeedSlider")
                                HStack {
                                    Text("0.25×").foregroundStyle(InstrumentPalette.secondaryInk)
                                    Spacer()
                                    Button("Normal · 1×") { session.playbackSpeed = 1 }
                                        .frame(minHeight: 44).buttonStyle(.glass)
                                        .accessibilityLabel("Normal playback speed")
                                        .accessibilityIdentifier("normalPlaybackSpeed")
                                    Spacer()
                                    Text("4×").foregroundStyle(InstrumentPalette.secondaryInk)
                                }.font(.caption)
                                Text(session.isSpeedSettling ? "Easing into the new speed…" : "1× = 2 microcycles per second. Speed changes ease smoothly; every phase still executes.")
                                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                            }
                        }
                    }.padding(16)
                }
            }
            .navigationTitle("Execution controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.frame(minHeight: 44)
                        .accessibilityIdentifier("executionControlsDone")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
