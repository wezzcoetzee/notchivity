import AppKit

let size: CGFloat = 1024
let inset: CGFloat = 100
let squircle = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset), xRadius: 185, yRadius: 185)
let red = NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1)
let amber = NSColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 1)
let green = NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1)
let grey = NSColor(white: 0.16, alpha: 1)

func render(_ name: String, _ draw: () -> Void) {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.black.setFill(); squircle.fill()
    draw()
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "/tmp/notchivity-icons/\(name).png"))
}

func bar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, pct: CGFloat, color: NSColor) {
    grey.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h/2, yRadius: h/2).fill()
    color.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: max(h, w*pct), height: h), xRadius: h/2, yRadius: h/2).fill()
}
func dot(x: CGFloat, y: CGFloat, r: CGFloat, color: NSColor) {
    color.setFill(); NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2*r, height: 2*r)).fill()
}
// The notch tab: a dark tab hanging from the top edge of the icon face.
func notch(width: CGFloat, height: CGFloat, color: NSColor) {
    let top = size - inset
    let rect = NSRect(x: (size - width)/2, y: top - height, width: width, height: height)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: top))
    path.line(to: NSPoint(x: rect.minX, y: rect.minY + 60))
    path.appendArc(withCenter: NSPoint(x: rect.minX + 60, y: rect.minY + 60), radius: 60, startAngle: 180, endAngle: 270)
    path.line(to: NSPoint(x: rect.maxX - 60, y: rect.minY))
    path.appendArc(withCenter: NSPoint(x: rect.maxX - 60, y: rect.minY + 60), radius: 60, startAngle: 270, endAngle: 360)
    path.line(to: NSPoint(x: rect.maxX, y: top))
    path.close()
    color.setFill(); path.fill()
}

// A. Miniature of the collapsed notch: tab, underline, status dots.
render("a-notch") {
    notch(width: 420, height: 130, color: grey)
    bar(x: 352, y: size - inset - 118, w: 320, h: 16, pct: 0.42, color: .white)
    dot(x: 380, y: 440, r: 46, color: red)
    dot(x: 512, y: 440, r: 46, color: amber)
    dot(x: 644, y: 440, r: 46, color: green)
}
// B. Bars and dots: usage on top, PR statuses beneath.
render("b-bars") {
    bar(x: 250, y: 640, w: 524, h: 56, pct: 0.35, color: .white)
    bar(x: 250, y: 540, w: 524, h: 56, pct: 0.72, color: amber)
    dot(x: 290, y: 380, r: 44, color: red)
    dot(x: 420, y: 380, r: 44, color: amber)
    dot(x: 550, y: 380, r: 44, color: amber)
    dot(x: 680, y: 380, r: 44, color: green)
}
// C. Notch silhouette: a white face with a black notch cut in, one green dot.
render("c-silhouette") {
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 200, y: 200, width: 624, height: 624), xRadius: 110, yRadius: 110).fill()
    let top: CGFloat = 824
    let rect = NSRect(x: 352, y: top - 110, width: 320, height: 110)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: top))
    path.line(to: NSPoint(x: rect.minX, y: rect.minY + 50))
    path.appendArc(withCenter: NSPoint(x: rect.minX + 50, y: rect.minY + 50), radius: 50, startAngle: 180, endAngle: 270)
    path.line(to: NSPoint(x: rect.maxX - 50, y: rect.minY))
    path.appendArc(withCenter: NSPoint(x: rect.maxX - 50, y: rect.minY + 50), radius: 50, startAngle: 270, endAngle: 360)
    path.line(to: NSPoint(x: rect.maxX, y: top))
    path.close()
    NSColor.black.setFill(); path.fill()
    dot(x: 512, y: 470, r: 70, color: green)
}
