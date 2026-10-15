import SwiftUI

// Metro Station design foundations. Minimum deployment: iOS 26.
// Add every Swift file in this folder and InstrumentLensOptics.metal to the
// application target. Domain clocks, sensor permission/mapping and haptics
// stay with the host app. This file introduces no audio or motion manager.

public enum InstrumentPalette {
    public static let canvas = Color(red: 0.025, green: 0.042, blue: 0.058)
    public static let content = Color(red: 0.045, green: 0.070, blue: 0.087)
    public static let actionCyan = Color(red: 0.34, green: 0.93, blue: 0.96)
    public static let actionAmber = Color(red: 1, green: 0.74, blue: 0.37)
    public static let instrumentCyan = Color(red: 0.32, green: 0.91, blue: 0.96)
    public static let instrumentAmber = Color(red: 1, green: 0.72, blue: 0.31)
    public static let displayInk = Color(red: 0.91, green: 0.95, blue: 0.97)
    public static let secondaryInk = Color(red: 0.60, green: 0.69, blue: 0.73)
    public static let wave = Color(red: 0.31, green: 0.86, blue: 1)
    public static let waveDepth = Color(red: 0.21, green: 0.40, blue: 1)
    public static let spectrum = Color(red: 0.76, green: 0.57, blue: 1)
    public static let spectrumDepth = Color(red: 0.96, green: 0.36, blue: 0.84)
    public static let carrier = Color(red: 1, green: 0.73, blue: 0.34)
}

public enum InstrumentMetrics {
    public static let panelInset: CGFloat = 16
    public static let panelRadius: CGFloat = 22
    public static let controlTarget: CGFloat = 44
    public static let stepperHeight: CGFloat = 48
    public static let gridSpacing: CGFloat = 28
    public static let lensDiameterRatio: CGFloat = 0.76
    public static let lensOpacity: Double = 0.48
}

public struct InstrumentDesignBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack {
            InstrumentPalette.canvas
            if !reduceTransparency {
                RadialGradient(colors: [InstrumentPalette.actionCyan.opacity(0.085), .clear],
                               center: .topTrailing, startRadius: 5, endRadius: 620)
            }
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: 0.0, through: size.width, by: InstrumentMetrics.gridSpacing) {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, through: size.height, by: InstrumentMetrics.gridSpacing) {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

public struct InstrumentContentPanel<Content: View>: View {
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(InstrumentMetrics.panelInset)
            .background(InstrumentPalette.content.opacity(reduceTransparency ? 1 : 0.85),
                        in: .rect(cornerRadius: InstrumentMetrics.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InstrumentMetrics.panelRadius)
                    .stroke(.white.opacity(contrast == .increased ? 0.20 : 0.09), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

@available(iOS 26.0, *)
public struct InstrumentGlassIconButton: View {
    private let symbol: String
    private let label: String
    private let accent: Color
    private let action: () -> Void

    public init(_ symbol: String, label: String,
                accent: Color = InstrumentPalette.actionCyan,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.accent = accent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
                .frame(width: InstrumentMetrics.controlTarget, height: InstrumentMetrics.controlTarget)
                .contentShape(.circle)
                .glassEffect(.regular.tint(accent.opacity(0.08)).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityIdentifier("instrumentIconButton.\(label)")
        .accessibilityAction(.default, action)
        .instrumentControlOwnsTouches(identifier: "glassIconButton")
    }
}

public struct InstrumentMetricReadout: View {
    private let label: String
    private let value: String
    private let unit: String
    private let color: Color

    public init(_ label: String, value: String, unit: String,
                color: Color = InstrumentPalette.actionCyan) {
        self.label = label
        self.value = value
        self.unit = unit
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(InstrumentPalette.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }
}

public struct InstrumentParameterStepper: View {
    @Binding private var value: Int
    private let label: String
    private let unit: String
    private let range: ClosedRange<Int>
    private let onEditingChanged: (Bool) -> Void
    private let onAcceptedChange: (Int) -> Void
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0
    @ScaledMetric(relativeTo: .body) private var valueSize = 18.0
    @Environment(\.dynamicTypeSize) private var dynamicType

    public init(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>,
                unit: String, onEditingChanged: @escaping (Bool) -> Void = { _ in },
                onAcceptedChange: @escaping (Int) -> Void = { _ in }) {
        self.label = label
        self._value = value
        self.range = range
        self.unit = unit
        self.onEditingChanged = onEditingChanged
        self.onAcceptedChange = onAcceptedChange
    }

    public var body: some View {
        Stepper {
            Group {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        parameterLabel
                        parameterValue
                    }
                } else {
                    HStack(spacing: 10) {
                        parameterLabel
                        parameterValue
                    }
                }
            }
        } onIncrement: {
            adjust(1)
        } onDecrement: {
            adjust(-1)
        } onEditingChanged: { editing in
            onEditingChanged(editing)
        }
        .frame(minHeight: InstrumentMetrics.stepperHeight)
        .padding(.horizontal, 14)
        .background(InstrumentPalette.content.opacity(0.85), in: .capsule)
        .overlay {
            Capsule().strokeBorder(InstrumentPalette.actionCyan.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .instrumentControlOwnsTouches(identifier: "parameterStepper")
        .accessibilityHint("Hold plus or minus for repeated adjustments.")
    }

    private var parameterLabel: some View {
        Text(label)
            .font(.system(size: labelSize, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(InstrumentPalette.secondaryInk)
    }

    private var parameterValue: some View {
        Text("\(value) \(unit)")
            .font(.system(size: valueSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(InstrumentPalette.actionCyan)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func adjust(_ direction: Int) {
        guard (direction > 0 && value < range.upperBound)
                || (direction < 0 && value > range.lowerBound) else { return }
        value += direction
        onAcceptedChange(value)
    }
}

public struct InstrumentLargeReadout: View {
    private let diameter: CGFloat
    private let value: String
    private let unit: String
    private let meaning: String?
    private let spokenLabel: String
    @ScaledMetric(relativeTo: .caption2) private var unitSize = 11.0
    @Environment(\.dynamicTypeSize) private var dynamicType

    public init(diameter: CGFloat, value: String, unit: String,
                meaning: String? = nil, spokenLabel: String) {
        self.diameter = max(1, diameter.isFinite ? diameter : 1)
        self.value = value
        self.unit = unit
        self.meaning = meaning
        self.spokenLabel = spokenLabel
    }

    public var body: some View {
        ZStack {
            Text(value)
                .font(.system(size: diameter * 0.23, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(InstrumentPalette.displayInk)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(width: diameter * 0.64)
                .position(x: diameter / 2, y: diameter * 0.52)
            if !dynamicType.isAccessibilitySize {
                Text(unit)
                    .font(.system(size: unitSize, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.68))
                    .position(x: diameter / 2, y: diameter * 0.665)
            }
            if let meaning {
                Text(meaning)
                    .font(.system(.subheadline, design: .serif, weight: .medium))
                    .italic()
                    .foregroundStyle(InstrumentPalette.instrumentCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: diameter * 0.64)
                    .position(x: diameter / 2, y: diameter * (dynamicType.isAccessibilitySize ? 0.79 : 0.745))
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue([value, unit, meaning ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// Face must be pure SwiftUI drawing content, preferably Canvas or Shapes.
// UIKit/AppKit-backed subviews cannot be assumed to participate in layerEffect.
// Supply filtered screen-space tilt and a scale sampled from the host's clock.
// This presentation component does not own the host's dial gestures.
@available(iOS 26.0, *)
public struct InstrumentLensSurface<Face: View, Readout: View>: View {
    private let diameter: CGFloat
    private let inputScale: Double
    private let filteredTilt: SIMD2<Double>
    private let motionActive: Bool
    private let face: Face
    private let readout: Readout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    public init(diameter: CGFloat, radiusScale: Double = 1,
                filteredTilt: SIMD2<Double> = .zero, motionActive: Bool = false,
                @ViewBuilder face: () -> Face, @ViewBuilder readout: () -> Readout) {
        self.diameter = max(1, diameter.isFinite ? diameter : 1)
        self.inputScale = radiusScale.isFinite ? min(1.09, max(0.92, radiusScale)) : 1
        self.filteredTilt = filteredTilt
        self.motionActive = motionActive
        self.face = face()
        self.readout = readout()
    }

    private var enabled: Bool {
        motionActive && !reduceMotion && !reduceTransparency && scenePhase == .active
    }
    private var scale: Double { reduceMotion || scenePhase != .active ? 1 : inputScale }
    private var radius: CGFloat { diameter * 0.38 * scale }
    private var enhanced: (x: Double, y: Double) {
        LensRefraction.enhancedTilt(x: filteredTilt.x, y: filteredTilt.y, enabled: enabled)
    }
    private var samplingBound: CGFloat {
        LensRefraction.maximumShift(diameter: diameter)
            + LensRefraction.maximumChannelSplit(diameter: diameter) * 0.5
    }

    public var body: some View {
        ZStack {
            face
                .frame(width: diameter, height: diameter)
                .layerEffect(shader, maxSampleOffset: CGSize(width: samplingBound, height: samplingBound),
                             isEnabled: enabled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: diameter * InstrumentMetrics.lensDiameterRatio,
                       height: diameter * InstrumentMetrics.lensDiameterRatio)
                .glassEffect(.clear, in: .circle)
                .scaleEffect(scale, anchor: .center)
                .opacity(reduceTransparency ? 1 : InstrumentMetrics.lensOpacity)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if enabled { edgeReflection }
            readout.frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .transaction { $0.animation = nil }
    }

    private var shader: Shader {
        ShaderLibrary.instrumentLensOptics(
            .float2(Float(diameter / 2), Float(diameter / 2)),
            .float(Float(radius)),
            .float2(Float(enhanced.x), Float(enhanced.y)),
            .float(Float(LensRefraction.maximumShift(diameter: diameter))),
            .float(Float(LensRefraction.rimStart)),
            .float(Float(LensRefraction.curvature)),
            .float(Float(LensRefraction.maximumChannelSplit(diameter: diameter))),
            .float(Float(LensRefraction.chromaticInnerStart)),
            .float(Float(LensRefraction.chromaticPeakRadius))
        )
    }

    private var edgeReflection: some View {
        Canvas { context, _ in
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let rim = radius * 0.985
            let angle = -90 + enhanced.x * 70 + enhanced.y * 20
            let start = angle - 38
            let end = angle + 38
            let arc = Path { path in
                path.addArc(center: center, radius: rim, startAngle: .degrees(start),
                            endAngle: .degrees(end), clockwise: false)
            }
            let a = CGPoint(x: center.x + rim * cos(start * .pi / 180),
                            y: center.y + rim * sin(start * .pi / 180))
            let b = CGPoint(x: center.x + rim * cos(end * .pi / 180),
                            y: center.y + rim * sin(end * .pi / 180))
            context.stroke(arc, with: .linearGradient(Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.085), location: 0.5),
                .init(color: .clear, location: 1)
            ]), startPoint: a, endPoint: b), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

