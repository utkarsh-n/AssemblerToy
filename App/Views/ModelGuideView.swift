import SwiftUI
import AssemblerCore

struct ModelGuideView: View {
    var body: some View {
        SheetShell(title: "Inside Assembler Toy") {
            VStack(alignment: .leading, spacing: 16) {
                Text("A computer small enough to see.").font(.system(.title2, design: .rounded, weight: .semibold))
                Text("Start with Run or Step. The first program uses system calls to produce a visible output. Load another experiment, change a register, flip a RAM bit, or draw your own sprite.")
                    .font(.subheadline)
                InstrumentContentPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The AT-8 contract").font(.headline)
                        fact("Words", "Eight-bit unsigned registers; arithmetic wraps modulo 256.")
                        fact("CPU", "Four registers, a byte-addressed PC, zero/carry flags, descending stack, visible microphases.")
                        fact("Encoding", "Four bytes: opcode, operand A, operand B, reserved zero. PC normally advances by four.")
                        fact("Memory", "0x00–0x7F code; 0x80–0xBF data/stack; 0xC0–0xFF display.")
                        fact("Pixel", "address = 192 + 8y + x. Color is byte AND 7.")
                        fact("Loader", "Copies an assembled 256-byte image into RAM and initializes the CPU. Labels are resolved by a two-pass assembler.")
                        fact("Protection", "User programs access code/data; device reads/writes require a syscall. The external debugger can patch all memory.")
                        fact("Panic", "A fault stops a program that broke a rule. A panic stops the whole machine: SYS 7 shows a kernel bug, SYS 8 a watchdog that gives up on a hung system. Reset reboots.")
                    }
                }
                InstrumentContentPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What the model represents").font(.headline)
                        Text("AT-8 is a custom educational ISA interpreted entirely inside this app. The kernel, ports and drivers are explicit Swift models. Microcycles reveal a causal sequence; their timing is chosen for learning.")
                        Text("The gate bench shows ideal Boolean logic and a digital controlled-switch analogy. It does not solve transistor voltages, semiconductor physics, propagation delay or actual power use.")
                        Text("This is one process with a simple privilege boundary. Real ARM instruction encodings, iOS system calls, executable formats, linking multiple objects, virtual memory, interrupts, caches, scheduling and multitasking are explained in the layer atlas where applicable; they are not simulated here.")
                        Text("Rewind restores up to 512 saved machine states, including RAM, registers, devices, input and trace. Reset restores the loaded program image.")
                    }.font(.subheadline)
                }
                InstrumentContentPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "Instruction set", detail: "27 OPCODES")
                        ForEach(Opcode.allCases, id: \.rawValue) { opcode in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(ToyInk.hex(Int(opcode.rawValue)))  \(opcode.mnemonic)")
                                    .font(.system(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(InstrumentPalette.actionCyan)
                                Text(opcode.explanation).font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                Text("Built with Metro Station’s portable SwiftUI design system: the same palette, technical typography, grid, content panels, glass controls and control touch boundaries.")
                    .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
            }
        }
    }

    private func fact(_ label: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Calibration(label.uppercased(), color: InstrumentPalette.actionCyan)
            Text(detail).font(.subheadline)
        }
    }
}
