import AppKit

// Exact geometry and palette of Resources/Logo.svg (the selected Center line mark).
enum IconRenderError: Error {
    case missingOutputDirectory
    case bitmapCreationFailed
    case graphicsContextCreationFailed
    case pngEncodingFailed
}

guard CommandLine.arguments.count == 2 else { throw IconRenderError.missingOutputDirectory }
let output = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: output + "/AppIcon.iconset", withIntermediateDirectories: true)
func png(_ pixels: Int) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw IconRenderError.bitmapCreationFailed }
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconRenderError.graphicsContextCreationFailed
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphicsContext
    let context = graphicsContext.cgContext
    context.scaleBy(x: CGFloat(pixels) / 32, y: CGFloat(pixels) / 32)
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setStrokeColor(
        CGColor(srgbRed: 205 / 255, green: 214 / 255, blue: 244 / 255, alpha: 0.45))
    for y: CGFloat in [8, 24] {
        context.move(to: CGPoint(x: 10, y: y))
        context.addLine(to: CGPoint(x: 22, y: y))
    }
    context.strokePath()
    context.setStrokeColor(CGColor(srgbRed: 180 / 255, green: 190 / 255, blue: 254 / 255, alpha: 1))
    context.move(to: CGPoint(x: 5, y: 16))
    context.addLine(to: CGPoint(x: 27, y: 16))
    context.strokePath()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconRenderError.pngEncodingFailed
    }
    return data
}
for size in [16, 32, 128, 256, 512] {
    try png(size).write(
        to: URL(fileURLWithPath: "\(output)/AppIcon.iconset/icon_\(size)x\(size).png"))
    try png(size * 2).write(
        to: URL(fileURLWithPath: "\(output)/AppIcon.iconset/icon_\(size)x\(size)@2x.png"))
}
try png(36).write(to: URL(fileURLWithPath: output + "/MenuBarIcon.png"))
