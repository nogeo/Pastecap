import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let ink = NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1)

// 背景：深紫罗兰 → 亮粉，超大圆角
let bg = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 240, yRadius: 240)
NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.11, blue: 0.71, alpha: 1),
    NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.60, alpha: 1)
])?.draw(in: bg, angle: 118)

// 新粗野主义白色描边
let border = NSBezierPath(roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840), xRadius: 214, yRadius: 214)
border.lineWidth = 22
NSColor.white.setStroke()
border.stroke()

// 闪光小星星
func sparkle(center: NSPoint, size: CGFloat, alpha: CGFloat) {
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: center.x - size / 2, y: center.y - size * 2.4, width: size, height: size * 4.8), xRadius: size / 2, yRadius: size / 2).fill()
    NSBezierPath(roundedRect: NSRect(x: center.x - size * 2.4, y: center.y - size / 2, width: size * 4.8, height: size), xRadius: size / 2, yRadius: size / 2).fill()
    NSBezierPath(ovalIn: NSRect(x: center.x - size * 0.7, y: center.y - size * 0.7, width: size * 1.4, height: size * 1.4)).fill()
}
sparkle(center: NSPoint(x: 200, y: 838), size: 20, alpha: 0.95)
sparkle(center: NSPoint(x: 842, y: 226), size: 26, alpha: 0.8)
sparkle(center: NSPoint(x: 190, y: 264), size: 14, alpha: 0.6)

// 主体（吉祥物剪贴板）微微倾斜 -6°
context.saveGState()
context.translateBy(x: 512, y: 512)
context.rotate(by: -6 * .pi / 180)
context.translateBy(x: -512, y: -512)

// 阴影
NSColor.black.withAlphaComponent(0.16).setFill()
NSBezierPath(roundedRect: NSRect(x: 282, y: 256, width: 460, height: 482), xRadius: 88, yRadius: 88).fill()

// 白色面板
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 282, y: 280, width: 460, height: 482), xRadius: 86, yRadius: 86).fill()

// 顶部夹子
NSColor(calibratedRed: 0.73, green: 0.76, blue: 0.84, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 246, width: 500, height: 64), xRadius: 28, yRadius: 28).fill()
NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.96, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 296, y: 262, width: 432, height: 22), xRadius: 11, yRadius: 11).fill()
NSColor(calibratedRed: 0.54, green: 0.57, blue: 0.66, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 341, y: 274, width: 30, height: 30)).fill()
NSBezierPath(ovalIn: NSRect(x: 653, y: 274, width: 30, height: 30)).fill()
NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.93, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 352, y: 285, width: 8, height: 8)).fill()
NSBezierPath(ovalIn: NSRect(x: 664, y: 285, width: 8, height: 8)).fill()

// 眼睛
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: 352, y: 518, width: 120, height: 120)).fill()
NSBezierPath(ovalIn: NSRect(x: 552, y: 518, width: 120, height: 120)).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 388, y: 556, width: 34, height: 34)).fill()
NSBezierPath(ovalIn: NSRect(x: 588, y: 556, width: 34, height: 34)).fill()

// 腮红
NSColor(calibratedRed: 0.96, green: 0.32, blue: 0.54, alpha: 0.42).setFill()
NSBezierPath(ovalIn: NSRect(x: 296, y: 462, width: 58, height: 40)).fill()
NSBezierPath(ovalIn: NSRect(x: 670, y: 462, width: 58, height: 40)).fill()

// 微笑
ink.setStroke()
let smile = NSBezierPath()
smile.lineWidth = 16
smile.lineCapStyle = .round
smile.appendArc(withCenter: NSPoint(x: 512, y: 436), radius: 108, startAngle: 205, endAngle: 335)
smile.stroke()

context.restoreGState()

// 右上角闪电徽章（贴纸风）
let badge = NSBezierPath(ovalIn: NSRect(x: 700, y: 684, width: 196, height: 196))
NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.24, alpha: 1).setFill()
badge.fill()
badge.lineWidth = 14
NSColor.white.setStroke()
badge.stroke()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 782, y: 844))
bolt.line(to: NSPoint(x: 744, y: 774))
bolt.line(to: NSPoint(x: 778, y: 774))
bolt.line(to: NSPoint(x: 758, y: 700))
bolt.line(to: NSPoint(x: 842, y: 790))
bolt.line(to: NSPoint(x: 800, y: 790))
bolt.close()
NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1).setFill()
bolt.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: outputURL, options: .atomic)