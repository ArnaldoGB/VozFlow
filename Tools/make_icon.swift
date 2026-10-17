// Renders the 1024×1024 app icon: usage `swift make_icon.swift <output.png>`
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.42, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.47, green: 0.25, blue: 0.95, alpha: 1),
])!.draw(in: shape, angle: -60)

// Waveform bars
let heights: [CGFloat] = [0.22, 0.42, 0.68, 0.48, 0.80, 0.56, 0.34, 0.62, 0.28]
let barWidth: CGFloat = 46
let gap: CGFloat = 30
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (size - total) / 2
NSColor.white.setFill()
for h in heights {
    let barHeight = h * 560
    let bar = NSRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
    NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
