import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CodeScreenshot {
    static func renderPNG(text: String, language: String) throws -> (path: String, base64: String, bytes: Int) {
        let highlighted = CodeFormatters.highlight(text, language: language)
        let lines = highlighted.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let width = 900
        let lineHeight = 18
        let height = max(120, 40 + min(lines.count, 80) * lineHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ToolError.failed("Could not create graphics context.")
        }
        context.setFillColor(CGColor(red: 0.09, green: 0.1, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let color = CGColor(red: 0.9, green: 0.92, blue: 0.95, alpha: 1)
        for (index, line) in lines.prefix(80).enumerated() {
            let attr: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            ]
            let lineRef = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attr))
            context.textPosition = CGPoint(x: 20, y: CGFloat(height - 30 - index * lineHeight))
            CTLineDraw(lineRef, context)
        }
        guard let image = context.makeImage() else {
            throw ToolError.failed("Could not render screenshot.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolbox-code-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ToolError.failed("Could not create PNG destination.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ToolError.failed("Could not write PNG.")
        }
        let data = try Data(contentsOf: url)
        return (url.path, data.base64EncodedString(), data.count)
    }
}
