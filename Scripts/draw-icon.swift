import AppKit
let icon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { frame in
    NSColor.black.setStroke()
    let border = NSBezierPath(roundedRect: frame.insetBy(dx: 3, dy: 3), xRadius: 5, yRadius: 5)
    border.lineWidth = 2
    border.stroke()
    let text = NSAttributedString(string: "译", attributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.black
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2))
    return true
}
guard let tiff = icon.tiffRepresentation else { exit(1) }
try tiff.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
