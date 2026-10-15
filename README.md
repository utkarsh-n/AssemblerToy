# Assembler Toy

A native SwiftUI instrument that turns assembly into visible, interactive software. Built for iPhone and iOS 27, with Metro Station's actual portable design system.

## Play

The initial experiment draws a picture through the teaching OS. Tap **Run**, or use **Step** to watch instruction fetch, decode, execution, trap, kernel validation, driver access and return. Step shows **Phase / Instruction** as its current size. The compact speed/settings button opens **Execution controls** to change that size or playback speed. **Last** names the completed phase; **Next** names the upcoming phase. The speed slider spans 0.25×–4×; **1×** is two microcycles per second. Live speed changes ease over 450 milliseconds while preserving the partially elapsed phase. Each microcycle is presented individually, and the chosen speed survives Reset and reopening the app.

- **Draw** opens a WYSIWYG 8×8 sprite editor. Paint by tapping or dragging, choose Bare metal or User + OS, then **Build & run this drawing**. The generator creates ten instructions and 64 data bytes; execution reconstructs your drawing at your chosen playback speed. Use the visible slider to accelerate or slow the reconstruction. The generated source is inspectable and shareable.
- **Machine** exposes four editable registers, individual bits, condition flags, the stack pointer, the last ALU result and memory-bus traffic.
- **Guide** pauses the current machine and walks one real instruction through Assembly, CPU, Registers, Memory and OS. Compact instruction and phase context stays visible above one selected layer; source/action/destination cues explain the actual transfer. **Next** names and performs one actual microcycle; before/after values and written/read/changed cues distinguish access from a value change. Expand **All … details** for complete facts and microcycle history. **Back** restores the preceding machine state, **Restart** restores this walkthrough's entry state, and **Next instruction** replaces Next in the same control slot after completion. **Done** keeps the latest machine paused and retains your playback speed. Entering partway through an instruction preserves that exact entry point.
- **Assembly** shows source instructions beside their actual four RAM bytes, labeled Opcode, A, B and Reserved. Edit and assemble your own program, toggle a row's breakpoint, or use its explicit inspection action to open the corresponding code address in Memory. A breakpoint stops before fetch. Patched RAM is marked separately from the original source.
- **Memory** probes all 256 bytes in four banks, with an overview of code, data/stack and display ranges. The selected address includes its region; a bit-order hint and named code fields explain the selected byte. Flip bits or use native steppers. Tap a display pixel to open its physical address. The external debugger can patch any byte; the CPU still follows privilege rules.
- **OS** shows privilege, the syscall table, console output and execution trace. Changing environment reloads the same program while preserving the input switch.
- **Programs** includes direct and OS pixel writes, a live input loop, counter overflow/branching, a stack-based function that prints HI, the data sprite, and two panic experiments: a buggy driver that crashes the kernel and a hung loop that the watchdog stops.
- **Layers** explores 14 abstractions from controlled switches to functional software, each with a concrete pixel path, governing rule and fidelity boundary.
- **Logic & silicon** in Go deeper opens the gate bench, seeded from the last ALU operands. Flip operands, choose ADD/AND/OR/XOR, inspect all eight ripple-carry stages and their full-adder truth tables, and toggle a conceptual transistor switch.
- **Rewind** restores up to 512 prior complete machine states, including mid-syscall state. **Reset** restores the loaded image and keeps the hardware input switch position.

Programs save after successful assembly; reopening the app reloads that source with a fresh machine. Execution pauses when the app becomes inactive. The input button is a persistent digital latch that the program can sample.

## AT-8 machine

This app interprets a deliberately small custom ISA. It executes the bytes fetched from RAM, so self-modifying code and debugger patches have real modeled effects. It does not execute ARM instructions or enter the real iOS kernel.

| Region | Byte addresses | Role |
| --- | --- | --- |
| Code | 0–127 / 0x00–0x7F | Up to 32 four-byte instructions |
| Data / stack | 128–191 / 0x80–0xBF | Data bytes and a descending stack |
| Display | 192–255 / 0xC0–0xFF | 8×8 framebuffer, one byte per pixel |

Every instruction is `[opcode, operand A, operand B, reserved zero]`. Unused operands must be zero. Normal PC advance is four bytes. Registers R0–R3 are unsigned bytes; arithmetic wraps modulo 256. Zero means the last ALU result is zero. Carry means overflow for addition and borrow for subtraction/comparison. Branch targets must be aligned code addresses. Initial SP is 192; the first PUSH stores at 191.

Instructions: `NOP LDI MOV ADD SUB AND OR XOR SHL LD ST LDX STX CMP JMP JZ JNZ PUSH POP CALL RET IN OUT SYS HALT INC DEC`.

Assembly supports case-insensitive mnemonics/registers, case-sensitive labels, `;` comments, decimal/hex/binary bytes, forward branches, `.org` and `.byte`. Example:

```asm
LDI R0, 27    ; pixel 3,3
LDI R1, 1     ; cyan
SYS 1
HALT
```

`.org 128` starts a data section; `.byte 1, 2, 3` emits data into it. The assembler performs two passes and reports line-specific diagnostics. The loader copies a complete 256-byte image into RAM.

### Devices and OS

Pixel address is `192 + y × 8 + x`. Raw framebuffer memory preserves all eight bits; the renderer selects `byte & 7`. Palette: off, cyan, amber, violet, green, red, white, blue.

IN and OUT use isolated input port 0 and console port 1. User code cannot directly access the framebuffer or these ports. SYS enters a modeled kernel through separately observable phases. Services preserve condition flags. SYS arguments are captured at instruction execution; input is sampled when its driver runs.

| Service | Contract |
| --- | --- |
| SYS 1 | Draw pixel: R0 index 0–63; R1 palette 0–7 |
| SYS 2 | Fill display: R0 palette 0–7 |
| SYS 3 | Read hardware input into R0 |
| SYS 4 | Write printable ASCII or newline from R0 to console |
| SYS 5 | Read modeled microcycle count modulo 256 into R0 |
| SYS 6 | Exit process |
| SYS 7 | Draw pixel with SYS 1's index check deliberately missing; an index of 64 or more writes past RAM and panics |
| SYS 8 | Watchdog check-in; the first call enables monitoring, then each check-in must follow within 32 microcycles |

The stack and data share memory. A full sprite occupies all 64 data bytes; adding PUSH/CALL to its program can overwrite that sprite starting at address 191. Generated drawing loops use neither instruction. Kernel context is kept inside the model, so SYS does not consume the user stack.

### Faults and panics

A **fault** is a rule enforced on a program: a user write to display RAM, a bad syscall argument or a malformed instruction. A **kernel panic** means the kernel itself went wrong, so nothing above it can recover. `SYS 7` panics with a kernel data abort and reports the missing address as `far`, like a real panic log. Once `SYS 8` has checked in, a machine that goes 32 microcycles without another check-in panics with a watchdog timeout. Both stop the machine and set `fault`; `panic` adds the report. Rewind still works, and Reset reboots. The watchdog is a modeled timer, not a general interrupt controller.

### Model boundaries

AT-8 is one sequential interpreted CPU with one process and a tiny synchronous OS. Microcycle timing is educational. There is no virtual memory, cache, interrupt controller, scheduler, multicore execution, executable object format or external dynamic linker. The atlas explains where those abstractions belong. The gate bench uses ideal Boolean logic and a controlled-switch analogy; it does not solve transistor voltages, semiconductor physics, delay or power use.

## Design

`App/DesignSystem` copies Metro Station's reusable SwiftUI foundation, touch ownership, lens helper and Metal shader. The canonical token snapshot is in `Documentation/metro-station-design-tokens.json`. The app uses its gridded canvas, metal surfaces, cyan actions, amber execution state, technical captions, serif interpretation and floating native Liquid Glass controls. The hero is a rectangular display instrument suited to the computer model.

Direct manipulators own touches that start inside them; scroll outside them. Native stepper alternatives accompany bit and canvas editing. Panels honor Reduce Transparency and Increased Contrast; the app uses no continuous decorative animation or sensor effects. Full physical accessibility/haptic validation is still separate from simulator checks.

## Build

Open `AssemblerToy.xcodeproj` and choose the `AssemblerToy` scheme. Target: iPhone, iOS 27+, portrait/landscape. Bundle ID: `com.utkarsh.assemblertoy`. Version 1.0, build 6. Regenerate with `xcodegen generate` after editing `project.yml`.

Portable core checks:

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/assembler-toy-clang-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/assembler-toy-module-cache \
  swift test --disable-sandbox \
  --scratch-path /private/tmp/assembler-toy-core-build \
  --cache-path /private/tmp/assembler-toy-swift-cache \
  -Xswiftc -module-cache-path \
  -Xswiftc /private/tmp/assembler-toy-module-cache
```

Build 6 replaces the rejected large bottom controls with a compact transport and an Execution controls sheet. Guide uses one Back/Restart/Next row, with Next instruction in the same slot after completion; accessibility text sizes use icon controls with full spoken labels and one-column context. All 46 native model/session cases passed on the unchanged build 6 sources. The final signed phone artifact is installed and foreground activated, with a later process query confirming it in the final container; the user called the compact bottom controls “Much better.” Six focused simulator UI flows remain incomplete: two older exact-label waiter failures are preserved, and the corrected run’s final outcomes were unavailable after interruption. The resumed compilation succeeded; an initial simulator-runtime boot failure was followed by runtime recovery, and the final scoped manual review is pending. Screenshots, accepted compact-footer feedback and diagnostics retain their specific scope in `Documentation/Ergonomics/audit.json`; final evidence is in `Documentation/QA.md` and `Documentation/QA/ergonomics-build6-documentation-review-receipt.json`.

Historical build 4 passed all 42 native session/restoration/guided model cases. All four guided UI flows passed across scoped runs. Its signed Release artifact, `Build/AssemblerToy-build4-final.app`, was installed and launched on the connected iPhone 15 Pro Max (iOS 27.2), with a subsequent process query confirming PID 10081. Its signature and exact copy parity are verified. Earlier artifacts and diagnostic results remain preserved. See `Documentation/QA.md` for observed outcomes and `Documentation/QA` for screenshots, signing evidence and source parity.

Apple API references: [native Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [Canvas](https://developer.apple.com/documentation/swiftui/canvas). Interactive controls are separate SwiftUI buttons rather than inaccessible Canvas-only hit regions.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
