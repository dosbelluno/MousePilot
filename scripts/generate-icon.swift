import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Pass an iconset directory") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot draw icon") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let scale = CGFloat(size) / 512
    graphics.cgContext.scaleBy(x: scale, y: scale)
    let background = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 448, height: 448), xRadius: 104, yRadius: 104)
    NSColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1).setFill()
    background.fill()
    let mouse = NSBezierPath(roundedRect: NSRect(x: 163, y: 108, width: 186, height: 296), xRadius: 88, yRadius: 88)
    NSColor(red: 0.35, green: 0.52, blue: 0.95, alpha: 1).setFill()
    mouse.fill()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 256, y: 345)); line.line(to: NSPoint(x: 256, y: 403))
    line.lineWidth = 4
    NSColor(white: 1, alpha: 0.85).setStroke(); line.stroke()
    NSColor(white: 1, alpha: 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: 246, y: 309, width: 20, height: 46), xRadius: 10, yRadius: 10).fill()
    NSBezierPath(roundedRect: NSRect(x: 143, y: 239, width: 10, height: 35), xRadius: 5, yRadius: 5).fill()
    NSBezierPath(roundedRect: NSRect(x: 143, y: 287, width: 10, height: 35), xRadius: 5, yRadius: 5).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: destination.appendingPathComponent(name + ".png"))
}
