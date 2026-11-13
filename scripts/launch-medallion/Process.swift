// Cuts the launch medallion layers out of ictool renders and writes them as image sets.
//
// Built and run by scripts/generate-launch-medallion.sh:
//   process <renders dir> <Assets.xcassets> <light r,g,b> <dark r,g,b>
//
// The renders dir holds 1024 × 1024 renders of the app icon (medallion of radius 400
// at the center):
//   base-black, base-white    the medallion alone on black and on white
//   glyph-black, glyph-white  the glyph alone on black and on white
//   all-light, all-dark       the whole icon on the light and dark LaunchBackground
//
// Each layer's color and transparency come from its black and white renders. The
// layers rendered apart miss what Liquid Glass draws where they meet (the thin
// outline around the glyph, the medallion rim against the background), so each
// layer is then corrected, per appearance, until base + glyph on LaunchBackground
// matches the real icon render. Corrections near the glyph go into the glyph, so
// they swing with it; everything else, the medallion's rim included, goes into the
// medallion, so nothing faint swings across it. The layers stay transparent.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry, in render pixels

let renderSize = 1024
/// The square cut out around the medallion, with room for its shadow.
let canvasSize = 960
let canvasOrigin = (renderSize - canvasSize) / 2
/// Outside this radius only the medallion is corrected: its rim against the background.
let rimRadius = 395.0
/// Corrections closer than this to the glyph belong to the glyph: its outline and shadow.
let glyphReach = 24
/// Beyond the medallion's shadow, the renders show the icon's own edge: fade it out.
let fadeStart = 460.0
let fadeEnd = 480.0

/// Output sizes: the canvas in points per idiom, and the scales to write.
let outputs: [(idiom: String, points: Double, scales: [Int])] = [
    ("universal", 264, [2, 3]),
    ("ipad", 384, [2]),
]

// MARK: - Images

/// A straight-alpha RGBA image with components in 0...1.
struct Picture {
    let width: Int
    let height: Int
    var pixels: [Double]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: 0, count: width * height * 4)
    }

    subscript(x: Int, y: Int, channel: Int) -> Double {
        get { pixels[(y * width + x) * 4 + channel] }
        set { pixels[(y * width + x) * 4 + channel] = newValue }
    }
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func load(_ url: URL) -> Picture {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("Cannot read \(url.path)") }
    guard image.width == renderSize, image.height == renderSize else {
        fail("\(url.lastPathComponent) is \(image.width) × \(image.height), expected \(renderSize) × \(renderSize)")
    }

    var bytes = [UInt8](repeating: 0, count: renderSize * renderSize * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: renderSize, height: renderSize, bitsPerComponent: 8,
            bytesPerRow: renderSize * 4, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: renderSize, height: renderSize))
    }

    var picture = Picture(width: renderSize, height: renderSize)
    for index in 0..<(renderSize * renderSize) {
        let alpha = Double(bytes[index * 4 + 3]) / 255
        for channel in 0..<3 {
            let premultiplied = Double(bytes[index * 4 + channel]) / 255
            picture.pixels[index * 4 + channel] = alpha > 0 ? min(premultiplied / alpha, 1) : 0
        }
        picture.pixels[index * 4 + 3] = alpha
    }
    return picture
}

/// Turns a straight-alpha picture into a CGImage.
func cgImage(_ picture: Picture) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
    for index in 0..<(picture.width * picture.height) {
        let alpha = picture.pixels[index * 4 + 3]
        for channel in 0..<3 {
            bytes[index * 4 + channel] = UInt8((picture.pixels[index * 4 + channel] * alpha * 255).rounded())
        }
        bytes[index * 4 + 3] = UInt8((alpha * 255).rounded())
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: picture.width, height: picture.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: picture.width * 4, space: sRGB,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    )!
}

func writePNG(_ picture: Picture, side: Int, to url: URL) {
    let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(cgImage(picture), in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("Cannot write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(url.path)") }
}

// MARK: - Layers

typealias RGB = (Double, Double, Double)

func parseColor(_ text: String) -> RGB {
    let parts = text.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 3 else { fail("Bad color \(text); expected r,g,b") }
    return (parts[0], parts[1], parts[2])
}

/// The distance of a canvas pixel from the medallion center, in render pixels.
func radius(_ x: Int, _ y: Int) -> Double {
    let center = Double(renderSize) / 2 - 0.5
    let dx = Double(x + canvasOrigin) - center
    let dy = Double(y + canvasOrigin) - center
    return (dx * dx + dy * dy).squareRoot()
}

/// Cuts a layer out of its renders on black and on white, cropped to the canvas.
func cutOut(black: Picture, white: Picture) -> Picture {
    var layer = Picture(width: canvasSize, height: canvasSize)
    for y in 0..<canvasSize {
        for x in 0..<canvasSize {
            let sx = x + canvasOrigin, sy = y + canvasOrigin
            let r = radius(x, y)
            // Outside the icon shape the renders are empty; past the shadow, fade out.
            guard black[sx, sy, 3] > 0.99, white[sx, sy, 3] > 0.99, r < fadeEnd else { continue }
            let fade = r <= fadeStart ? 1 : (fadeEnd - r) / (fadeEnd - fadeStart)

            var difference = 0.0
            for channel in 0..<3 { difference += white[sx, sy, channel] - black[sx, sy, channel] }
            let alpha = min(max(1 - difference / 3, 0), 1)
            guard alpha > 0.0001 else { continue }

            for channel in 0..<3 {
                layer[x, y, channel] = min(max(black[sx, sy, channel] / alpha, 0), 1)
            }
            layer[x, y, 3] = alpha * fade
        }
    }
    return layer
}

/// Color of a layer pixel laid over a color.
func over(_ layer: Picture, _ x: Int, _ y: Int, _ under: RGB) -> RGB {
    let a = layer[x, y, 3]
    return (
        layer[x, y, 0] * a + under.0 * (1 - a),
        layer[x, y, 1] * a + under.1 * (1 - a),
        layer[x, y, 2] * a + under.2 * (1 - a)
    )
}

/// Changes a layer pixel so that, laid over `under`, it gives `target`, keeping at
/// least the layer's own opacity.
func correct(_ layer: inout Picture, _ x: Int, _ y: Int, under: RGB, target: RGB) {
    let u = [under.0, under.1, under.2], t = [target.0, target.1, target.2]
    var needed = layer[x, y, 3]
    for channel in 0..<3 {
        if t[channel] < u[channel] {
            needed = max(needed, (u[channel] - t[channel]) / max(u[channel], 0.0001))
        } else if t[channel] > u[channel] {
            needed = max(needed, (t[channel] - u[channel]) / max(1 - u[channel], 0.0001))
        }
    }
    needed = min(needed, 1)
    guard needed > 0.0001 else { return }
    for channel in 0..<3 {
        layer[x, y, channel] = min(max((t[channel] - u[channel] * (1 - needed)) / needed, 0), 1)
    }
    layer[x, y, 3] = needed
}

/// The glyph laid over the medallion, still transparent.
func stack(_ top: Picture, over bottom: Picture) -> Picture {
    var result = Picture(width: canvasSize, height: canvasSize)
    for index in 0..<(canvasSize * canvasSize) {
        let at = top.pixels[index * 4 + 3], ab = bottom.pixels[index * 4 + 3]
        let alpha = at + ab * (1 - at)
        guard alpha > 0.0001 else { continue }
        for channel in 0..<3 {
            let color = top.pixels[index * 4 + channel] * at + bottom.pixels[index * 4 + channel] * ab * (1 - at)
            result.pixels[index * 4 + channel] = color / alpha
        }
        result.pixels[index * 4 + 3] = alpha
    }
    return result
}

/// The pixels within `glyphReach` of the glyph (a square neighborhood).
func nearGlyph(_ glyph: Picture) -> [Bool] {
    let side = canvasSize
    var solid = [Int](repeating: 0, count: side * side)
    for index in 0..<(side * side) where glyph.pixels[index * 4 + 3] > 0.05 { solid[index] = 1 }

    // Dilates rows, then columns, with running sums over a window of 2 × reach + 1.
    func dilate(_ input: [Int], horizontal: Bool) -> [Int] {
        var output = [Int](repeating: 0, count: side * side)
        for line in 0..<side {
            func index(_ position: Int) -> Int { horizontal ? line * side + position : position * side + line }
            var sum = 0
            for position in 0..<min(glyphReach, side) { sum += input[index(position)] }
            for position in 0..<side {
                let entering = position + glyphReach, leaving = position - glyphReach - 1
                if entering < side { sum += input[index(entering)] }
                if leaving >= 0 { sum -= input[index(leaving)] }
                output[index(position)] = sum > 0 ? 1 : 0
            }
        }
        return output
    }
    return dilate(dilate(solid, horizontal: true), horizontal: false).map { $0 > 0 }
}

/// Corrects both layers against the real render of the icon on `background`.
func corrected(base: Picture, glyph: Picture, reference: Picture, background: RGB) -> (base: Picture, glyph: Picture) {
    var base = base, glyph = glyph
    let near = nearGlyph(glyph)
    // The medallion first: the glyph's corrections are made over the corrected medallion.
    for pass in 0..<2 {
        for y in 0..<canvasSize {
            for x in 0..<canvasSize {
                let sx = x + canvasOrigin, sy = y + canvasOrigin
                guard reference[sx, sy, 3] > 0.99, radius(x, y) < fadeStart else { continue }
                let target = (reference[sx, sy, 0], reference[sx, sy, 1], reference[sx, sy, 2])
                let belongsToGlyph = near[y * canvasSize + x] && radius(x, y) < rimRadius
                if pass == 0, !belongsToGlyph {
                    // Away from the glyph only the medallion shows; drop the glyph's faint traces.
                    glyph[x, y, 3] = 0
                    correct(&base, x, y, under: background, target: target)
                } else if pass == 1, belongsToGlyph {
                    correct(&glyph, x, y, under: over(base, x, y, background), target: target)
                }
            }
        }
    }
    return (base, glyph)
}

// MARK: - Asset catalog

let darkAppearance: [[String: String]] = [["appearance": "luminosity", "value": "dark"]]

func writeImageSet(_ name: String, light: Picture, dark: Picture, catalog: URL) {
    let folder = catalog.appendingPathComponent("\(name).imageset")
    try? FileManager.default.removeItem(at: folder)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
        fail("Cannot create \(folder.path): \(error)")
    }

    let variants: [(suffix: String, picture: Picture, appearances: [[String: String]]?)] = [
        ("", light, nil),
        ("-dark", dark, darkAppearance),
    ]
    var images: [[String: Any]] = []
    for (suffix, picture, appearances) in variants {
        for output in outputs {
            for scale in output.scales {
                let idiomSuffix = output.idiom == "universal" ? "" : "~\(output.idiom)"
                let filename = "\(name)\(suffix)\(idiomSuffix)@\(scale)x.png"
                writePNG(picture, side: Int((output.points * Double(scale)).rounded()), to: folder.appendingPathComponent(filename))
                var entry: [String: Any] = ["filename": filename, "idiom": output.idiom, "scale": "\(scale)x"]
                if let appearances { entry["appearances"] = appearances }
                images.append(entry)
            }
        }
    }

    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    do {
        let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("Contents.json"))
    } catch {
        fail("Cannot write \(folder.path)/Contents.json: \(error)")
    }
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("Usage: process <renders dir> <Assets.xcassets> <light r,g,b> <dark r,g,b>")
}
let renders = URL(fileURLWithPath: arguments[1])
let catalog = URL(fileURLWithPath: arguments[2])
let backgrounds = (light: parseColor(arguments[3]), dark: parseColor(arguments[4]))

func render(_ name: String) -> Picture {
    load(renders.appendingPathComponent("\(name).png"))
}

let base = cutOut(black: render("base-black"), white: render("base-white"))
let glyph = cutOut(black: render("glyph-black"), white: render("glyph-white"))
let light = corrected(base: base, glyph: glyph, reference: render("all-light"), background: backgrounds.light)
let dark = corrected(base: base, glyph: glyph, reference: render("all-dark"), background: backgrounds.dark)

writeImageSet("SplashMedallionBase", light: light.base, dark: dark.base, catalog: catalog)
writeImageSet("SplashMedallionGlyph", light: light.glyph, dark: dark.glyph, catalog: catalog)
writeImageSet(
    "LaunchMedallion",
    light: stack(light.glyph, over: light.base),
    dark: stack(dark.glyph, over: dark.base),
    catalog: catalog
)
