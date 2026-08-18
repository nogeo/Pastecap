import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// MARK: - 1. macOS Icon Base & Squircle Background (macOS HIG Standard)

let squircleRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircleRadius: CGFloat = 185
let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: squircleRadius, yRadius: squircleRadius)

// Base Drop Shadow
context.saveGState()
let shadowColor = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.25, alpha: 0.45)
context.setShadow(offset: CGSize(width: 0, height: -32), blur: 46, color: shadowColor.cgColor)
NSColor.black.withAlphaComponent(0.01).setFill()
squirclePath.fill()
context.restoreGState()

// Background Gradient: Deep Royal Indigo → Modern Violet
context.saveGState()
squirclePath.addClip()

let bgGradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.38, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.62, alpha: 1.0), 0.5),
    (NSColor(calibratedRed: 0.40, green: 0.18, blue: 0.76, alpha: 1.0), 1.0)
)
bgGradient?.draw(in: squircleRect, angle: 45)

// Top Specular Highlight (Rim Light)
let innerHighlight = NSBezierPath(roundedRect: squircleRect.insetBy(dx: 1.5, dy: 1.5), xRadius: squircleRadius - 1.5, yRadius: squircleRadius - 1.5)
innerHighlight.lineWidth = 2.0
NSColor.white.withAlphaComponent(0.25).setStroke()
innerHighlight.stroke()

// Subtle Blueprint / Viewfinder Grid
context.saveGState()
let gridColor = NSColor.white.withAlphaComponent(0.05)
gridColor.setStroke()
let gridPath = NSBezierPath()
gridPath.lineWidth = 1.2
for x in stride(from: 180, to: 900, by: 110) {
    gridPath.move(to: NSPoint(x: x, y: 100))
    gridPath.line(to: NSPoint(x: x, y: 924))
}
for y in stride(from: 180, to: 900, by: 110) {
    gridPath.move(to: NSPoint(x: 100, y: y))
    gridPath.line(to: NSPoint(x: 924, y: y))
}
gridPath.stroke()
context.restoreGState()

// Viewfinder Brackets (4 corners)
func drawCropCorner(at center: NSPoint, dx: CGFloat, dy: CGFloat, length: CGFloat) {
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: center.x, y: center.y + dy * length))
    corner.line(to: center)
    corner.line(to: NSPoint(x: center.x + dx * length, y: center.y))
    corner.lineWidth = 5.5
    corner.lineCapStyle = .round
    corner.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.42).setStroke()
    corner.stroke()
}
drawCropCorner(at: NSPoint(x: 200, y: 800), dx: 1, dy: -1, length: 34)
drawCropCorner(at: NSPoint(x: 824, y: 800), dx: -1, dy: -1, length: 34)
drawCropCorner(at: NSPoint(x: 200, y: 180), dx: 1, dy: 1, length: 34)
drawCropCorner(at: NSPoint(x: 824, y: 180), dx: -1, dy: 1, length: 34)

// MARK: - 2. Layered Documents (代表复制 Clipboard / Copy)

// --- Layer 1: Back Document (Tilted -10°) ---
context.saveGState()
context.translateBy(x: 440, y: 490)
context.rotate(by: -10 * .pi / 180)
context.translateBy(x: -440, y: -490)

let backDocRect = NSRect(x: 255, y: 245, width: 370, height: 490)
let backDocPath = NSBezierPath(roundedRect: backDocRect, xRadius: 30, yRadius: 30)

// Back doc shadow
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.96, alpha: 0.90).setFill()
backDocPath.fill()
context.restoreGState()

// Back doc subtle placeholder content
NSColor.white.withAlphaComponent(0.45).setFill()
NSBezierPath(roundedRect: NSRect(x: 295, y: 655, width: 120, height: 16), xRadius: 8, yRadius: 8).fill()
NSBezierPath(roundedRect: NSRect(x: 295, y: 608, width: 290, height: 12), xRadius: 6, yRadius: 6).fill()
NSBezierPath(roundedRect: NSRect(x: 295, y: 574, width: 230, height: 12), xRadius: 6, yRadius: 6).fill()
NSBezierPath(roundedRect: NSRect(x: 295, y: 540, width: 260, height: 12), xRadius: 6, yRadius: 6).fill()

context.restoreGState()

// --- Layer 2: Front Main Document (Tilted +2°) ---
context.saveGState()
context.translateBy(x: 490, y: 470)
context.rotate(by: 2 * .pi / 180)
context.translateBy(x: -490, y: -470)

let frontDocRect = NSRect(x: 295, y: 215, width: 390, height: 505)
let frontDocPath = NSBezierPath(roundedRect: frontDocRect, xRadius: 32, yRadius: 32)

// Front doc soft multi-layer shadow
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -22), blur: 36, color: NSColor.black.withAlphaComponent(0.38).cgColor)
NSColor.white.setFill()
frontDocPath.fill()
context.restoreGState()

// Front doc gradient fill
let docGradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedWhite: 1.0, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.99, alpha: 1.0), 1.0)
)
docGradient?.draw(in: frontDocPath, angle: -85)

// Document Inner Header Tag Pill
let clipBadge = NSBezierPath(roundedRect: NSRect(x: 340, y: 640, width: 110, height: 28), xRadius: 14, yRadius: 14)
NSColor(calibratedRed: 0.28, green: 0.44, blue: 0.98, alpha: 0.14).setFill()
clipBadge.fill()
let clipDot = NSBezierPath(ovalIn: NSRect(x: 354, y: 649, width: 10, height: 10))
NSColor(calibratedRed: 0.28, green: 0.44, blue: 0.98, alpha: 1.0).setFill()
clipDot.fill()
let clipTitleBar = NSBezierPath(roundedRect: NSRect(x: 372, y: 650, width: 62, height: 8), xRadius: 4, yRadius: 4)
NSColor(calibratedRed: 0.28, green: 0.44, blue: 0.98, alpha: 0.7).setFill()
clipTitleBar.fill()

// Text Content Bars
let textBarColor = NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.46, alpha: 0.24)
textBarColor.setFill()
NSBezierPath(roundedRect: NSRect(x: 340, y: 590, width: 300, height: 14), xRadius: 7, yRadius: 7).fill()
NSBezierPath(roundedRect: NSRect(x: 340, y: 554, width: 250, height: 14), xRadius: 7, yRadius: 7).fill()
NSBezierPath(roundedRect: NSRect(x: 340, y: 518, width: 270, height: 14), xRadius: 7, yRadius: 7).fill()
NSBezierPath(roundedRect: NSRect(x: 340, y: 482, width: 180, height: 14), xRadius: 7, yRadius: 7).fill()

// Media preview card inside front document
let mediaBox = NSBezierPath(roundedRect: NSRect(x: 340, y: 265, width: 300, height: 185), xRadius: 18, yRadius: 18)
NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.98, alpha: 1.0).setFill()
mediaBox.fill()

// Mountain silhouettes in image card
let thumbAccent = NSBezierPath()
thumbAccent.move(to: NSPoint(x: 365, y: 290))
thumbAccent.line(to: NSPoint(x: 435, y: 385))
thumbAccent.line(to: NSPoint(x: 495, y: 325))
thumbAccent.line(to: NSPoint(x: 550, y: 410))
thumbAccent.line(to: NSPoint(x: 615, y: 290))
thumbAccent.close()
NSColor(calibratedRed: 0.28, green: 0.52, blue: 0.95, alpha: 0.48).setFill()
thumbAccent.fill()

let thumbSun = NSBezierPath(ovalIn: NSRect(x: 555, y: 390, width: 32, height: 32))
NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.24, alpha: 0.85).setFill()
thumbSun.fill()

context.restoreGState()

// MARK: - 3. Scissors (代表截图 Snip / Screenshot)

// Scissors positioned cutting diagonally from right towards center
context.saveGState()
let pivot = NSPoint(x: 620, y: 550)
context.translateBy(x: pivot.x, y: pivot.y)
context.rotate(by: -30 * .pi / 180)
context.translateBy(x: -pivot.x, y: -pivot.y)

// Scissors Overall Shadow
context.saveGState()
context.setShadow(offset: CGSize(width: 10, height: -24), blur: 30, color: NSColor.black.withAlphaComponent(0.42).cgColor)

// Lower Metallic Blade
let blade1 = NSBezierPath()
blade1.move(to: NSPoint(x: pivot.x + 10, y: pivot.y))
blade1.curve(to: NSPoint(x: pivot.x - 240, y: pivot.y + 34), controlPoint1: NSPoint(x: pivot.x - 80, y: pivot.y + 20), controlPoint2: NSPoint(x: pivot.x - 170, y: pivot.y + 30))
blade1.curve(to: NSPoint(x: pivot.x + 10, y: pivot.y - 30), controlPoint1: NSPoint(x: pivot.x - 170, y: pivot.y - 6), controlPoint2: NSPoint(x: pivot.x - 80, y: pivot.y - 20))
blade1.close()

let bladeGradient1 = NSGradient(colorsAndLocations:
    (NSColor(calibratedWhite: 0.98, alpha: 1.0), 0.0),
    (NSColor(calibratedWhite: 0.84, alpha: 1.0), 0.5),
    (NSColor(calibratedWhite: 0.64, alpha: 1.0), 1.0)
)
bladeGradient1?.draw(in: blade1, angle: 90)

// Upper Metallic Blade
let blade2 = NSBezierPath()
blade2.move(to: NSPoint(x: pivot.x + 10, y: pivot.y))
blade2.curve(to: NSPoint(x: pivot.x - 245, y: pivot.y - 38), controlPoint1: NSPoint(x: pivot.x - 80, y: pivot.y - 20), controlPoint2: NSPoint(x: pivot.x - 170, y: pivot.y - 30))
blade2.curve(to: NSPoint(x: pivot.x + 10, y: pivot.y + 30), controlPoint1: NSPoint(x: pivot.x - 170, y: pivot.y + 8), controlPoint2: NSPoint(x: pivot.x - 80, y: pivot.y + 22))
blade2.close()

let bladeGradient2 = NSGradient(colorsAndLocations:
    (NSColor(calibratedWhite: 1.0, alpha: 1.0), 0.0),
    (NSColor(calibratedWhite: 0.88, alpha: 1.0), 0.5),
    (NSColor(calibratedWhite: 0.68, alpha: 1.0), 1.0)
)
bladeGradient2?.draw(in: blade2, angle: -90)
context.restoreGState()

// Blade sharp cutting edge highlight line
let sharpEdge = NSBezierPath()
sharpEdge.move(to: NSPoint(x: pivot.x + 10, y: pivot.y))
sharpEdge.curve(to: NSPoint(x: pivot.x - 245, y: pivot.y - 38), controlPoint1: NSPoint(x: pivot.x - 80, y: pivot.y - 20), controlPoint2: NSPoint(x: pivot.x - 170, y: pivot.y - 30))
sharpEdge.lineWidth = 2.5
sharpEdge.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.95).setStroke()
sharpEdge.stroke()

// Vibrant Handle Gradient: Coral Red → Electric Sunset
let handleGradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 1.0, green: 0.44, blue: 0.28, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.94, green: 0.22, blue: 0.40, alpha: 1.0), 1.0)
)

// Function to draw clean seamless handle with transparency layer
func drawErgonomicHandle(loopCenter: NSPoint, loopRadiusX: CGFloat, loopRadiusY: CGFloat, innerRadiusX: CGFloat, innerRadiusY: CGFloat, tiltAngle: CGFloat) {
    context.saveGState()
    context.beginTransparencyLayer(auxiliaryInfo: nil)

    // Solid Handle Background (Arm + Outer Ring)
    context.saveGState()
    context.translateBy(x: loopCenter.x, y: loopCenter.y)
    context.rotate(by: tiltAngle)
    context.translateBy(x: -loopCenter.x, y: -loopCenter.y)

    let handleArm = NSBezierPath()
    handleArm.move(to: NSPoint(x: pivot.x, y: pivot.y - 18))
    handleArm.line(to: NSPoint(x: loopCenter.x - 30, y: loopCenter.y - 30))
    handleArm.line(to: NSPoint(x: loopCenter.x - 30, y: loopCenter.y + 30))
    handleArm.line(to: NSPoint(x: pivot.x, y: pivot.y + 18))
    handleArm.close()

    let outerOval = NSBezierPath(ovalIn: NSRect(x: loopCenter.x - loopRadiusX, y: loopCenter.y - loopRadiusY, width: loopRadiusX * 2, height: loopRadiusY * 2))

    let combinedOuter = NSBezierPath()
    combinedOuter.append(handleArm)
    combinedOuter.append(outerOval)
    handleGradient?.draw(in: combinedOuter, angle: 45)

    // Rim highlight on outer edge
    combinedOuter.lineWidth = 2.0
    NSColor.white.withAlphaComponent(0.35).setStroke()
    combinedOuter.stroke()

    // Clean Inner Cutout Hole (Erased completely)
    context.setBlendMode(.clear)
    let innerHole = NSBezierPath(ovalIn: NSRect(x: loopCenter.x - innerRadiusX, y: loopCenter.y - innerRadiusY, width: innerRadiusX * 2, height: innerRadiusY * 2))
    NSColor.black.setFill()
    innerHole.fill()

    context.restoreGState()

    // Inner Rim Highlight
    context.saveGState()
    context.translateBy(x: loopCenter.x, y: loopCenter.y)
    context.rotate(by: tiltAngle)
    context.translateBy(x: -loopCenter.x, y: -loopCenter.y)
    let innerRim = NSBezierPath(ovalIn: NSRect(x: loopCenter.x - innerRadiusX, y: loopCenter.y - innerRadiusY, width: innerRadiusX * 2, height: innerRadiusY * 2))
    innerRim.lineWidth = 2.0
    NSColor.white.withAlphaComponent(0.40).setStroke()
    innerRim.stroke()
    context.restoreGState()

    context.endTransparencyLayer()
    context.restoreGState()
}

// Upper Handle Loop
drawErgonomicHandle(
    loopCenter: NSPoint(x: pivot.x + 130, y: pivot.y + 80),
    loopRadiusX: 60,
    loopRadiusY: 45,
    innerRadiusX: 38,
    innerRadiusY: 24,
    tiltAngle: 0.28
)

// Lower Handle Loop
drawErgonomicHandle(
    loopCenter: NSPoint(x: pivot.x + 130, y: pivot.y - 80),
    loopRadiusX: 60,
    loopRadiusY: 45,
    innerRadiusX: 38,
    innerRadiusY: 24,
    tiltAngle: -0.28
)

// Golden Pivot Rivet / Screw
let rivetOuter = NSBezierPath(ovalIn: NSRect(x: pivot.x - 18, y: pivot.y - 18, width: 36, height: 36))
let goldGradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.44, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.84, green: 0.62, blue: 0.18, alpha: 1.0), 1.0)
)
goldGradient?.draw(in: rivetOuter, angle: 45)

let rivetInner = NSBezierPath(ovalIn: NSRect(x: pivot.x - 10, y: pivot.y - 10, width: 20, height: 20))
NSColor(calibratedRed: 0.98, green: 0.92, blue: 0.68, alpha: 1.0).setFill()
rivetInner.fill()

let rivetCore = NSBezierPath(ovalIn: NSRect(x: pivot.x - 4, y: pivot.y - 4, width: 8, height: 8))
NSColor(calibratedRed: 0.48, green: 0.34, blue: 0.08, alpha: 1.0).setFill()
rivetCore.fill()

context.restoreGState() // restore scissors rotation

// MARK: - 4. Pisces Zodiac Constellation Emblem (右上角双鱼座徽标 ♓︎)

func drawPiscesEmblem(center: NSPoint, radius: CGFloat) {
    context.saveGState()

    // 柔光微晕底盘
    let glow = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    let glowGradient = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.38, green: 0.52, blue: 0.98, alpha: 0.35), 0.0),
        (NSColor(calibratedRed: 0.65, green: 0.38, blue: 0.95, alpha: 0.0), 1.0)
    )
    glowGradient?.draw(in: glow, angle: 45)

    // 外圈细金环
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius * 0.78, y: center.y - radius * 0.78, width: radius * 1.56, height: radius * 1.56))
    ring.lineWidth = 1.6
    NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.44, alpha: 0.55).setStroke()
    ring.stroke()

    // 双鱼座经典符号 (Pisces Symbol: 两个对向弯弧 + 一条横贯桥梁)
    let symbolColor = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.62, alpha: 0.95)
    symbolColor.setStroke()
    symbolColor.setFill()

    let strokeWidth: CGFloat = 3.5
    let halfHeight: CGFloat = radius * 0.48
    let arcWidth: CGFloat = radius * 0.32

    // 左侧弧线 (向左凸起)
    let leftArc = NSBezierPath()
    leftArc.move(to: NSPoint(x: center.x - arcWidth * 0.3, y: center.y + halfHeight))
    leftArc.curve(to: NSPoint(x: center.x - arcWidth * 0.3, y: center.y - halfHeight),
                  controlPoint1: NSPoint(x: center.x - arcWidth * 1.25, y: center.y + halfHeight * 0.5),
                  controlPoint2: NSPoint(x: center.x - arcWidth * 1.25, y: center.y - halfHeight * 0.5))
    leftArc.lineWidth = strokeWidth
    leftArc.lineCapStyle = .round
    leftArc.stroke()

    // 右侧弧线 (向右凸起)
    let rightArc = NSBezierPath()
    rightArc.move(to: NSPoint(x: center.x + arcWidth * 0.3, y: center.y + halfHeight))
    rightArc.curve(to: NSPoint(x: center.x + arcWidth * 0.3, y: center.y - halfHeight),
                   controlPoint1: NSPoint(x: center.x + arcWidth * 1.25, y: center.y + halfHeight * 0.5),
                   controlPoint2: NSPoint(x: center.x + arcWidth * 1.25, y: center.y - halfHeight * 0.5))
    rightArc.lineWidth = strokeWidth
    rightArc.lineCapStyle = .round
    rightArc.stroke()

    // 中间横贯线 (双鱼纽带)
    let crossLine = NSBezierPath()
    crossLine.move(to: NSPoint(x: center.x - arcWidth * 0.95, y: center.y))
    crossLine.line(to: NSPoint(x: center.x + arcWidth * 0.95, y: center.y))
    crossLine.lineWidth = strokeWidth
    crossLine.lineCapStyle = .round
    crossLine.stroke()

    // 两条相伴小鱼星点 / 鱼跃微点
    let fish1 = NSBezierPath(ovalIn: NSRect(x: center.x - arcWidth * 0.95 - 4, y: center.y + halfHeight - 4, width: 8, height: 8))
    fish1.fill()
    let fish2 = NSBezierPath(ovalIn: NSRect(x: center.x + arcWidth * 0.95 - 4, y: center.y - halfHeight - 4, width: 8, height: 8))
    fish2.fill()

    context.restoreGState()
}

// 绘制右上角双鱼座徽章
drawPiscesEmblem(center: NSPoint(x: 820, y: 780), radius: 52)

// MARK: - 5. Sparkles / Action Particles

func drawSparkle(center: NSPoint, size: CGFloat, color: NSColor) {
    color.setFill()
    let star = NSBezierPath()
    star.move(to: NSPoint(x: center.x, y: center.y + size))
    star.curve(to: NSPoint(x: center.x + size, y: center.y), controlPoint1: NSPoint(x: center.x, y: center.y), controlPoint2: NSPoint(x: center.x, y: center.y))
    star.curve(to: NSPoint(x: center.x, y: center.y - size), controlPoint1: NSPoint(x: center.x, y: center.y), controlPoint2: NSPoint(x: center.x, y: center.y))
    star.curve(to: NSPoint(x: center.x - size, y: center.y), controlPoint1: NSPoint(x: center.x, y: center.y), controlPoint2: NSPoint(x: center.x, y: center.y))
    star.curve(to: NSPoint(x: center.x, y: center.y + size), controlPoint1: NSPoint(x: center.x, y: center.y), controlPoint2: NSPoint(x: center.x, y: center.y))
    star.close()
    star.fill()
}

drawSparkle(center: NSPoint(x: 270, y: 740), size: 22, color: NSColor.white.withAlphaComponent(0.85))
drawSparkle(center: NSPoint(x: 770, y: 260), size: 18, color: NSColor.white.withAlphaComponent(0.75))

context.restoreGState() // restore squircle clip

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: outputURL, options: .atomic)
