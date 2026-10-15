import SwiftUI

/// The physical and software abstractions represented by the AT-8 teaching machine.
struct LayerAtlasView: View {
    @State private var selected: AtlasLayer = .assembly
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    detailPanel
                        .id("layerDetail")
                    pathPanel
                    routePanel(reader: reader)
                    scopePanel
                }
                .padding(16)
            }
            .background { InstrumentDesignBackground() }
            .foregroundStyle(InstrumentPalette.displayInk)
            .preferredColorScheme(.dark)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            atlasEyebrow("AT-8 · ABSTRACTION ATLAS")
            Text("One pixel. Every layer.")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("Explore the path from a controlled switch to a program drawing on its screen.")
                .font(.subheadline)
                .foregroundStyle(InstrumentPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detailPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected.symbol)
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(InstrumentPalette.actionCyan)
                        .frame(width: 44, height: 44)
                        .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        atlasEyebrow("LAYER \(selected.index + 1) OF \(AtlasLayer.allCases.count)")
                        Text(selected.title)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                }
                Text(selected.role)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    atlasEyebrow("FOLLOW THE PIXEL")
                    Text(selected.pixelPath)
                        .font(.subheadline)
                        .foregroundStyle(InstrumentPalette.displayInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    atlasEyebrow("GOVERNING RULE")
                    Text(selected.equation)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(InstrumentPalette.actionCyan)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    atlasEyebrow("IN THIS TOY")
                    Text(selected.boundary)
                        .font(.caption)
                        .foregroundStyle(InstrumentPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    layerStepButton(direction: -1)
                    layerStepButton(direction: 1)
                }
            }
        }
    }

    private var pathPanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 12) {
                atlasEyebrow("A CONCRETE SOFTWARE PATH")
                Text("Draw palette 5 at (3, 3)")
                    .font(.headline)
                Text("LDI R0, 27\nLDI R1, 5\nSYS 1\nSYS 6")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(InstrumentPalette.actionCyan)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 12))
                    .textSelection(.enabled)
                    .accessibilityLabel("Assembly example. Load immediate register zero with twenty-seven. Load immediate register one with five. System call one draws a pixel. System call six exits.")
                HStack(spacing: 8) {
                    pathReadout("INDEX", "27")
                    pathReadout("ADDRESS", "219")
                    pathReadout("PALETTE", "5")
                }
                Text("Assembly → bytes → loader → memory → CPU → trap → kernel → display driver → framebuffer → screen. Follow the layers below to see which part owns each step.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func routePanel(reader: ScrollViewProxy) -> some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 14) {
                atlasEyebrow("SELECT ANY LAYER")
                Text("Hardware below. Software above.")
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(AtlasLayer.allCases.reversed()) { layer in
                        Button {
                            selected = layer
                            if reduceMotion {
                                reader.scrollTo("layerDetail", anchor: .top)
                            } else {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    reader.scrollTo("layerDetail", anchor: .top)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(selected == layer ? InstrumentPalette.actionCyan : InstrumentPalette.canvas)
                                        .frame(width: 32, height: 32)
                                    Text(String(format: "%02d", layer.index + 1))
                                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                        .foregroundStyle(selected == layer ? InstrumentPalette.canvas : InstrumentPalette.secondaryInk)
                                }
                                Text(layer.title)
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    .foregroundStyle(selected == layer ? InstrumentPalette.actionCyan : InstrumentPalette.displayInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: layer.symbol)
                                    .font(.system(size: 17, weight: .light))
                                    .foregroundStyle(selected == layer ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 13))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13)
                                    .strokeBorder(selected == layer ? InstrumentPalette.actionCyan.opacity(0.7) : .white.opacity(0.07), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Explore layer \(layer.index + 1), \(layer.title)")
                        .accessibilityAddTraits(selected == layer ? .isSelected : [])
                        if layer != .transistors {
                            Rectangle()
                                .fill(InstrumentPalette.actionCyan.opacity(0.2))
                                .frame(width: 1, height: 8)
                                .padding(.leading, 28)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Text("This stack describes responsibilities, not a claim that each item is a physical component or a strictly sequential stage. Registers, memory and control logic cooperate during each instruction.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopePanel: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 10) {
                atlasEyebrow("AT-8 CONTRACT")
                Text("A custom 8-bit teaching computer")
                    .font(.headline)
                Text("4 registers · 256 memory bytes · fixed 4-byte instructions · up to 32 instructions · 8 × 8 display")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(InstrumentPalette.actionCyan)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Code: 0…127\nData and stack: 128…191\nDisplay framebuffer: 192…255\nInitial SP: 192; first push writes 191")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                Text("The toy simulates its own CPU, protection checks, services and display driver. It does not execute real ARM instructions or expose the iPhone’s hardware or iOS kernel. Analog electronics, caches, pipelines, MMU paging, multitasking and networking are outside this model.")
                    .font(.caption)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func layerStepButton(direction: Int) -> some View {
        let index = selected.index + direction
        let available = AtlasLayer.allCases.indices.contains(index)
        return Button {
            if available { selected = AtlasLayer.allCases[index] }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: direction < 0 ? "arrow.down" : "arrow.up")
                Text(direction < 0 ? "Lower layer" : "Higher layer")
            }
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(available ? InstrumentPalette.actionCyan : InstrumentPalette.secondaryInk.opacity(0.4))
            .background(InstrumentPalette.canvas, in: .capsule)
            .overlay { Capsule().strokeBorder(InstrumentPalette.actionCyan.opacity(available ? 0.25 : 0.05), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityHint(available ? "Explore \(AtlasLayer.allCases[index].title)" : "End of the layer stack")
    }

    private func pathReadout(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.system(.caption2, design: .monospaced))
            Text(value).font(.system(.title3, design: .monospaced, weight: .semibold))
        }
        .foregroundStyle(InstrumentPalette.actionCyan)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(InstrumentPalette.canvas, in: .rect(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }
}

private enum AtlasLayer: CaseIterable, Identifiable {
    case transistors, gates, alu, registers, instructionBits, assembly, image
    case loader, memory, cpu, devices, syscall, kernel, app

    var id: Self { self }
    var index: Int { Self.allCases.firstIndex(of: self)! }

    var title: String {
        switch self {
        case .transistors: "Transistor switch"
        case .gates: "Logic gates"
        case .alu: "Arithmetic & logic unit"
        case .registers: "Registers"
        case .instructionBits: "Instruction bits"
        case .assembly: "Assembly language"
        case .image: "Assembler & linker"
        case .loader: "Program loader"
        case .memory: "Memory & stack"
        case .cpu: "Fetch · decode · execute"
        case .devices: "MMIO & display driver"
        case .syscall: "System call boundary"
        case .kernel: "Kernel services"
        case .app: "Functional screen app"
        }
    }

    var symbol: String {
        switch self {
        case .transistors: "switch.2"
        case .gates: "point.3.connected.trianglepath.dotted"
        case .alu: "plus.forwardslash.minus"
        case .registers: "square.stack.3d.up"
        case .instructionBits: "number.square"
        case .assembly: "chevron.left.forwardslash.chevron.right"
        case .image: "shippingbox"
        case .loader: "arrow.down.to.line"
        case .memory: "memorychip"
        case .cpu: "cpu"
        case .devices: "cable.connector"
        case .syscall: "arrow.up.right.square"
        case .kernel: "shield.lefthalf.filled"
        case .app: "display"
        }
    }

    var role: String {
        switch self {
        case .transistors:
            "A transistor’s control terminal changes whether a conducting path is available. Networks of transistors implement digital logic. Binary 0 and 1 stand for voltage ranges in physical hardware."
        case .gates:
            "Gates give names to Boolean relationships between input and output bits. AND, OR and XOR compose into bigger circuits; a full adder combines two data bits with one carry bit."
        case .alu:
            "The ALU selects an arithmetic or logic operation and transforms input words into an output word and flags. Eight full adders can add two eight-bit values with a ripple carry chain."
        case .registers:
            "Registers hold the CPU’s immediate working values. A register keeps its bits until an instruction writes a replacement. The program counter and stack pointer track execution and stack position."
        case .instructionBits:
            "An instruction is a binary agreement between the assembler and CPU. The opcode chooses an operation; operand bytes select registers, values, addresses or services. The CPU fetches these bytes from memory."
        case .assembly:
            "Assembly assigns readable mnemonics to the machine’s operations. Labels name positions in the program. Changing an operand changes the bytes the machine executes and, eventually, visible behavior."
        case .image:
            "An assembler parses instructions, checks operands and emits encoded bytes. Linking resolves references and combines object code in larger systems. Here, one flat program image resolves its own labels before loading."
        case .loader:
            "The loader places a program image and initial data into the machine’s memory, establishes a starting state and prepares the CPU to fetch the first instruction. Loading is different from executing."
        case .memory:
            "Memory stores addressable bytes. Code and data occupy different regions by convention and protection rules. A stack stores temporary values by moving its pointer and writing or reading a byte."
        case .cpu:
            "The CPU repeatedly fetches instruction bytes at PC, decodes their meaning, and executes the chosen operation. Each instruction can change registers, memory, flags or the next PC. A system call takes a longer path."
        case .devices:
            "Memory-mapped I/O (MMIO) gives a device’s registers or buffers addresses. Here the display framebuffer is mapped into memory: a driver writes bytes, and the screen interprets them as pixels. Isolated input and console ports are separate from RAM."
        case .syscall:
            "A system call asks privileged software to perform a service. The program supplies arguments, traps into the kernel, and resumes after the kernel returns. This boundary gives the operating system control over access."
        case .kernel:
            "The kernel owns protected services. It validates a request, chooses a service, coordinates its driver and returns control. The teaching kernel provides display, input, console, tick and exit services. When a program breaks a rule, the kernel stops it; when the kernel itself goes wrong, nothing is above it, so the whole machine panics."
        case .app:
            "A functional program links intent to an observable effect: input changes data, instructions operate on that data, and a service updates the screen. The visual canvas can generate assembly that rebuilds its pixels."
        }
    }

    var pixelPath: String {
        switch self {
        case .transistors:
            "The gate bench models the smallest control idea: SOURCE = 1 and GATE = 1 create an output signal. Many such switching elements would underpin the logic that handles the pixel’s index and color."
        case .gates:
            "The pixel index 27 is 00011011₂; palette 5 is 00000101₂. Gates operate on their individual bits. They also build the adder used when the display driver computes framebuffer address 192 + 27."
        case .alu:
            "To locate the pixel, the driver computes 192 + 27 = 219. 11000000₂ + 00011011₂ = 11011011₂. The displayed low byte is 219; there is no carry beyond bit 7 in this example."
        case .registers:
            "LDI R0, 27 stores the pixel index in R0. LDI R1, 5 stores its palette in R1. SYS 1 reads those registers as arguments. These values are visible in the CPU inspector before the trap."
        case .instructionBits:
            "LDI R0, 27 becomes 01 00 1B 00 in hexadecimal. SYS 1 becomes 17 01 00 00. 0x17 is decimal opcode 23. For SYS, operand A is the service number rather than a register."
        case .assembly:
            "The four-instruction example loads index 27 and palette 5, requests draw-pixel service 1, then requests exit service 6. Edit the immediate values or regenerate assembly from the WYSIWYG canvas to change the output."
        case .image:
            "The example emits 16 code bytes. Labels in a loop resolve to four-byte-aligned code addresses. A .org 128 directive positions data at address 128; .byte entries emit literal data bytes for the canvas program."
        case .loader:
            "The example code starts at address 0. The loader clears and initializes the teaching machine, copies the code into 0…127, places declared data into 128…191, and starts execution with PC = 0 and SP = 192."
        case .memory:
            "The CPU fetches the example from the code region. The privileged driver writes byte 5 to address 219 in the framebuffer. User LD/ST instructions cannot write the framebuffer directly."
        case .cpu:
            "First fetch 01 00 1B 00, decode LDI, then write R0 = 27. Repeat for R1 = 5. When the fetched opcode is SYS, follow trap → kernel → driver → return-to-user before the next user instruction."
        case .devices:
            "Draw-pixel service 1 reaches the display driver. It writes palette 5 at framebuffer byte 219. The screen interprets index 27 as row 3, column 3 and renders that byte’s low three bits as a palette color."
        case .syscall:
            "SYS 1 passes R0 = 27 and R1 = 5. The CPU leaves user execution and enters the service path. After the pixel is written, it returns to the next user instruction. SYS 6 then requests program exit."
        case .kernel:
            "The kernel checks index 27 is within 0…63 and palette 5 is within 0…7, then authorizes the driver operation. An invalid request faults instead of letting a user program address arbitrary display memory."
        case .app:
            "The final screen lights pixel (3, 3) with palette 5. Drawing on the 8 × 8 canvas creates 64 pixel bytes; generated assembly loops through the data and calls SYS 1 to reproduce the picture through the same kernel path."
        }
    }

    var equation: String {
        switch self {
        case .transistors: "ideal OUT = SOURCE ∧ GATE"
        case .gates: "S = A ⊕ B ⊕ Cᵢₙ\nCₒᵤₜ = (A ∧ B) ∨ (Cᵢₙ ∧ (A ⊕ B))"
        case .alu: "R = (A + B) mod 256\nC = 1 when A + B > 255"
        case .registers: "R0 ← 27\nR1 ← 5\n0 ≤ Rᵢ ≤ 255"
        case .instructionBits: "[opcode, operand A, operand B, 0]\nLDI: [1, register, immediate, 0]\nSYS: [23, service, 0, 0]"
        case .assembly: "LDI R0, 27 → R0 ← 27\nSYS 1 → draw(R0, R1)"
        case .image: "instruction address = 4 × instruction index\ncode bytes ≤ 128"
        case .loader: "PC ← 0\nSP ← 192\nRAM[code address] ← encoded byte"
        case .memory: "first PUSH: SP ← 191; RAM[191] ← value\nframebuffer address = 192 + index"
        case .cpu: "IR ← RAM[PC…PC+3]\nnext PC = PC + 4, unless control flow changes it"
        case .devices: "index = y × 8 + x\nx = index mod 8; y = index ÷ 8\npalette = framebuffer byte ∧ 7"
        case .syscall: "user → trap → kernel → driver → return\nSYS 1: draw(index: R0, palette: R1)"
        case .kernel: "0 ≤ pixel index < 64\n0 ≤ palette < 8\nauthorized write: RAM[192 + index] ← palette"
        case .app: "canvas pixels → 64 data bytes\nloop: load palette → SYS 1 → next pixel"
        }
    }

    var boundary: String {
        switch self {
        case .transistors:
            "This switch is a conceptual control model. No voltage, current, transistor characteristic curves or analog timing are simulated. A single switch is not a full CMOS logic gate."
        case .gates:
            "Boolean equations are exact for ideal bits. The visual carry path shows dependency, not measured propagation delays or a transistor-level netlist."
        case .alu:
            "AT-8 uses eight-bit arithmetic and logic. The gate bench exposes carry and two’s-complement overflow as teaching signals; it is not an ARM ALU replica."
        case .registers:
            "There are four eight-bit general registers R0…R3. PC and SP are separate control state. Real CPU register files, physical storage cells and clock behavior are not modeled electrically."
        case .instructionBits:
            "This is the custom AT-8 encoding, not ARM, x86 or a real iOS executable format. Each instruction is exactly four bytes, and the reserved byte is zero."
        case .assembly:
            "These mnemonics target AT-8. No high-level compiler is hidden between this text and its emitted bytes. The emulator executes bytes fetched from memory."
        case .image:
            "One flat image is assembled and labels are resolved locally. External symbols, multiple object files, dynamic libraries and relocation tables are outside the model."
        case .loader:
            "The loader operates on toy RAM, not the iPhone’s address space. There are no executable file formats, process creation, virtual-memory mappings or dynamic loading here."
        case .memory:
            "256 bytes: code 0…127, data/stack 128…191, protected framebuffer 192…255. The teaching machine checks access; it has no caches, MMU paging or real memory bus timing."
        case .cpu:
            "Microphases are visible teaching steps. They do not reproduce a real CPU’s cycles, speculative execution or pipeline. A full instruction may take several visible phases."
        case .devices:
            "Port 0 is input and port 1 is console output, distinct from RAM. User programs use kernel services instead of direct IN/OUT or framebuffer stores. No physical display controller is driven."
        case .syscall:
            "SYS is a custom instruction. Its argument convention is an AT-8 ABI and is not the iOS syscall ABI. The transition is enforced by this emulator’s state and access checks."
        case .kernel:
            "Services: 1 draw pixel, 2 fill screen, 3 read input into R0, 4 print ASCII from R0, 5 read ticks into R0, 6 exit, 7 a deliberately unchecked draw, 8 watchdog check-in. A panic here stops one 256-byte model; a real kernel panic restarts the whole device. No scheduler, multitasking, files, MMU or network stack is simulated."
        case .app:
            "The toy renders an eight-color 8 × 8 framebuffer. SwiftUI displays the simulated result. The generated picture is executable AT-8 software; the toy itself is a native iOS app."
        }
    }
}

private func atlasEyebrow(_ text: String) -> some View {
    Text(text)
        .font(.system(.caption2, design: .monospaced, weight: .medium))
        .tracking(1.2)
        .foregroundStyle(InstrumentPalette.secondaryInk)
}
