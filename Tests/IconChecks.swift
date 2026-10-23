import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, size) in [("Keychron.png", 18), ("Keychron@2x.png", 36)] {
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: folder.appendingPathComponent(name)))!
    precondition(bitmap.pixelsWide == size && bitmap.pixelsHigh == size)
    for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
        precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent == 0, "Icon corners must be transparent")
    }
    let visible = (0..<size).flatMap { y in (0..<size).map { x in bitmap.colorAt(x: x, y: y)!.alphaComponent } }
    precondition(visible.contains { $0 > 0.9 }, "Logo must remain visible")
    print("PASS \(name) size and transparent background")
}
