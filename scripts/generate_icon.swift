#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

/// 在指定尺寸画布上绘制 macOS Big Sur / Sequoia 现代风格的 WhereAmIP 应用图标
func renderAppIcon(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = nsCtx
    let cg = nsCtx.cgContext

    // 统一在 1024x1024 逻辑坐标系下绘制，再等比缩放到目标像素尺寸
    let scale = CGFloat(size) / 1024.0
    cg.scaleBy(x: scale, y: scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. 绘制 macOS 标准圆角矩形底座 (824x824, 边距 100, 圆角 185) + 外阴影
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: 185, yRadius: 185)

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -18),
        blur: 36,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.42).cgColor
    )
    NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.20, alpha: 1.0).setFill()
    squirclePath.fill()
    cg.restoreGState()

    // 裁剪至圆角矩形内部
    cg.saveGState()
    squirclePath.addClip()

    // 2. 深海极光渐变背景
    let bgColors = [
        NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.17, blue: 0.36, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.32, blue: 0.58, alpha: 1.0).cgColor
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        cg.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: 512, y: 100),
            end: CGPoint(x: 512, y: 924),
            options: []
        )
    }

    // 中心径向发光光晕
    let glowColors = [
        NSColor(calibratedRed: 0.12, green: 0.68, blue: 0.98, alpha: 0.42).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.35, blue: 0.70, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        cg.drawRadialGradient(
            glowGradient,
            startCenter: CGPoint(x: 512, y: 525),
            startRadius: 20,
            endCenter: CGPoint(x: 512, y: 525),
            endRadius: 380,
            options: []
        )
    }

    // 3. 绘制经纬地球仪网格 (中心: 512, 515, 半径: 255)
    let globeCenter = CGPoint(x: 512, y: 515)
    let globeRadius: CGFloat = 255.0

    // 外围雷达脉冲光环
    NSColor(calibratedRed: 0.25, green: 0.78, blue: 1.0, alpha: 0.18).setStroke()
    let outerPulse = NSBezierPath(
        ovalIn: CGRect(
            x: globeCenter.x - globeRadius - 42,
            y: globeCenter.y - globeRadius - 42,
            width: (globeRadius + 42) * 2,
            height: (globeRadius + 42) * 2
        )
    )
    outerPulse.lineWidth = 4
    outerPulse.stroke()

    // 地球半透明球体填充
    let spherePath = NSBezierPath(
        ovalIn: CGRect(
            x: globeCenter.x - globeRadius,
            y: globeCenter.y - globeRadius,
            width: globeRadius * 2,
            height: globeRadius * 2
        )
    )
    NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.75, alpha: 0.28).setFill()
    spherePath.fill()

    // 裁剪到地球内部画经纬线
    cg.saveGState()
    spherePath.addClip()

    NSColor(calibratedRed: 0.38, green: 0.85, blue: 1.0, alpha: 0.40).setStroke()

    // 经线（椭圆簇）
    let meridianFactors: [CGFloat] = [0.28, 0.62, 1.0]
    for factor in meridianFactors {
        let rx = globeRadius * factor
        let meridian = NSBezierPath(
            ovalIn: CGRect(
                x: globeCenter.x - rx,
                y: globeCenter.y - globeRadius,
                width: rx * 2,
                height: globeRadius * 2
            )
        )
        meridian.lineWidth = 6.5
        meridian.stroke()
    }

    // 中央本初子午线
    let centerVLine = NSBezierPath()
    centerVLine.move(to: CGPoint(x: globeCenter.x, y: globeCenter.y - globeRadius))
    centerVLine.line(to: CGPoint(x: globeCenter.x, y: globeCenter.y + globeRadius))
    centerVLine.lineWidth = 6.5
    centerVLine.stroke()

    // 纬线（赤道与南北回归线）
    let latOffsets: [CGFloat] = [-150, -75, 0, 75, 150]
    for dy in latOffsets {
        let latLine = NSBezierPath()
        latLine.move(to: CGPoint(x: globeCenter.x - globeRadius, y: globeCenter.y + dy))
        latLine.line(to: CGPoint(x: globeCenter.x + globeRadius, y: globeCenter.y + dy))
        latLine.lineWidth = (dy == 0) ? 8.0 : 6.0
        latLine.stroke()
    }

    cg.restoreGState()

    // 地球外圈高亮描边
    NSColor(calibratedRed: 0.45, green: 0.88, blue: 1.0, alpha: 0.90).setStroke()
    spherePath.lineWidth = 10.0
    spherePath.stroke()

    // 4. 绘制悬浮定位坐标针 (Location Pin) 象征 "WhereAmIP"
    let pinTip = CGPoint(x: 512, y: 475)
    let pinCircleCenter = CGPoint(x: 512, y: 660)
    let pinRadius: CGFloat = 105.0

    // 定位针尖端下方的信号涟漪点
    let beaconRing = NSBezierPath(ovalIn: CGRect(x: 512 - 42, y: 475 - 16, width: 84, height: 32))
    NSColor(calibratedRed: 0.45, green: 0.95, blue: 1.0, alpha: 0.90).setStroke()
    beaconRing.lineWidth = 6.5
    beaconRing.stroke()

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 24,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor
    )

    let pinPath = NSBezierPath()
    pinPath.move(to: pinTip)
    pinPath.curve(
        to: CGPoint(x: pinCircleCenter.x - pinRadius, y: pinCircleCenter.y),
        controlPoint1: CGPoint(x: pinTip.x - 42, y: pinTip.y + 62),
        controlPoint2: CGPoint(x: pinCircleCenter.x - pinRadius, y: pinCircleCenter.y - 58)
    )
    pinPath.appendArc(
        withCenter: pinCircleCenter,
        radius: pinRadius,
        startAngle: 180,
        endAngle: 0,
        clockwise: true
    )
    pinPath.curve(
        to: pinTip,
        controlPoint1: CGPoint(x: pinCircleCenter.x + pinRadius, y: pinCircleCenter.y - 58),
        controlPoint2: CGPoint(x: pinTip.x + 42, y: pinTip.y + 62)
    )
    pinPath.close()

    cg.saveGState()
    pinPath.addClip()
    let pinColors = [
        NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.35, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.20, alpha: 1.0).cgColor
    ] as CFArray
    if let pinGrad = CGGradient(colorsSpace: colorSpace, colors: pinColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            pinGrad,
            start: CGPoint(x: 512, y: 475),
            end: CGPoint(x: 512, y: 770),
            options: []
        )
    }
    cg.restoreGState()

    // 定位针白色边框与内孔
    NSColor(calibratedWhite: 1.0, alpha: 0.96).setStroke()
    pinPath.lineWidth = 8.5
    pinPath.stroke()

    let innerHole = NSBezierPath(
        ovalIn: CGRect(
            x: pinCircleCenter.x - 42,
            y: pinCircleCenter.y - 42,
            width: 84,
            height: 84
        )
    )
    NSColor.white.setFill()
    innerHole.fill()
    cg.restoreGState()

    // 5. 底部胶囊徽章 "IP"
    let badgeRect = CGRect(x: 362, y: 175, width: 300, height: 112)
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 56, yRadius: 56)

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -8),
        blur: 18,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor
    )
    NSColor(calibratedRed: 0.04, green: 0.13, blue: 0.26, alpha: 0.95).setFill()
    badgePath.fill()
    cg.restoreGState()

    NSColor(calibratedRed: 0.42, green: 0.88, blue: 1.0, alpha: 0.90).setStroke()
    badgePath.lineWidth = 6.5
    badgePath.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let ipAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 66, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: 6.0,
        .paragraphStyle: paragraph
    ]
    let ipString = NSAttributedString(string: "IP", attributes: ipAttributes)
    let textSize = ipString.size()
    let textRect = CGRect(
        x: badgeRect.origin.x + 3.0,
        y: badgeRect.origin.y + (badgeRect.height - textSize.height) / 2.0 + 3.0,
        width: badgeRect.width,
        height: textSize.height
    )
    ipString.draw(in: textRect)

    cg.restoreGState()

    // 6. 圆角矩形玻璃内缘高光描边
    let innerBorder = NSBezierPath(roundedRect: squircleRect.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
    innerBorder.lineWidth = 4.0
    innerBorder.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconsetDir = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in specs {
    guard let rep = renderAppIcon(size: spec.pixels),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(spec.name)")
    }
    let outPath = "\(iconsetDir)/\(spec.name)"
    try pngData.write(to: URL(fileURLWithPath: outPath))
}

let icnsProcess = Process()
icnsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icnsProcess.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
try icnsProcess.run()
icnsProcess.waitUntilExit()

// 保留一张 512px PNG 用于 README 展示后清理临时 iconset
try? fm.removeItem(atPath: "Resources/AppIcon.png")
try? fm.copyItem(atPath: "\(iconsetDir)/icon_256x256@2x.png", toPath: "Resources/AppIcon.png")
try? fm.removeItem(atPath: iconsetDir)

print("✅ 已生成 Resources/AppIcon.icns 与 Resources/AppIcon.png")
