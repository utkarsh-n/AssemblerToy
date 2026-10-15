import SwiftUI
import Observation
import AssemblerCore

@MainActor @Observable
final class MachineSession {
    var machine: Machine
    var program: Program
    var source: String
    var title: String
    var running = false {
        didSet {
            if running != oldValue { clearPlaybackPacing() }
        }
    }
    static let playbackSpeedRange = 0.25...4.0
    private var requestedPlaybackSpeed = 1.0
    private(set) var isSpeedSettling = false
    /// Requested teaching pace: 1× presents two individual microcycles per second.
    var playbackSpeed: Double {
        get { requestedPlaybackSpeed }
        set {
            guard newValue.isFinite, Self.playbackSpeedRange.contains(newValue),
                  newValue != requestedPlaybackSpeed else { return }
            requestedPlaybackSpeed = newValue
            preferences.set(newValue, forKey: "AssemblerToy.playbackSpeed")
            if running {
                transitionStartSpeed = effectivePlaybackSpeed
                transitionElapsed = 0
                isSpeedSettling = true
            } else {
                clearPlaybackPacing()
            }
        }
    }
    var cyclesPerSecond: Double { playbackSpeed * 2 }
    var breakpoints: Set<Int> = []
    @ObservationIgnored private(set) var history: [Machine] = []
    private(set) var canRewind = false
    private(set) var guidedInstruction: GuidedInstruction?
    /// One actual interpreter transition powers the visible causal affordances.
    /// Its lifetime follows the presented machine, independent of undo capacity.
    private(set) var lastExecutionStep: GuidedInstructionStep?
    var notice: String?
    var selectedAddress = 192
    var selectedRegister = 0
    private let preferences: UserDefaults
    private var skipBreakpoint: Int?
    private var stoppedBreakpoint: Int?
    // Fractional pacing stays out of Observation. Panels publish only actual
    // machine phases and the beginning/end of a requested speed transition.
    @ObservationIgnored private var playbackPhase = 0.0
    @ObservationIgnored private var effectivePlaybackSpeed = 1.0
    @ObservationIgnored private var transitionStartSpeed = 1.0
    @ObservationIgnored private var transitionElapsed = 0.45
    @ObservationIgnored private var guidedHistoryBaseline: [Machine]?
    private static let speedTransitionDuration = 0.45
    private static let maximumPlaybackElapsed = 0.1

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let example = ExampleCatalog.examples.first(where: { $0.id == "data-sprite" }) ?? ExampleCatalog.examples[0]
        let saved = preferences.string(forKey: "AssemblerToy.source")
        let savedMode = preferences.bool(forKey: "AssemblerToy.bareMetal") ? ExecutionMode.bareMetal : .user
        let restored = saved.flatMap { try? Assembler.assemble($0) }
        let initialProgram = restored ?? (try! Assembler.assemble(example.source))
        program = initialProgram
        source = saved != nil && restored != nil ? saved! : example.source
        title = restored == nil ? example.name : "Your program"
        machine = Machine(program: initialProgram, mode: restored == nil ? example.mode : savedMode)
        if let savedSpeed = preferences.object(forKey: "AssemblerToy.playbackSpeed") as? Double,
           savedSpeed.isFinite, Self.playbackSpeedRange.contains(savedSpeed) {
            requestedPlaybackSpeed = savedSpeed
        }
        clearPlaybackPacing()
    }

    func load(_ example: MachineExample) {
        title = example.name
        do { try assemble(example.source, mode: example.mode) } catch { notice = error.localizedDescription }
    }

    func assemble(_ text: String, mode: ExecutionMode) throws {
        let assembled = try Assembler.assemble(text)
        endGuidedInstruction()
        running = false
        source = text
        program = assembled
        machine = Machine(program: assembled, mode: mode)
        lastExecutionStep = nil
        clearHistory()
        breakpoints.removeAll()
        clearBreakpointContinuation()
        notice = "Assembled \(assembled.instructions.count) instructions. Loaded into RAM."
        preferences.set(text, forKey: "AssemblerToy.source")
        preferences.set(mode == .bareMetal, forKey: "AssemblerToy.bareMetal")
    }

    func checkpoint() {
        history.append(machine)
        if history.count > 512 { history.removeFirst(history.count - 512) }
        if !canRewind { canRewind = true }
    }

    func step(micro: Bool) {
        guard guidedInstruction == nil else {
            notice = "Use Next microstep while the instruction guide is open."
            return
        }
        running = false
        clearBreakpointContinuation()
        guard !machine.halted, machine.fault == nil else { return }
        checkpoint()
        if micro {
            performMicrostep()
        } else {
            // Match Machine.stepInstruction's completion rule and safety bound,
            // retaining one undo checkpoint for the entire instruction.
            let target = machine.instructionCount + 1
            for _ in 0..<16 {
                guard !machine.isFinished, machine.instructionCount < target else { break }
                performMicrostep()
            }
        }
    }

    func tick() {
        guard guidedInstruction == nil else { running = false; return }
        guard running else { return }
        guard !machine.isFinished else { running = false; return }
        if machine.nextPhase == .fetch, breakpoints.contains(machine.pc), skipBreakpoint != machine.pc {
            running = false
            stoppedBreakpoint = machine.pc
            notice = "Breakpoint at 0x\(ToyInk.hex(machine.pc)). Tap Run to continue."
            return
        }
        checkpoint()
        performMicrostep()
        if machine.nextPhase != .fetch { skipBreakpoint = nil }
        if machine.halted || machine.fault != nil { running = false }
    }

    /// Accept monotonic elapsed time from the view's low-frequency scheduler.
    /// A delayed callback contributes at most 0.1 seconds and can publish only
    /// one microcycle, so a stall never produces a hidden batch or catch-up burst.
    func advancePlayback(elapsed: Double) {
        guard guidedInstruction == nil else { running = false; return }
        guard running, elapsed.isFinite, elapsed > 0 else { return }
        guard !machine.isFinished else { running = false; return }
        let delta = min(elapsed, Self.maximumPlaybackElapsed)
        playbackPhase += integratedPlaybackSpeed(over: delta) * 2
        guard playbackPhase >= 1 - 1e-10 else { return }
        playbackPhase = max(0, playbackPhase - 1)
        tick()
    }

    func toggleRun() {
        guard guidedInstruction == nil else {
            notice = "Finish or close the instruction guide before running."
            return
        }
        if running { running = false; clearBreakpointContinuation(); return }
        guard !machine.halted, machine.fault == nil else { notice = "Reset the machine to run again."; return }
        // Only a deliberate continuation from a breakpoint bypasses that stop.
        // The first Run after reset must still honor a breakpoint at PC zero.
        skipBreakpoint = stoppedBreakpoint == machine.pc && machine.nextPhase == .fetch ? machine.pc : nil
        stoppedBreakpoint = nil
        notice = nil
        running = true
    }

    func rewind() {
        endGuidedInstruction()
        running = false
        clearBreakpointContinuation()
        if let previous = history.popLast() { machine = previous; notice = nil }
        lastExecutionStep = nil
        if history.isEmpty && canRewind { canRewind = false }
    }

    func reset() {
        endGuidedInstruction()
        running = false
        machine.reset()
        lastExecutionStep = nil
        clearHistory()
        clearBreakpointContinuation()
        notice = nil
    }

    func changeMode(_ mode: ExecutionMode) {
        endGuidedInstruction()
        running = false
        machine.load(program: program, mode: mode)
        lastExecutionStep = nil
        clearHistory()
        clearBreakpointContinuation()
        preferences.set(mode == .bareMetal, forKey: "AssemblerToy.bareMetal")
        notice = mode == .bareMetal ? "Bare metal: the program owns the devices." : "User process: device access goes through SYS."
    }

    func writeByte(at address: Int, value: UInt8) {
        running = false
        var edited = machine
        do {
            try edited.editMemory(at: address, value: value)
            endGuidedInstruction()
            checkpoint()
            machine = edited
            lastExecutionStep = nil
            notice = "Probe wrote 0x\(ToyInk.hex(Int(value))) at 0x\(ToyInk.hex(address))."
        } catch { notice = error.localizedDescription }
    }

    func writeRegister(_ register: Int, value: UInt8) {
        running = false
        var edited = machine
        do {
            try edited.editRegister(register, value: value)
            endGuidedInstruction()
            checkpoint()
            machine = edited
            lastExecutionStep = nil
        } catch { notice = error.localizedDescription }
    }

    func setInput(_ value: UInt8) {
        guard value != machine.inputValue else { return }
        endGuidedInstruction()
        checkpoint()
        machine.setInput(value)
        lastExecutionStep = nil
    }

    func startGuidedInstruction() {
        endGuidedInstruction()
        running = false
        clearPlaybackPacing()
        clearBreakpointContinuation()
        guard !machine.isFinished else {
            notice = "Reset the machine before starting another instruction guide."
            return
        }
        guidedHistoryBaseline = history
        guidedInstruction = GuidedInstruction(machine: machine)
        notice = nil
    }

    /// Advance one real microphase and capture its actual trace and full snapshots.
    func advanceGuidedInstruction() {
        guard var guide = guidedInstruction, guide.canAdvance else { return }
        var advanced = machine
        guard let event = advanced.step() else { return }
        let previous = machine
        checkpoint()
        machine = advanced
        let step = GuidedInstructionStep(id: guide.steps.count + 1, before: previous, after: advanced,
                                         event: event, instructionAddress: guide.instructionAddress)
        guide.append(step)
        lastExecutionStep = step
        guidedInstruction = guide
        notice = nil
    }

    func previousGuidedStep() {
        guard var guide = guidedInstruction, let previous = guide.removeLastStep() else { return }
        machine = previous.before
        restoreGuidedHistory(guide)
        guidedInstruction = guide
        lastExecutionStep = guide.latestStep
        clearPlaybackPacing()
        notice = nil
    }

    func restartGuidedInstruction() {
        guard var guide = guidedInstruction else { return }
        machine = guide.baseline
        guide.restart()
        restoreGuidedHistory(guide)
        guidedInstruction = guide
        lastExecutionStep = nil
        clearPlaybackPacing()
        notice = nil
    }

    /// Closing retains exactly the currently presented machine and undo history.
    func endGuidedInstruction() {
        guard guidedInstruction != nil else { return }
        running = false
        clearPlaybackPacing()
        guidedInstruction = nil
        guidedHistoryBaseline = nil
    }

    private func restoreGuidedHistory(_ guide: GuidedInstruction) {
        let restored = (guidedHistoryBaseline ?? []) + guide.steps.map(\.before)
        history = Array(restored.suffix(512))
        let available = !history.isEmpty
        if canRewind != available { canRewind = available }
    }

    /// Advance the interpreter once; never infer effects from source text.
    private func performMicrostep() {
        let before = machine
        guard let event = machine.step() else { return }
        let address = before.nextPhase == .fetch ? before.pc
            : (before.currentInstructionAddress ?? before.pc)
        lastExecutionStep = GuidedInstructionStep(id: Int(truncatingIfNeeded: machine.cycleCount),
                                                  before: before, after: machine, event: event,
                                                  instructionAddress: address)
    }

    private func clearPlaybackPacing() {
        playbackPhase = 0
        effectivePlaybackSpeed = playbackSpeed
        transitionStartSpeed = playbackSpeed
        transitionElapsed = Self.speedTransitionDuration
        if isSpeedSettling { isSpeedSettling = false }
    }

    /// Integrate a smoothstep ramp exactly, retaining the fraction of the
    /// current cycle when the requested speed changes or reverses direction.
    private func integratedPlaybackSpeed(over delta: Double) -> Double {
        guard isSpeedSettling else { return effectivePlaybackSpeed * delta }
        let duration = Self.speedTransitionDuration
        let start = transitionElapsed
        let end = min(start + delta, duration)
        let startFraction = start / duration
        let endFraction = end / duration
        func smoothstepIntegral(_ fraction: Double) -> Double {
            let cube = fraction * fraction * fraction
            return cube - 0.5 * cube * fraction
        }
        let difference = playbackSpeed - transitionStartSpeed
        let rampIntegral = transitionStartSpeed * (end - start)
            + difference * duration * (smoothstepIntegral(endFraction) - smoothstepIntegral(startFraction))
        let remainder = delta - (end - start)
        let fractionSquared = endFraction * endFraction
        effectivePlaybackSpeed = transitionStartSpeed
            + difference * fractionSquared * (3 - 2 * endFraction)
        transitionElapsed = end
        if end >= duration - 1e-10 {
            effectivePlaybackSpeed = playbackSpeed
            if isSpeedSettling { isSpeedSettling = false }
        }
        return rampIntegral + playbackSpeed * max(0, remainder)
    }

    private func clearBreakpointContinuation() {
        skipBreakpoint = nil
        stoppedBreakpoint = nil
    }

    private func clearHistory() {
        history.removeAll()
        if canRewind { canRewind = false }
    }
}
