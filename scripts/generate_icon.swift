#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct IconSpec {
    let filename: String
    let pixelSize: Int
}

let iconSpecs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", pixelSize: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixelSize: 32),
    IconSpec(filename: "icon_32x32.png", pixelSize: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixelSize: 64),
    IconSpec(filename: "icon_128x128.png", pixelSize: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixelSize: 256),
    IconSpec(filename: "icon_256x256.png", pixelSize: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixelSize: 512),
    IconSpec(filename: "icon_512x512.png", pixelSize: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixelSize: 1024),
]

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum PrismMetrics {
    static let squircleSize: CGFloat = 824
    static let squircleCornerRadius: CGFloat = 185

    // Outer equilateral prism vertices (side = 436, slightly shifted left to balance outgoing rays)
    static let vertexTop = CGPoint(x: 502.0, y: 320.0)
    static let vertexBottomLeft = CGPoint(x: 284.0, y: 697.6)
    static let vertexBottomRight = CGPoint(x: 720.0, y: 697.6)
    static let outerVertices = [vertexTop, vertexBottomLeft, vertexBottomRight]
    static let outerCornerRadius: CGFloat = 24.0

    // Incenter C = (502.0, 571.73)
    static let incenter = CGPoint(
        x: (vertexTop.x + vertexBottomLeft.x + vertexBottomRight.x) / 3.0,
        y: (vertexTop.y + vertexBottomLeft.y + vertexBottomRight.y) / 3.0
    )

    static let innerScale: CGFloat = 0.855
    static let innerCornerRadius: CGFloat = 15.0

    static let innerVertices: [CGPoint] = outerVertices.map { v in
        CGPoint(
            x: incenter.x + innerScale * (v.x - incenter.x),
            y: incenter.y + innerScale * (v.y - incenter.y)
        )
    }

    // Snell's-law incident and refracted coordinates
    static let pStart = CGPoint(x: 108.0, y: 567.0)
    static let pIn = CGPoint(x: 397.4, y: 501.2)

    static let pOut1 = CGPoint(x: 601.2, y: 491.8) // Ice-Emerald (On-Device)
    static let pOut2 = CGPoint(x: 611.0, y: 508.8) // Glacier-Sapphire (Apple PCC)
    static let pOut3 = CGPoint(x: 620.8, y: 525.8) // Champagne-Gold (External AI)

    static let pEnd1 = CGPoint(x: 916.0, y: 550.2)
    static let pEnd2 = CGPoint(x: 916.0, y: 616.9)
    static let pEnd3 = CGPoint(x: 916.0, y: 685.9)

    static func roundedTriangleCGPath(vertices: [CGPoint], cornerRadius: CGFloat) -> CGPath {
        precondition(vertices.count == 3)
        let p0 = vertices[0]
        let p1 = vertices[1]
        let p2 = vertices[2]
        let mid01 = CGPoint(x: (p0.x + p1.x) / 2.0, y: (p0.y + p1.y) / 2.0)

        let path = CGMutablePath()
        path.move(to: mid01)
        path.addArc(tangent1End: p1, tangent2End: p2, radius: cornerRadius)
        path.addArc(tangent1End: p2, tangent2End: p0, radius: cornerRadius)
        path.addArc(tangent1End: p0, tangent2End: p1, radius: cornerRadius)
        path.closeSubpath()
        return path
    }

    /// Point on the rounded fillet along the angle bisector toward the equilateral incenter.
    static func roundedApex(from vertex: CGPoint, filletRadius: CGFloat) -> CGPoint {
        let dx = incenter.x - vertex.x
        let dy = incenter.y - vertex.y
        let dist = hypot(dx, dy)
        guard dist > 0 else { return vertex }
        return CGPoint(
            x: vertex.x + (dx / dist) * filletRadius,
            y: vertex.y + (dy / dist) * filletRadius
        )
    }
}

struct RoundedTriangleShape: Shape {
    let vertices: [CGPoint]
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(PrismMetrics.roundedTriangleCGPath(vertices: vertices, cornerRadius: cornerRadius))
    }
}

struct PrismComplementMaskShape: Shape {
    let vertices: [CGPoint]
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addPath(Path(PrismMetrics.roundedTriangleCGPath(vertices: vertices, cornerRadius: cornerRadius)))
        return path
    }
}

struct InternalCausticFanShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 397.4, y: 498.5))
        path.addLine(to: CGPoint(x: 601.2, y: 487.0))
        path.addLine(to: CGPoint(x: 620.8, y: 530.5))
        path.addLine(to: CGPoint(x: 397.4, y: 504.0))
        path.closeSubpath()
        return path
    }
}

struct RaySegment: View {
    let from: CGPoint
    let to: CGPoint
    let haloWidth: CGFloat
    let haloStartColor: Color
    let haloEndColor: Color
    let silkWidth: CGFloat
    let silkStartColor: Color
    let silkEndColor: Color
    let coreWidth: CGFloat
    let coreStartColor: Color
    let coreEndColor: Color

    private var linePath: Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    var body: some View {
        ZStack {
            linePath
                .stroke(
                    LinearGradient(
                        colors: [haloStartColor, haloEndColor],
                        startPoint: UnitPoint(x: from.x / 1024.0, y: from.y / 1024.0),
                        endPoint: UnitPoint(x: to.x / 1024.0, y: to.y / 1024.0)
                    ),
                    style: StrokeStyle(lineWidth: haloWidth, lineCap: .round)
                )
                .blur(radius: 10.0)

            linePath
                .stroke(
                    LinearGradient(
                        colors: [silkStartColor, silkEndColor],
                        startPoint: UnitPoint(x: from.x / 1024.0, y: from.y / 1024.0),
                        endPoint: UnitPoint(x: to.x / 1024.0, y: to.y / 1024.0)
                    ),
                    style: StrokeStyle(lineWidth: silkWidth, lineCap: .round)
                )
                .blur(radius: 1.8)

            linePath
                .stroke(
                    LinearGradient(
                        colors: [coreStartColor, coreEndColor],
                        startPoint: UnitPoint(x: from.x / 1024.0, y: from.y / 1024.0),
                        endPoint: UnitPoint(x: to.x / 1024.0, y: to.y / 1024.0)
                    ),
                    style: StrokeStyle(lineWidth: coreWidth, lineCap: .butt)
                )
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Matte Space Black Squircle + Beveled Liquid Glass Optical Prism Dispersion macOS Icon.
struct AppleLensPrismIconView: View {
    private var outerPrism: RoundedTriangleShape {
        RoundedTriangleShape(
            vertices: PrismMetrics.outerVertices,
            cornerRadius: PrismMetrics.outerCornerRadius
        )
    }

    private var innerPrism: RoundedTriangleShape {
        RoundedTriangleShape(
            vertices: PrismMetrics.innerVertices,
            cornerRadius: PrismMetrics.innerCornerRadius
        )
    }

    var body: some View {
        ZStack {
            // Layer 1A: Continuous Apple Squircle with macOS dual-layer drop shadow
            RoundedRectangle(cornerRadius: PrismMetrics.squircleCornerRadius, style: .continuous)
                .fill(Color(hex: 0x060709))
                .frame(width: PrismMetrics.squircleSize, height: PrismMetrics.squircleSize)
                .shadow(color: Color.black.opacity(0.42), radius: 18, x: 0, y: 12)
                .shadow(color: Color.black.opacity(0.24), radius: 3, x: 0, y: 2)

            // Interior clipped to 824x824 continuous squircle
            ZStack {
                // Layer 1B: Matte Space Black Titanium background + subtle ambient studio falloff
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x181A1F), location: 0.0),
                        .init(color: Color(hex: 0x0D0F13), location: 0.52),
                        .init(color: Color(hex: 0x060709), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 1024, height: 1024)

                RadialGradient(
                    colors: [
                        Color(hex: 0x94A3B8, opacity: 0.08),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 525.0 / 1024.0, y: 520.0 / 1024.0),
                    startRadius: 12,
                    endRadius: 330
                )
                .frame(width: 1024, height: 1024)

                // Layer 2: Prism Cast Shadow & Floor Caustic
                outerPrism
                    .fill(Color.black.opacity(0.65))
                    .offset(x: 0, y: 20)
                    .blur(radius: 22)

                outerPrism
                    .fill(Color(hex: 0x38BDF8, opacity: 0.06))
                    .offset(x: 24, y: 18)
                    .blur(radius: 26)

                // Layer 3: External Collimated Beams (masked strictly outside outerPrism)
                externalBeams
                    .mask {
                        PrismComplementMaskShape(
                            vertices: PrismMetrics.outerVertices,
                            cornerRadius: PrismMetrics.outerCornerRadius
                        )
                        .fill(Color.white, style: FillStyle(eoFill: true))
                        .frame(width: 1024, height: 1024)
                    }

                // Layer 4: 3D Liquid Glass Prism interior (clipped to outerPrism)
                liquidGlassPrismInterior
                    .clipShape(outerPrism)

                // Layer 5: Polished Crystal Rim, Interface Glints & Squircle Milled Bevel
                interfaceGlintsAndRim

                RoundedRectangle(cornerRadius: PrismMetrics.squircleCornerRadius, style: .continuous)
                    .inset(by: 1.0)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.19), location: 0.0),
                                .init(color: Color.white.opacity(0.04), location: 0.42),
                                .init(color: Color.black.opacity(0.48), location: 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.0
                    )
                    .frame(width: PrismMetrics.squircleSize, height: PrismMetrics.squircleSize)
            }
            .frame(width: PrismMetrics.squircleSize, height: PrismMetrics.squircleSize)
            .clipShape(RoundedRectangle(cornerRadius: PrismMetrics.squircleCornerRadius, style: .continuous))
        }
        .frame(width: 1024, height: 1024)
        .background(Color.clear)
    }

    private var externalBeams: some View {
        ZStack {
            // Incident Cold-White Beam (fades smoothly in from P_start to P_in)
            RaySegment(
                from: PrismMetrics.pStart,
                to: PrismMetrics.pIn,
                haloWidth: 22.0,
                haloStartColor: Color(hex: 0xBAE6FD, opacity: 0.0),
                haloEndColor: Color(hex: 0xBAE6FD, opacity: 0.22),
                silkWidth: 6.2,
                silkStartColor: Color(hex: 0xE0F2FE, opacity: 0.02),
                silkEndColor: Color(hex: 0xE0F2FE, opacity: 0.65),
                coreWidth: 2.1,
                coreStartColor: Color.white.opacity(0.04),
                coreEndColor: Color.white.opacity(0.96)
            )

            // Beam 1: Ice-Emerald (On-Device ANE)
            RaySegment(
                from: PrismMetrics.pOut1,
                to: PrismMetrics.pEnd1,
                haloWidth: 22.0,
                haloStartColor: Color(hex: 0x10B981, opacity: 0.22),
                haloEndColor: Color(hex: 0x10B981, opacity: 0.0),
                silkWidth: 6.0,
                silkStartColor: Color(hex: 0x34D399, opacity: 0.68),
                silkEndColor: Color(hex: 0x34D399, opacity: 0.02),
                coreWidth: 2.0,
                coreStartColor: Color(hex: 0xECFDF5, opacity: 0.94),
                coreEndColor: Color(hex: 0xECFDF5, opacity: 0.03)
            )

            // Beam 2: Glacier-Sapphire (Apple PCC)
            RaySegment(
                from: PrismMetrics.pOut2,
                to: PrismMetrics.pEnd2,
                haloWidth: 24.0,
                haloStartColor: Color(hex: 0x0284C7, opacity: 0.24),
                haloEndColor: Color(hex: 0x0284C7, opacity: 0.0),
                silkWidth: 6.4,
                silkStartColor: Color(hex: 0x38BDF8, opacity: 0.72),
                silkEndColor: Color(hex: 0x38BDF8, opacity: 0.02),
                coreWidth: 2.15,
                coreStartColor: Color(hex: 0xF0F9FF, opacity: 0.95),
                coreEndColor: Color(hex: 0xF0F9FF, opacity: 0.03)
            )

            // Beam 3: Warm Champagne-Gold (External LLM)
            RaySegment(
                from: PrismMetrics.pOut3,
                to: PrismMetrics.pEnd3,
                haloWidth: 22.0,
                haloStartColor: Color(hex: 0xD97706, opacity: 0.22),
                haloEndColor: Color(hex: 0xD97706, opacity: 0.0),
                silkWidth: 6.0,
                silkStartColor: Color(hex: 0xFBBF24, opacity: 0.68),
                silkEndColor: Color(hex: 0xFBBF24, opacity: 0.02),
                coreWidth: 2.0,
                coreStartColor: Color(hex: 0xFFFBEB, opacity: 0.94),
                coreEndColor: Color(hex: 0xFFFBEB, opacity: 0.03)
            )
        }
        .frame(width: 1024, height: 1024)
        .blendMode(.screen)
    }

    private var liquidGlassPrismInterior: some View {
        ZStack {
            // Frosted dark-flint Liquid Glass body gradient
            outerPrism
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0xE2E8F0, opacity: 0.18), location: 0.0),
                            .init(color: Color(hex: 0x94A3B8, opacity: 0.07), location: 0.36),
                            .init(color: Color(hex: 0x0F172A, opacity: 0.40), location: 0.74),
                            .init(color: Color(hex: 0xCBD5E1, opacity: 0.13), location: 1.0),
                        ],
                        startPoint: UnitPoint(x: 340.0 / 1024.0, y: 340.0 / 1024.0),
                        endPoint: UnitPoint(x: 680.0 / 1024.0, y: 700.0 / 1024.0)
                    )
                )

            // Left-facet studio specular wash
            outerPrism
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.clear,
                        ],
                        startPoint: UnitPoint(x: 350.0 / 1024.0, y: 430.0 / 1024.0),
                        endPoint: UnitPoint(x: 465.0 / 1024.0, y: 505.0 / 1024.0)
                    )
                )

            // Internal Dispersion Caustic Fan: left cold-white fanning into 3 spectral bands
            InternalCausticFanShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x6EE7B7, opacity: 0.34), location: 0.0),
                            .init(color: Color(hex: 0x7DD3FC, opacity: 0.36), location: 0.50),
                            .init(color: Color(hex: 0xFDE68A, opacity: 0.34), location: 1.0),
                        ],
                        startPoint: UnitPoint(x: 605.0 / 1024.0, y: 486.0 / 1024.0),
                        endPoint: UnitPoint(x: 618.0 / 1024.0, y: 531.0 / 1024.0)
                    )
                )
                .overlay(
                    InternalCausticFanShape()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: 0xF8FAFC, opacity: 0.52), location: 0.0),
                                    .init(color: Color(hex: 0xF8FAFC, opacity: 0.16), location: 0.45),
                                    .init(color: Color.clear, location: 1.0),
                                ],
                                startPoint: UnitPoint(x: 397.4 / 1024.0, y: 501.2 / 1024.0),
                                endPoint: UnitPoint(x: 611.0 / 1024.0, y: 508.8 / 1024.0)
                            )
                        )
                )
                .blur(radius: 5.5)
                .blendMode(.screen)

            // Subtle internal connecting rays (P_in -> P_out1/2/3)
            internalRay(to: PrismMetrics.pOut1, endTint: Color(hex: 0x6EE7B7, opacity: 0.52))
            internalRay(to: PrismMetrics.pOut2, endTint: Color(hex: 0x7DD3FC, opacity: 0.56))
            internalRay(to: PrismMetrics.pOut3, endTint: Color(hex: 0xFDE68A, opacity: 0.52))

            // Inner 3D Beveled Table
            innerPrism
                .fill(Color.black.opacity(0.08))

            innerPrism
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.24), location: 0.0),
                            .init(color: Color(hex: 0xBAE6FD, opacity: 0.14), location: 0.55),
                            .init(color: Color.white.opacity(0.06), location: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.3
                )

            // Three faint vertex-chamfer ridge lines connecting outer apexes to inner table
            Canvas { context, _ in
                for (outerV, innerV) in zip(PrismMetrics.outerVertices, PrismMetrics.innerVertices) {
                    let start = PrismMetrics.roundedApex(from: outerV, filletRadius: PrismMetrics.outerCornerRadius)
                    let end = PrismMetrics.roundedApex(from: innerV, filletRadius: PrismMetrics.innerCornerRadius)
                    var ridge = Path()
                    ridge.move(to: start)
                    ridge.addLine(to: end)
                    context.stroke(ridge, with: .color(Color.white.opacity(0.12)), lineWidth: 1.0)
                }
            }
            .frame(width: 1024, height: 1024)
        }
        .frame(width: 1024, height: 1024)
    }

    private func internalRay(to end: CGPoint, endTint: Color) -> some View {
        var path = Path()
        path.move(to: PrismMetrics.pIn)
        path.addLine(to: end)
        return path
            .stroke(
                LinearGradient(
                    colors: [Color(hex: 0xF8FAFC, opacity: 0.55), endTint],
                    startPoint: UnitPoint(x: PrismMetrics.pIn.x / 1024.0, y: PrismMetrics.pIn.y / 1024.0),
                    endPoint: UnitPoint(x: end.x / 1024.0, y: end.y / 1024.0)
                ),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .blur(radius: 0.6)
            .blendMode(.screen)
    }

    private var interfaceGlintsAndRim: some View {
        ZStack {
            // Left-wall air-glass entry glint aligned to the 60° facet
            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: 3.5, height: 22.0)
                .rotationEffect(.degrees(30))
                .position(PrismMetrics.pIn)
                .blur(radius: 2.0)
                .blendMode(.screen)

            // Right-wall glass-air dispersion exit glints aligned to the -60° facet
            facetExitGlint(at: PrismMetrics.pOut1, tint: Color(hex: 0xA7F3D0, opacity: 0.75))
            facetExitGlint(at: PrismMetrics.pOut2, tint: Color(hex: 0xBAE6FD, opacity: 0.75))
            facetExitGlint(at: PrismMetrics.pOut3, tint: Color(hex: 0xFDE68A, opacity: 0.75))

            // Polished Liquid Glass outer rim stroke
            outerPrism
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.62), location: 0.0),
                            .init(color: Color(hex: 0xE2E8F0, opacity: 0.34), location: 0.35),
                            .init(color: Color(hex: 0xBAE6FD, opacity: 0.38), location: 0.68),
                            .init(color: Color(hex: 0x94A3B8, opacity: 0.20), location: 1.0),
                        ],
                        startPoint: UnitPoint(x: 340.0 / 1024.0, y: 315.0 / 1024.0),
                        endPoint: UnitPoint(x: 700.0 / 1024.0, y: 710.0 / 1024.0)
                    ),
                    lineWidth: 2.2
                )
        }
        .frame(width: 1024, height: 1024)
    }

    private func facetExitGlint(at point: CGPoint, tint: Color) -> some View {
        Capsule()
            .fill(tint)
            .frame(width: 3.0, height: 14.0)
            .rotationEffect(.degrees(-30))
            .position(point)
            .blur(radius: 1.8)
            .blendMode(.screen)
    }
}

func downsampleCGImage(_ source: CGImage, to pixelSize: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try pngData.write(to: url, options: .atomic)
}

func main() throws {
    guard CommandLine.arguments.count >= 2 else {
        fputs("Usage: swift scripts/generate_icon.swift <output-icns-path>\n", stderr)
        exit(1)
    }

    let outputICNSURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let fm = FileManager.default
    try fm.createDirectory(at: outputICNSURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let masterCG: CGImage = try MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: AppleLensPrismIconView())
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
        guard let image = renderer.cgImage else {
            throw NSError(
                domain: "generate_icon",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "SwiftUI ImageRenderer failed to produce 1024x1024 CGImage"]
            )
        }
        return image
    }

    let tempIconsetURL = fm.temporaryDirectory
        .appendingPathComponent("AppleLens-\(UUID().uuidString).iconset", isDirectory: true)
    try fm.createDirectory(at: tempIconsetURL, withIntermediateDirectories: true)
    defer {
        try? fm.removeItem(at: tempIconsetURL)
    }

    for spec in iconSpecs {
        guard let scaledImage = (spec.pixelSize == 1024 ? masterCG : downsampleCGImage(masterCG, to: spec.pixelSize)) else {
            throw NSError(
                domain: "generate_icon",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to downsample \(spec.filename)"]
            )
        }
        try writePNG(scaledImage, to: tempIconsetURL.appendingPathComponent(spec.filename))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", tempIconsetURL.path, "-o", outputICNSURL.path]

    let errPipe = Pipe()
    iconutil.standardError = errPipe

    try iconutil.run()
    iconutil.waitUntilExit()

    guard iconutil.terminationStatus == 0 else {
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(
            domain: "generate_icon",
            code: Int(iconutil.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed: \(errText)"]
        )
    }

    print("Generated icon: \(outputICNSURL.path)")
}

do {
    try main()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
