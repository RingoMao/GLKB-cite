import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: render-icon.swift /path/to/AppIcon.png /path/to/AppIcon.icns\n".utf8)
    )
    exit(64)
}

let dimension = 1_024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: dimension,
    pixelsHigh: dimension,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Could not create the icon bitmap.\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

let tile = NSBezierPath(
    roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920),
    xRadius: 218,
    yRadius: 218
)
let gradient = NSGradient(
    starting: NSColor(deviceRed: 0.098, green: 0.298, blue: 0.439, alpha: 1),
    ending: NSColor(deviceRed: 0.165, green: 0.498, blue: 0.471, alpha: 1)
)
gradient?.draw(in: tile, angle: -45)

let leftPage = NSBezierPath()
leftPage.move(to: NSPoint(x: 262, y: 750))
leftPage.curve(
    to: NSPoint(x: 512, y: 767),
    controlPoint1: NSPoint(x: 346, y: 796),
    controlPoint2: NSPoint(x: 431, y: 804)
)
leftPage.line(to: NSPoint(x: 512, y: 247))
leftPage.curve(
    to: NSPoint(x: 262, y: 230),
    controlPoint1: NSPoint(x: 430, y: 284),
    controlPoint2: NSPoint(x: 346, y: 276)
)
leftPage.close()
NSColor(deviceWhite: 0.98, alpha: 1).setFill()
leftPage.fill()

let rightPage = NSBezierPath()
rightPage.move(to: NSPoint(x: 762, y: 750))
rightPage.curve(
    to: NSPoint(x: 512, y: 767),
    controlPoint1: NSPoint(x: 678, y: 796),
    controlPoint2: NSPoint(x: 593, y: 804)
)
rightPage.line(to: NSPoint(x: 512, y: 247))
rightPage.curve(
    to: NSPoint(x: 762, y: 230),
    controlPoint1: NSPoint(x: 594, y: 284),
    controlPoint2: NSPoint(x: 678, y: 276)
)
rightPage.close()
NSColor(deviceRed: 0.851, green: 0.941, blue: 0.925, alpha: 1).setFill()
rightPage.fill()

let lineColor = NSColor(deviceRed: 0.165, green: 0.498, blue: 0.471, alpha: 1)
lineColor.setStroke()
for xStart in [350.0, 564.0] {
    for y in [634.0, 546.0, 458.0] {
        let line = NSBezierPath()
        line.lineWidth = 34
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: xStart, y: y))
        line.line(to: NSPoint(x: xStart + 110, y: y))
        line.stroke()
    }
}

let lens = NSBezierPath(ovalIn: NSRect(x: 436, y: 258, width: 152, height: 152))
NSColor(deviceRed: 0.949, green: 0.722, blue: 0.294, alpha: 1).setFill()
lens.fill()

NSColor(deviceRed: 0.098, green: 0.298, blue: 0.439, alpha: 1).setStroke()
for endpoints in [
    (NSPoint(x: 483, y: 334), NSPoint(x: 541, y: 334)),
    (NSPoint(x: 512, y: 305), NSPoint(x: 512, y: 363))
] {
    let line = NSBezierPath()
    line.lineWidth = 26
    line.lineCapStyle = .round
    line.move(to: endpoints.0)
    line.line(to: endpoints.1)
    line.stroke()
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode the icon PNG.\n".utf8))
    exit(1)
}

let pngURL = URL(fileURLWithPath: CommandLine.arguments[1])
let icnsURL = URL(fileURLWithPath: CommandLine.arguments[2])
try data.write(to: pngURL, options: .atomic)

func resizedPNG(_ pixels: Int) throws -> Data {
    guard let source = NSImage(data: data),
          let target = NSBitmapImageRep(
              bitmapDataPlanes: nil,
              pixelsWide: pixels,
              pixelsHigh: pixels,
              bitsPerSample: 8,
              samplesPerPixel: 4,
              hasAlpha: true,
              isPlanar: false,
              colorSpaceName: .deviceRGB,
              bytesPerRow: 0,
              bitsPerPixel: 0
          ),
          let targetContext = NSGraphicsContext(bitmapImageRep: target)
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = targetContext
    targetContext.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(x: 0, y: 0, width: source.size.width, height: source.size.height),
        operation: .copy,
        fraction: 1
    )
    targetContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = target.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

func bigEndianBytes(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

let iconChunks: [(String, Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1_024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512)
]

let encodedChunks = try iconChunks.map { type, pixels -> (String, Data) in
    (type, try resizedPNG(pixels))
}
let totalLength = 8 + encodedChunks.reduce(0) { $0 + 8 + $1.1.count }
guard totalLength <= Int(UInt32.max) else {
    throw CocoaError(.fileWriteOutOfSpace)
}

var icns = Data("icns".utf8)
icns.append(bigEndianBytes(UInt32(totalLength)))
for (type, png) in encodedChunks {
    icns.append(Data(type.utf8))
    icns.append(bigEndianBytes(UInt32(png.count + 8)))
    icns.append(png)
}
try icns.write(to: icnsURL, options: .atomic)
