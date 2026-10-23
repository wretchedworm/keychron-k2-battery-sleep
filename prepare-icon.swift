import AppKit

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let source = NSBitmapImageRep(data: try Data(contentsOf: sourceURL))!
let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: source.pixelsWide,
    pixelsHigh: source.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<source.pixelsHigh {
    for x in 0..<source.pixelsWide {
        let color = source.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        let brightness = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        let alpha = UInt8((255 * max(0, min(1, 1 - brightness))).rounded())
        let offset = y * mask.bytesPerRow + x * 4
        let bytes = mask.bitmapData!
        bytes[offset] = 0
        bytes[offset + 1] = 0
        bytes[offset + 2] = 0
        bytes[offset + 3] = alpha
    }
}
let image = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
image.addRepresentation(mask)
for (pixels, name) in [(18, "Keychron.png"), (36, "Keychron@2x.png")] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
