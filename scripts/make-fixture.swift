// Generates a synthetic test image full of fictitious personal data, for checking
// that pdmask detects the formats the real screenshot in examples/ lacks
// (address, phone, email, birthdate, card number, QR code).
//
// Usage: swift scripts/make-fixture.swift examples/fixture-profile.png

import AppKit
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.dropFirst().first ?? "examples/fixture-profile.png"
let width = 900
let height = 1250

guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create context") }

context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

/// Draws text with its top-left corner at (x, top), measuring `top` from the image's top edge.
func draw(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat = 30, bold: Bool = false, gray: CGFloat = 0.1) {
    let font = CTFontCreateWithName((bold ? "HiraginoSans-W6" : "HiraginoSans-W3") as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(gray: gray, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: x, y: CGFloat(height) - top - size)
    CTLineDraw(line, context)
}

draw("会員登録票", x: 60, top: 50, size: 44, bold: true)

let rows: [(String, String)] = [
    ("氏名", "山田 花子"),
    ("ふりがな", "やまだ はなこ"),
    ("生年月日", "1990年1月1日"),
    ("住所", "〒100-0001 東京都千代田区千代田1-1"),
    ("", "サンプルマンション302号室"),
    ("電話", "090-1234-5678"),
    ("メール", "hanako.yamada@example.com"),
    ("カード", "4111 1111 1111 1111"),
]
var top: CGFloat = 150
for (label, value) in rows {
    if !label.isEmpty { draw(label, x: 60, top: top, gray: 0.45) }
    draw(value, x: 240, top: top)
    top += 62
}

context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
context.setLineWidth(2)
context.stroke(CGRect(x: 60, y: CGFloat(height) - top - 10, width: CGFloat(width - 120), height: 0))
top += 30

// Things that look like data but are not personal information.
for text in [
    "発行日 2026年10月6日",
    "発行元 株式会社サンプル商事 千葉駅前店",
    "担当 佐藤",
    "お客様各位 ご来店ありがとうございます",
    "仕様は予告なく変更される場合があります",
] {
    draw(text, x: 60, top: top, size: 26)
    top += 52
}

// QR code carrying a fictitious member record.
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue("MEMBER:0001234:YAMADA HANAKO".data(using: .utf8), forKey: "inputMessage")
let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
let qrImage = CIContext().createCGImage(qr, from: qr.extent)!
context.interpolationQuality = .none
context.draw(qrImage, in: CGRect(x: CGFloat(width) - 60 - qr.extent.width, y: 60, width: qr.extent.width, height: qr.extent.height))

let image = context.makeImage()!
let url = URL(fileURLWithPath: outputPath)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(outputPath)") }
print("Wrote \(outputPath)")
