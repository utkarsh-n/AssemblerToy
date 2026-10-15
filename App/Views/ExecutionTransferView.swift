import SwiftUI

/// A stable route and explanation: no scrolling, flashing or decorative motion
/// implies an extra machine operation.
struct ExecutionTransferView: View {
    let cue: ExecutionCue
    let identifier: String
    @ScaledMetric(relativeTo: .caption) private var nodeHeight = 40.0
    @ScaledMetric(relativeTo: .caption) private var detailHeight = 34.0

    init(cue: ExecutionCue, identifier: String = "executionTransfer") {
        self.cue = cue
        self.identifier = identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                node(cue.source, symbol: cue.sourceSymbol)
                VStack(spacing: 3) {
                    Text(cue.action)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(InstrumentPalette.actionAmber)
                    Image(systemName: "arrow.right")
                        .font(.caption).foregroundStyle(InstrumentPalette.secondaryInk)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: nodeHeight)
                node(cue.destination, symbol: cue.destinationSymbol)
            }
            Text(cue.detail)
                .font(.caption).foregroundStyle(InstrumentPalette.displayInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: detailHeight, maxHeight: detailHeight, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cue.source). \(cue.action). \(cue.destination). \(cue.detail)")
        .accessibilityIdentifier(identifier)
    }

    private func node(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption)
                .foregroundStyle(InstrumentPalette.actionCyan).accessibilityHidden(true)
            Text(title)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(InstrumentPalette.displayInk)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: nodeHeight, maxHeight: nodeHeight)
        .padding(.horizontal, 6)
        .background(.black.opacity(0.18), in: .rect(cornerRadius: 9))
    }
}
