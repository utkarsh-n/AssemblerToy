import AppKit

let side = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()
let canvas = NSRect(x: 0, y: 0, width: side, height: side)
NSGradient(colors: [NSColor(red: 0.08, green: 0.13, blue: 0.16, alpha: 1), NSColor(red: 0.015, green: 0.025, blue: 0.035, alpha: 1)])!.draw(in: canvas, angle: -50)
NSColor.white.withAlphaComponent(0.045).setStroke()
let grid = NSBezierPath()
grid.lineWidth = 1
for i in stride(from: 0, through: side, by: 56) {
    grid.move(to: NSPoint(x: i, y: 0)); grid.line(to: NSPoint(x: i, y: side))
    grid.move(to: NSPoint(x: 0, y: i)); grid.line(to: NSPoint(x: side, y: i))
}
grid.stroke()
let cyan = NSColor(red: 0.34, green: 0.93, blue: 0.96, alpha: 1)
let amber = NSColor(red: 1, green: 0.74, blue: 0.37, alpha: 1)
for i in 0..<6 {
    let offset = 275 + i * 90
    cyan.withAlphaComponent(0.7).setStroke()
    let traces = NSBezierPath()
    traces.lineWidth = 12
    traces.lineCapStyle = .round
    traces.move(to: NSPoint(x: offset, y: 100)); traces.line(to: NSPoint(x: offset, y: 220))
    traces.move(to: NSPoint(x: offset, y: 804)); traces.line(to: NSPoint(x: offset, y: 924))
    traces.move(to: NSPoint(x: 100, y: offset)); traces.line(to: NSPoint(x: 220, y: offset))
    traces.move(to: NSPoint(x: 804, y: offset)); traces.line(to: NSPoint(x: 924, y: offset))
    traces.stroke()
}
let chip = NSBezierPath(roundedRect: NSRect(x: 190, y: 190, width: 644, height: 644), xRadius: 86, yRadius: 86)
NSGradient(colors: [NSColor(red: 0.19, green: 0.23, blue: 0.25, alpha: 1), NSColor(red: 0.035, green: 0.05, blue: 0.06, alpha: 1)])!.draw(in: chip, angle: -55)
chip.lineWidth = 5
NSColor.white.withAlphaComponent(0.28).setStroke(); chip.stroke()
let inset = NSBezierPath(roundedRect: NSRect(x: 243, y: 243, width: 538, height: 538), xRadius: 44, yRadius: 44)
NSColor(red: 0.018, green: 0.035, blue: 0.045, alpha: 1).setFill(); inset.fill()
let pattern = ["00011000", "00111100", "01111110", "11111111", "11011011", "11111111", "00100100", "01011010"]
for y in 0..<8 { for x in 0..<8 {
    let on = Array(pattern[y])[x] == "1"
    let path = NSBezierPath(roundedRect: NSRect(x: 271 + x * 61, y: 710 - y * 61, width: 52, height: 52), xRadius: 8, yRadius: 8)
    (on ? (y < 4 ? cyan : amber) : cyan.withAlphaComponent(0.06)).setFill(); path.fill()
} }
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
