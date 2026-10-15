#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

static float instrumentSmootherstep(float value) {
    float t = clamp(value, 0.0, 1.0);
    return t * t * t * (10.0 + t * (-15.0 + 6.0 * t));
}

// Only the metal/ticker Canvas enters this sampling layer. Native glass,
// foreground readout and controls remain separate, stationary siblings.
[[ stitchable ]] half4 instrumentLensOptics(
    float2 position, SwiftUI::Layer layer, float2 center, float radius, float2 tilt,
    float maximumShift, float rimStart, float curvature,
    float maximumChannelSplit, float chromaticInnerStart, float chromaticPeakRadius
) {
    if (radius <= 0.0 || maximumShift <= 0.0) return layer.sample(position);
    float2 local = (position - center) / radius;
    float r = length(local);
    if (r >= 1.0) return layer.sample(position);

    float t = clamp((r - rimStart) / (1.0 - rimStart), 0.0, 1.0);
    float remaining = 1.0 - t;
    float feather = remaining * remaining * remaining * (1.0 + 3.0 * t + 6.0 * t * t);
    float weight = feather * (1.0 - curvature * r * r);
    float2 boundedTilt = clamp(tilt, -1.0, 1.0);
    float2 source = position - boundedTilt * maximumShift * weight;
    half4 green = layer.sample(source);
    if (r <= chromaticInnerStart || maximumChannelSplit <= 0.0) return green;

    float radial = r <= chromaticPeakRadius
        ? instrumentSmootherstep((r - chromaticInnerStart) / (chromaticPeakRadius - chromaticInnerStart))
        : 1.0 - instrumentSmootherstep((r - chromaticPeakRadius) / (1.0 - chromaticPeakRadius));
    float diagonal = 2.0 * local.x * local.y / (r * r);
    // The supplied bound is total R-to-B separation; each side uses half.
    float2 split = boundedTilt * (0.5 * maximumChannelSplit * radial * diagonal * diagonal);
    half4 red = layer.sample(source + split);
    half4 blue = layer.sample(source - split);
    // Samples are already premultiplied. Union alpha preserves the thin
    // colored fringe on transparent ink without double-premultiplication.
    half alpha = max(red.a, max(green.a, blue.a));
    half3 rgb = min(half3(red.r, green.g, blue.b), half3(alpha));
    return half4(rgb, alpha);
}
