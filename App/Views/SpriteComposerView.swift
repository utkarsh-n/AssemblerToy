import SwiftUI
import AssemblerCore

struct SpriteComposerView: View {
    let session: MachineSession
    @State private var pixels: [UInt8]
    @State private var brush: UInt8 = 1
    @State private var mode: ExecutionMode = .user
    @State private var showSource = false
    @State private var canvasWidth: CGFloat = 340
    @State private var selectedPixel = 0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: MachineSession) {
        self.session = session
        _pixels = State(initialValue: session.machine.framebuffer)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentDesignBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Draw the result. Build the program.")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        Text("Paint an 8×8 sprite. Your drawing becomes 64 data bytes and a small assembly loop. Watch the CPU turn those bytes back into the screen.")
                            .font(.subheadline).foregroundStyle(InstrumentPalette.secondaryInk)
                        Picker("Rendering environment", selection: $mode) {
                            ForEach(ExecutionMode.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                            PixelMatrix(pixels: pixels, selected: selectedPixel, interactive: true) { selectedPixel = $0; pixels[$0] = brush }
                                .frame(maxWidth: 421)
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
                                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                    let pitch = (canvasWidth - 37) / 8 + 3
                                    let x = Int((value.location.x - 8) / pitch)
                                    let y = Int((value.location.y - 8) / pitch)
                                    if value.location.x >= 8, value.location.y >= 8, (0..<8).contains(x), (0..<8).contains(y) {
                                        selectedPixel = y * 8 + x
                                        pixels[y * 8 + x] = brush
                                    }
                                })
                        Calibration("PAINT BY TOUCH • SCROLL BELOW THE CANVAS")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(0..<8, id: \.self) { index in
                                    Button { brush = UInt8(index) } label: {
                                        RoundedRectangle(cornerRadius: 10).fill(ToyInk.pixels[index])
                                            .frame(width: 44, height: 44)
                                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(brush == index ? .white : .white.opacity(0.15), lineWidth: brush == index ? 2 : 1) }
                                    }.buttonStyle(.plain).accessibilityLabel("Paint \(ToyInk.names[index])")
                                        .accessibilityAddTraits(brush == index ? .isSelected : [])
                                }
                            }.padding(2)
                        }
                        HStack {
                            Button("Clear") { pixels = Array(repeating: 0, count: 64) }.buttonStyle(.glass)
                            Button("Seed sprite") { seed() }.buttonStyle(.glass)
                            Spacer()
                            Calibration(ToyInk.names[Int(brush)].uppercased(), color: ToyInk.pixels[Int(brush)] == ToyInk.pixels[0] ? InstrumentPalette.secondaryInk : ToyInk.pixels[Int(brush)])
                        }
                        InstrumentParameterStepper("PIXEL", value: $selectedPixel, in: 0...63, unit: "INDEX")
                        Button("Paint selected pixel (\(selectedPixel % 8), \(selectedPixel / 8))") { pixels[selectedPixel] = brush }
                            .frame(minHeight: 44).buttonStyle(.glass)
                        InstrumentContentPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(mode == .user ? "LDX reads sprite data. SYS 1 asks the OS to validate and draw each pixel through its driver." : "LDX reads sprite data. STX writes each color directly into the physical framebuffer.")
                                    .font(.subheadline)
                                Text("10 instructions + 64 data bytes")
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.actionCyan)
                                Toggle("Inspect generated source", isOn: $showSource)
                                if showSource {
                                    Text(generatedSource).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    ShareLink("Share assembly", item: generatedSource).buttonStyle(.glass)
                                }
                            }
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(ToyInk.pixels[5]) }
                        Text("The editor works like a program generator: it changes source and data, then the loader resets the machine. The screen changes only when the generated program executes.")
                            .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                    }.padding(16).frame(maxWidth: 600).frame(maxWidth: .infinity).padding(.bottom, 90)
                }
            }.navigationTitle("Draw software").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        do {
                            try session.assemble(generatedSource, mode: mode)
                            session.title = "Your sprite"
                            session.toggleRun()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    } label: {
                        Label("Build & run this drawing", systemImage: "play.square")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.glassProminent).accessibilityIdentifier("buildDrawing")
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }
                .alert("Couldn’t build drawing", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }.preferredColorScheme(.dark)
    }

    private var generatedSource: String {
        let program: String
        if mode == .user {
            program = """
            ; Your drawing → OS display driver
            LDI R0, 0
            LDI R2, 128
            LDI R3, 64
            draw:
              LDX R1, R2
              SYS 1
              INC R0
              INC R2
              DEC R3
              JNZ draw
            HALT
            """
        } else {
            program = """
            ; Your drawing → physical framebuffer
            LDI R0, 192
            LDI R2, 128
            LDI R3, 64
            draw:
              LDX R1, R2
              STX R1, R0
              INC R0
              INC R2
              DEC R3
              JNZ draw
            HALT
            """
        }
        let data = (0..<8).map { row in
            ".byte " + pixels[(row * 8)..<(row * 8 + 8)].map(String.init).joined(separator: ", ")
        }.joined(separator: "\n")
        return program + "\n\n; Sprite data, one row at a time\n.org 128\n" + data + "\n"
    }

    private func seed() {
        let pattern = ["00011000", "00111100", "01111110", "11111111", "11011011", "11111111", "00100100", "01011010"]
        pixels = pattern.flatMap { $0.map { $0 == "1" ? UInt8(brush == 0 ? 1 : brush) : 0 } }
    }
}
