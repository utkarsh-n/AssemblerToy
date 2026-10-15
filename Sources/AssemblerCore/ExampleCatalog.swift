public enum ExampleCatalog {
    public static let examples: [MachineExample] = [
        MachineExample(
            id: "bare-pixel", name: "One pixel · bare metal",
            summary: "A store instruction drives a real byte in the model's display RAM.",
            goals: ["Follow assembly into four encoded bytes.", "Watch ST move a register onto the memory bus.", "See RAM address 219 become pixel 27."],
            source: """
            ; Bare metal writes framebuffer RAM directly.
            LDI R0, 3
            ST R0, 219
            HALT
            """, mode: .bareMetal),
        MachineExample(
            id: "os-pixel", name: "One pixel · through the OS",
            summary: "The same display byte is reached through a protected system call.",
            goals: ["R0 supplies pixel index 27; R1 supplies palette 3.", "Step through trap → kernel → driver → return.", "Compare the final display byte with the bare-metal program."],
            source: """
            ; SYS 1: draw pixel R0 using palette R1.
            LDI R0, 27
            LDI R1, 3
            SYS 1
            HALT
            """, mode: .user),
        MachineExample(
            id: "button-loop", name: "Switch → software → light",
            summary: "A live program reads the input switch and lights a pixel.",
            goals: ["Toggle the physical input switch while the loop runs.", "Trace the input driver return value into R0.", "Observe comparison, branch, and display output as one cause-and-effect chain."],
            source: """
            ; Toggle input during the loop: 0 = dark, 1 = violet.
            loop: SYS 3
            LDI R2, 0
            CMP R0, R2
            JZ dark
            LDI R1, 3
            JMP draw
            dark: LDI R1, 0
            draw: LDI R0, 27
            SYS 1
            JMP loop
            """, mode: .user),
        MachineExample(
            id: "counter-branch", name: "Count, wrap, branch",
            summary: "An eight-bit counter crosses 255 and takes a zero branch.",
            goals: ["Watch INC turn 255 into 0.", "Inspect the ALU's zero and carry flags.", "See a conditional branch select the visible outcome."],
            source: """
            LDI R0, 254
            count: INC R0
            JNZ count
            LDI R1, 5
            ST R1, 192
            HALT
            """, mode: .bareMetal),
        MachineExample(
            id: "stack-console", name: "A function says HI",
            summary: "CALL and RET use shared data RAM as a stack; SYS writes the console.",
            goals: ["Watch CALL push the byte address of the next instruction.", "Follow a subroutine into two console syscalls.", "Watch RET pop its return address and restore control."],
            source: """
            CALL greet
            HALT
            greet: PUSH R0
            LDI R0, 72
            SYS 4
            LDI R0, 73
            SYS 4
            POP R0
            RET
            """, mode: .user),
        MachineExample(
            id: "data-sprite", name: "A picture becomes a program",
            summary: "A 64-byte sprite in data RAM becomes a display through an assembly loop.",
            goals: ["Inspect .byte data alongside encoded instruction bytes.", "Follow LDX reading each palette index from data RAM.", "Watch the OS driver turn those values into a complete 8×8 picture."],
            source: """
            LDI R0, 0
            LDI R2, 128
            LDI R3, 64
            draw: LDX R1, R2
            SYS 1
            INC R0
            INC R2
            DEC R3
            JNZ draw
            HALT
            .org 128
            .byte 0,0,0,3,3,0,0,0
            .byte 0,0,3,3,3,3,0,0
            .byte 0,3,3,3,3,3,3,0
            .byte 3,3,3,3,3,3,3,3
            .byte 3,3,3,3,3,3,3,3
            .byte 0,3,3,3,3,3,3,0
            .byte 0,0,3,3,3,3,0,0
            .byte 0,0,0,3,3,0,0,0
            """, mode: .user),
        MachineExample(
            id: "kernel-panic", name: "Kernel panic · a buggy driver",
            summary: "A driver that skips one bounds check works until a bad index stops the whole machine.",
            goals: ["Watch SYS 7 draw pixel 27 exactly like SYS 1.", "Step the second call into its driver: index 70 means RAM[262], which does not exist.", "Change both SYS 7 lines to SYS 1 and run again: the kernel refuses index 70 with a fault, and nothing panics."],
            source: """
            ; SYS 7 is SYS 1 with its index check deliberately removed.
            LDI R0, 27
            LDI R1, 5
            SYS 7
            LDI R0, 70
            SYS 7
            HALT
            """, mode: .user),
        MachineExample(
            id: "watchdog-hang", name: "Watchdog · a hung machine",
            summary: "A loop checks in with the watchdog until the input switch makes it hang.",
            goals: ["Watch SYS 8 check in once per loop, well inside the 32-microcycle limit.", "Turn the input switch on: the program jumps into a loop that never checks in.", "Count the microcycles after the last check-in until the watchdog panics."],
            source: """
            ; Green means running. Turn the input switch on to hang.
            LDI R0, 4
            SYS 2
            loop: SYS 8
            SYS 3
            LDI R2, 0
            CMP R0, R2
            JZ loop
            hang: JMP hang
            """, mode: .user)
    ]
}
