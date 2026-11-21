// Draws the Todos app icon. Run from the repository root:
//   xcrun swiftc Design/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
// Writes todos/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024 x 1024, opaque, no corner mask;
// iOS applies its own mask).
import CoreGraphics
import Foundation
import ImageIO

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// A matte ink background with only the faintest tonal shift. No glow, no highlights.
let gradient = CGGradient(colorsSpace: space, colors: [color(0x222C36), color(0x182029)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])

// The checkbox: a rounded square outline, set a little low and left to leave room for the check.
let box = CGRect(x: 214, y: 214, width: 500, height: 500)
context.setStrokeColor(color(0xECE7DD))
context.setLineWidth(40)
context.addPath(CGPath(roundedRect: box, cornerWidth: 120, cornerHeight: 120, transform: nil))
context.strokePath()

// The check: brass, breaking out of the box towards the top right.
context.setStrokeColor(color(0xC9A66B))
context.setLineWidth(84)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 330, y: 470))
context.addLine(to: CGPoint(x: 470, y: 330))
context.addLine(to: CGPoint(x: 800, y: 740))
context.strokePath()

let url = URL(fileURLWithPath: "todos/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write the icon") }
print("wrote \(url.path)")
