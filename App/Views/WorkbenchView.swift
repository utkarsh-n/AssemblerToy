import SwiftUI
import AssemblerCore

enum WorkbenchSheet: String, Identifiable {
    case source, examples, composer, gates, atlas, guide, walkthrough, controls
    var id: String { rawValue }
}

enum BenchPage: String, CaseIterable {
    case machine = "Machine", code = "Assembly", memory = "Memory", system = "OS"
}

struct WorkbenchView: View {
    @State private var session = MachineSession()
    @State private var sheet: WorkbenchSheet?
    @State private var page = BenchPage.machine
    @State private var microStep = true
    @ScaledMetric(relativeTo: .footnote) private var statusHeight = 54.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentDesignBackground()
                ScrollViewReader { proxy in
                  ScrollView {
                    VStack(spacing: 16) {
                        header
                        DisplayInstrumentView(session: session, inspectPixel: { page = .memory })
                        quickTools
                        VStack(spacing: 14) {
                            pagePicker
                            pageContent
                        }.id("workspaceInspector")
                        if let panic = session.machine.panic {
                            PanicReportPanel(panic: panic)
                        } else if let fault = session.machine.fault {
                            InstrumentContentPanel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Machine fault", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(ToyInk.pixels[5])
                                    Text(fault).font(.subheadline)
                                    Text("The stopped state is inspectable. Rewind, edit the cause, or reset.")
                                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Text(session.notice ?? "Pause at any time to inspect the current instruction, registers and memory.")
                            .font(.footnote).foregroundStyle(InstrumentPalette.secondaryInk)
                            .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: statusHeight, alignment: .topLeading)
                        exploration
                        Text("AT-8 • a working model of a computer\n8-bit words · 256 bytes · one process · a tiny teaching OS")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(InstrumentPalette.secondaryInk)
                            .multilineTextAlignment(.center).padding(.vertical, 12)
                    }
                    .frame(maxWidth: 540)
                    .padding(.horizontal, 16).padding(.bottom, 110)
                    .frame(maxWidth: .infinity)
                  }
                  .onChange(of: page) { _, _ in
                      // Inspector changes are explicit navigation. Execution
                      // updates never move the reader's position.
                      proxy.scrollTo("workspaceInspector", anchor: .top)
                  }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                transport.padding(.horizontal, 14).padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .background(InstrumentPalette.canvas.ignoresSafeArea(edges: .bottom))
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .source: SourceEditorView(session: session)
                case .examples: ExampleLibraryView(session: session)
                case .composer: SpriteComposerView(session: session)
                case .gates: EducationSheet(title: "Gate bench") {
                    GateBenchView(a: session.machine.lastALU?.left ?? session.machine.registers[0],
                                  b: session.machine.lastALU?.right ?? session.machine.registers[1])
                }
                case .atlas: EducationSheet(title: "Every layer") { LayerAtlasView() }
                case .guide: ModelGuideView()
                case .walkthrough: GuidedInstructionView(session: session)
                case .controls: ExecutionControlsView(session: session, microStep: $microStep)
                }
            }
            .task(id: session.running) {
                guard session.running else { return }
                let clock = ContinuousClock()
                var previous = clock.now
                while session.running && !Task.isCancelled {
                    let now = clock.now
                    let elapsed = previous.duration(to: now).components
                    previous = now
                    session.advancePlayback(elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                    guard session.running && !Task.isCancelled else { return }
                    do { try await Task.sleep(for: .milliseconds(50)) }
                    catch { return }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { session.running = false } }
            .sensoryFeedback(.selection, trigger: session.machine.instructionCount) { _, _ in
                !session.running
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Assembler Toy").font(.system(.title, design: .rounded, weight: .semibold))
                Calibration("FROM A BIT TO A WORKING PROGRAM")
            }
            Spacer(minLength: 4)
            InstrumentGlassIconButton("atom", label: "Machine specification and help") { sheet = .guide }
        }.padding(.top, 12)
    }

    private var pagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inspect the running machine")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(InstrumentPalette.secondaryInk)
            HStack(spacing: 4) {
                ForEach(BenchPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        VStack(spacing: 5) {
                            Image(systemName: pageSymbol(item)).font(.caption)
                            Text(item.rawValue).font(.system(.caption, design: .rounded, weight: .semibold))
                        }.frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(page == item ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                            .background(page == item ? InstrumentPalette.actionCyan.opacity(0.12) : .black.opacity(0.12), in: .rect(cornerRadius: 11))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(item.rawValue)
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                        .accessibilityIdentifier("inspectLayer.\(pageID(item))")
                }
            }
        }
    }

    private func pageID(_ item: BenchPage) -> String {
        switch item { case .machine: "machine"; case .code: "code"; case .memory: "memory"; case .system: "system" }
    }

    private func pageSymbol(_ item: BenchPage) -> String {
        switch item { case .machine: "cpu"; case .code: "curlybraces"; case .memory: "memorychip"; case .system: "shield.lefthalf.filled" }
    }

    private var quickTools: some View {
        GlassEffectContainer(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                Button { session.startGuidedInstruction(); sheet = .walkthrough } label: {
                    toolLabel("Guide", detail: "Walk one instruction", symbol: "list.number")
                }.accessibilityLabel("Guide one instruction").accessibilityIdentifier("guidedModeButton")
                Button { session.running = false; sheet = .composer } label: {
                    toolLabel("Draw", detail: "Pixels into a program", symbol: "square.grid.3x3.fill")
                }.accessibilityLabel("Draw software")
                Button { session.running = false; sheet = .examples } label: {
                    toolLabel("Programs", detail: "Load an experiment", symbol: "books.vertical")
                }.accessibilityLabel("Program library")
                Button { session.running = false; sheet = .atlas } label: {
                    toolLabel("Layers", detail: "Explore the full stack", symbol: "square.3.layers.3d")
                }.accessibilityLabel("Layers of abstraction")
            }.buttonStyle(.glass)
                .frame(maxWidth: .infinity)
        }
    }

    private func toolLabel(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(InstrumentPalette.actionCyan)
            Text(detail).font(.caption2).foregroundStyle(InstrumentPalette.secondaryInk)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.horizontal, 4)
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .machine: CPUInspectorView(session: session)
        case .code: AssemblyInspectorView(session: session, edit: { sheet = .source }, inspectBytes: { _ in page = .memory })
        case .memory: MemoryInspectorView(session: session)
        case .system: SystemInspectorView(session: session)
        }
    }

    private var exploration: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Go deeper", detail: "THE WHOLE MACHINE")
                exploreButton("Draw software", subtitle: "Pixels → assembly → operating system", symbol: "square.grid.3x3.fill", destination: .composer)
                exploreButton("Program library", subtitle: "Hardware, loops, input, stack and system calls", symbol: "books.vertical", destination: .examples)
                exploreButton("Logic & silicon", subtitle: "Flip bits, close switches, build an ALU", symbol: "cpu", destination: .gates)
                exploreButton("Layers of abstraction", subtitle: "Follow one pixel through the full stack", symbol: "square.3.layers.3d", destination: .atlas)
                Button { session.startGuidedInstruction(); sheet = .walkthrough } label: {
                    Label("Guide one instruction", systemImage: "list.number")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.glass)
            }
        }
    }

    private func exploreButton(_ title: String, subtitle: String, symbol: String, destination: WorkbenchSheet) -> some View {
        Button { session.running = false; sheet = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(InstrumentPalette.actionCyan).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(.body, design: .rounded, weight: .medium)).foregroundStyle(InstrumentPalette.displayInk)
                    Text(subtitle).font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            }.frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var transport: some View {
        VStack(spacing: 5) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    InstrumentGlassIconButton("arrow.counterclockwise", label: "Reset machine") { session.reset() }
                    InstrumentGlassIconButton("backward.end", label: "Rewind one step") { session.rewind() }
                        .disabled(!session.canRewind)
                    Button { session.toggleRun() } label: {
                        Label(session.running ? "Pause" : "Run", systemImage: session.running ? "pause.fill" : "play.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .labelStyle(CompactTransportLabelStyle(iconOnly: typeSize.isAccessibilitySize))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glassProminent)
                        .tint(session.running ? InstrumentPalette.actionAmber : InstrumentPalette.actionCyan)
                        .accessibilityLabel(session.running ? "Pause" : "Run")
                        .accessibilityIdentifier("runMachine")
                    Button { session.step(micro: microStep) } label: {
                        Group {
                            if typeSize.isAccessibilitySize {
                                Image(systemName: "forward.end.fill").font(.body)
                            } else {
                                VStack(spacing: 1) {
                                    Text("Step").font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    Text(microStep ? "Phase" : "Instruction")
                                        .font(.system(.caption2, design: .rounded))
                                }
                            }
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glass)
                        .accessibilityLabel("Step")
                        .accessibilityValue(microStep ? "One microcycle" : "One instruction")
                        .accessibilityIdentifier("stepMachine")
                    Button { sheet = .controls } label: {
                        Group {
                            if typeSize.isAccessibilitySize {
                                Image(systemName: "slider.horizontal.3").font(.body)
                            } else {
                                VStack(spacing: 2) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("\(session.playbackSpeed.formatted(.number.precision(.fractionLength(0...2))))×")
                                        .font(.system(.caption2, design: .rounded)).monospacedDigit()
                                }
                            }
                        }.frame(width: 44, height: 44)
                    }.buttonStyle(.glass)
                        .accessibilityLabel("Execution controls")
                        .accessibilityValue("\(session.playbackSpeed.formatted(.number.precision(.fractionLength(0...2)))) times normal")
                        .accessibilityHint("Adjust playback speed and choose what Step performs")
                        .accessibilityIdentifier("executionControlsButton")
                }
            }
            HStack(spacing: 8) {
                if !typeSize.isAccessibilitySize {
                    Text("Last: \(session.machine.cycleCount == 0 ? "None yet" : session.machine.phase.title)")
                        .accessibilityIdentifier("workbenchLastPhase")
                    Text("Next: \(session.machine.nextPhase.title)")
                        .foregroundStyle(InstrumentPalette.actionAmber)
                        .accessibilityIdentifier("workbenchNextPhase")
                    Spacer(minLength: 0)
                }
                Text("\(session.cyclesPerSecond.formatted(.number.precision(.fractionLength(0...2)))) cycles/s")
                    .accessibilityIdentifier("playbackRateReadout")
            }
            .font(.system(.caption2, design: .monospaced)).monospacedDigit()
            .foregroundStyle(InstrumentPalette.secondaryInk)
        }
        .frame(maxWidth: 540)
        .padding(.top, 6)
    }

}

struct EducationSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct SheetShell<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentDesignBackground()
                ScrollView { content.padding(16).frame(maxWidth: 600).frame(maxWidth: .infinity).padding(.bottom, 24) }
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private struct CompactTransportLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon } else {
            HStack(spacing: 5) { configuration.icon; configuration.title }
        }
    }
}
