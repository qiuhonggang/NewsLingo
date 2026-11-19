import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func fillGradient(_ path: CGPath, colors: [UInt32], from: CGPoint, to: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors.map(color) as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func markPath(_ points: [CGPoint], width: CGFloat) -> CGPath {
    let spine = CGMutablePath()
    spine.addLines(between: points)
    return spine.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
}

let tile = CGPath(roundedRect: CGRect(x: 66, y: 66, width: 892, height: 892), cornerWidth: 202, cornerHeight: 202, transform: nil)
fillGradient(tile, colors: [0x25545A, 0x153841, 0x122536], from: CGPoint(x: 130, y: 920), to: CGPoint(x: 906, y: 120))
context.setStrokeColor(color(0x407074))
context.setLineWidth(3)
context.addPath(tile)
context.strokePath()

// The right stem of N doubles as the upright of L.
let news = markPath([CGPoint(x: 289, y: 341), CGPoint(x: 289, y: 683), CGPoint(x: 548, y: 341)], width: 88)
let lingo = markPath([CGPoint(x: 548, y: 683), CGPoint(x: 548, y: 341), CGPoint(x: 735, y: 341)], width: 88)
fillGradient(news, colors: [0xF1FFF8, 0xCDE9E4], from: CGPoint(x: 280, y: 725), to: CGPoint(x: 565, y: 299))
fillGradient(lingo, colors: [0xC8FFBC, 0x88E0AD], from: CGPoint(x: 520, y: 727), to: CGPoint(x: 749, y: 302))

// The headline rules stay secondary to the shared letterform.
context.setFillColor(color(0x68A9A1))
for bar in [CGRect(x: 645, y: 638, width: 114, height: 39), CGRect(x: 645, y: 550, width: 77, height: 39)] {
    context.addPath(CGPath(roundedRect: bar, cornerWidth: 19.5, cornerHeight: 19.5, transform: nil))
    context.fillPath()
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output))
