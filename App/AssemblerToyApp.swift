import SwiftUI

@main
struct AssemblerToyApp: App {
    var body: some Scene {
        WindowGroup {
            WorkbenchView()
                .preferredColorScheme(.dark)
                .tint(InstrumentPalette.actionCyan)
        }
    }
}
