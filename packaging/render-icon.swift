import Cocoa

// Renders the macsnap app icon (SF viewfinder glyph on a dark rounded
// square) into an .iconset directory. Run: swift packaging/render-icon.swift <iconset-dir>
guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-icon.swift <iconset-dir>\n", stderr)
    exit(2)
}
let iconsetDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func render(size: Int) -> NSImage? {
    let length = CGFloat(size)
    let img = NSImage(size: NSSize(width: length, height: length))
    img.lockFocus()
    defer { img.unlockFocus() }
    // Dark rounded-square background.
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: length, height: length),
                          xRadius: length * 0.225, yRadius: length * 0.225)
    NSColor(calibratedWhite: 0.11, alpha: 1.0).setFill()
    bg.fill()
    // White viewfinder glyph, ~62% of the canvas (template tinted via
    // source-atop so it renders white, not black).
    if let glyph = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "macsnap") {
        let glyphLen = length * 0.62
        let tinted = NSImage(size: NSSize(width: glyphLen, height: glyphLen))
        tinted.lockFocus()
        glyph.draw(in: NSRect(x: 0, y: 0, width: glyphLen, height: glyphLen))
        NSColor.white.set()
        NSRect(x: 0, y: 0, width: glyphLen, height: glyphLen).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: (length - glyphLen) / 2, y: (length - glyphLen) / 2,
                               width: glyphLen, height: glyphLen))
    }
    return img
}

// Standard iconset members.
let members: [(pixels: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for m in members {
    guard let img = render(size: m.pixels),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to render \(m.pixels)px\n", stderr)
        exit(1)
    }
    let url = URL(fileURLWithPath: iconsetDir).appendingPathComponent("\(m.name).png")
    try png.write(to: url)
}
print("iconset written to \(iconsetDir)")
