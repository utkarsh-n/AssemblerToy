import Foundation

/// A bounded sampling displacement for metal detail behind a stationary lens.
/// This is a visual refraction cue, not a ray-traced optical material model.
public enum LensRefraction {
    /// The outer 18% of the lens radius smoothly releases the displacement.
    public static let rimStart: Double = 0.82
    public static let curvature: Double = 0.32
    /// Chromatic detail begins outside the central readout region and peaks in
    /// diagonal arcs before releasing smoothly at the circular rim.
    public static let chromaticInnerStart: Double = 0.52
    public static let chromaticPeakRadius: Double = 0.82

    /// Radially clamps gravity to the unit disk, preserving its direction, then
    /// enhances moderate tilt with 2g / (1 + |g|²). Magnitude remains at most one.
    /// Pass enabled=false for Reduce Motion or a static presentation.
    public static func enhancedTilt(
        x: Double,
        y: Double,
        enabled: Bool = true
    ) -> (x: Double, y: Double) {
        guard enabled, x.isFinite, y.isFinite else { return (0, 0) }
        let largest = max(abs(x), abs(y))
        guard largest > 0 else { return (0, 0) }

        // Scale before finding magnitude so even hostile finite vectors cannot
        // overflow. Small inputs retain their original precision.
        let scaledX = x / largest
        let scaledY = y / largest
        let scaledMagnitude = hypot(scaledX, scaledY)
        let boundedX: Double
        let boundedY: Double
        if largest > 1 / scaledMagnitude {
            boundedX = scaledX / scaledMagnitude
            boundedY = scaledY / scaledMagnitude
        } else {
            boundedX = x
            boundedY = y
        }
        let gain = 2 / (1 + boundedX * boundedX + boundedY * boundedY)
        return (boundedX * gain, boundedY * gain)
    }

    /// Maximum sampling shift in points for a gauge diameter measured in points.
    /// A 322-point gauge permits 8.05 points, with a global 9.5-point ceiling.
    public static func maximumShift(diameter: Double) -> Double {
        guard diameter.isFinite, diameter > 0 else { return 0 }
        return min(9.5, 0.025 * diameter)
    }

    /// Local coordinates are relative to the lens center and divided by its
    /// radius. The bow preserves broad interior distortion; a quintic feather
    /// joins it with continuous first and second derivatives at the rim.
    /// Outside the unit disk, malformed coordinates, and the rim itself are zero.
    public static func weight(normalizedX: Double, normalizedY: Double) -> Double {
        guard normalizedX.isFinite, normalizedY.isFinite else { return 0 }
        let radius = hypot(normalizedX, normalizedY)
        guard radius < 1 else { return 0 }
        let bow = 1 - curvature * radius * radius
        guard radius > rimStart else { return bow }
        let progress = (radius - rimStart) / (1 - rimStart)
        let remaining = 1 - progress
        // Factored 1 - smootherstep keeps small values stable near the rim.
        let feather = remaining * remaining * remaining
            * (1 + 3 * progress + 6 * progress * progress)
        return bow * feather
    }

    /// Returns a positive displacement vector in points. A sampling shader may
    /// subtract this vector to make the apparent detail move with positive tilt.
    /// The surrounding lens frame and its overlaid controls need no translation.
    public static func sampleOffset(
        normalizedX: Double,
        normalizedY: Double,
        gravityX: Double,
        gravityY: Double,
        diameter: Double,
        enabled: Bool = true
    ) -> (x: Double, y: Double) {
        let tilt = enhancedTilt(x: gravityX, y: gravityY, enabled: enabled)
        let amount = maximumShift(diameter: diameter)
            * weight(normalizedX: normalizedX, normalizedY: normalizedY)
        return (tilt.x * amount, tilt.y * amount)
    }

    /// Total red-to-blue sampling separation in points, before tilt and edge
    /// weighting. This is one point at a 322-point gauge, capped at 1.2 points.
    public static func maximumChannelSplit(diameter: Double) -> Double {
        guard diameter.isFinite, diameter > 0 else { return 0 }
        return min(1.2, diameter / 322)
    }

    /// Smooth diagonal edge arcs: a quintic radial window rises from .52 to .82
    /// radius, then falls to zero at the rim; sin²(2θ) suppresses the axial arcs.
    /// The central disk is exactly zero, avoiding an angular singularity there.
    /// Both radial joins have continuous first and second derivatives.
    public static func chromaticWeight(normalizedX: Double, normalizedY: Double) -> Double {
        guard normalizedX.isFinite, normalizedY.isFinite else { return 0 }
        let radius = hypot(normalizedX, normalizedY)
        guard radius > chromaticInnerStart, radius < 1 else { return 0 }
        let radial: Double
        if radius < chromaticPeakRadius {
            let progress = (radius - chromaticInnerStart) / (chromaticPeakRadius - chromaticInnerStart)
            radial = progress * progress * progress * (10 + progress * (-15 + 6 * progress))
        } else {
            let progress = (radius - chromaticPeakRadius) / (1 - chromaticPeakRadius)
            let remaining = 1 - progress
            radial = remaining * remaining * remaining * (1 + 3 * progress + 6 * progress * progress)
        }
        let diagonal = 2 * (normalizedX / radius) * (normalizedY / radius)
        return min(1, max(0, radial * diagonal * diagonal))
    }

    /// One channel's offset relative to the achromatic sample in points. Sample
    /// red at base+offset, green at base, and blue at base-offset. Thus the TOTAL
    /// red-to-blue split is bounded by maximumChannelSplit, not twice that limit.
    /// Strength is proportional to enhanced tilt magnitude; neutral tilt and
    /// Reduce Motion produce no channel separation.
    public static func chromaticOffset(
        normalizedX: Double,
        normalizedY: Double,
        gravityX: Double,
        gravityY: Double,
        diameter: Double,
        enabled: Bool = true
    ) -> (x: Double, y: Double) {
        let tilt = enhancedTilt(x: gravityX, y: gravityY, enabled: enabled)
        let amount = 0.5 * maximumChannelSplit(diameter: diameter)
            * chromaticWeight(normalizedX: normalizedX, normalizedY: normalizedY)
        return (tilt.x * amount, tilt.y * amount)
    }

}
