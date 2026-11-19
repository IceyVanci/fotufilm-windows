#if os(Windows)
import Foundation
#if canImport(FotufilmCore)
import FotufilmCore
#endif
#if canImport(FotufilmImaging)
import FotufilmImaging
#endif

/// Draws print frames without Apple's frameworks.
///
/// The geometry and the materials are the Mac app's: `PrintFramePlacement` places the photograph
/// in its aperture, `PrintFrameConfiguration` states what the material is made of, and
/// `PrintFrameRenderer.perforationOutline` is the die's own outline — all of them portable, so a
/// frame here is the same size, in the same place, as the Mac's. What differs is the rasterizer,
/// which is this file: an 8-bit RGBA canvas filled with the frame's colours.
///
/// Drawn: the paper, card or rebate, the photograph in its aperture, a filed carrier's rebate, and
/// the holes the material is cut with — perforations and a sheet's notches. Not drawn yet: the
/// edge printer's lettering and its DX bars, the lustre stipple, and an inverted scan's black
/// point, so a film border comes out as its material and its holes.
struct WindowsFrameCompositor: HostFrameCompositor {
    func frame(_ pixels: [UInt8], width: Int, height: Int, configuration: PrintFrameConfiguration,
               edge: UnexposedEdge.Margins?) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard configuration.frame != .none else { return (pixels, width, height) }
        let strip = configuration.frame.showsFilmStrip ? edge : nil
        let band = configuration.frame == .emulsion ? edge : strip
        if configuration.frame == .emulsion, band == nil { return nil }
        let film = band ?? UnexposedEdge.Margins(left: 0, right: 0, top: 0, bottom: 0)
        let photoWidth = width - film.left - film.right
        let photoHeight = height - film.top - film.bottom
        guard photoWidth > 0, photoHeight > 0, pixels.count >= width * height * 4 else { return nil }
        let placement = PrintFramePlacement.layout(width: photoWidth, height: photoHeight,
                                                   configuration: configuration, edge: band)
        let canvasWidth = Int(placement.size.width.rounded())
        let canvasHeight = Int(placement.size.height.rounded())
        guard canvasWidth > 0, canvasHeight > 0,
              canvasWidth * canvasHeight <= 250_000_000 else { return nil }
        // A developed strip is the frame's whole canvas; anything else surrounds the photograph.
        if strip != nil, width != canvasWidth || height != canvasHeight { return nil }

        let material = PrintFramePlacement.materialGeometry(configuration)
        var canvas = Canvas(width: canvasWidth, height: canvasHeight)
        let card = Configuration.card
        let base = Configuration.display(configuration.baseRGB)
        canvas.fill(rect: (x: 0, y: 0, width: canvasWidth, height: canvasHeight),
                    color: configuration.slideMount == nil ? base : card)

        // The photograph: the strip lays over the whole canvas, the emulsion border's band is the
        // film's own inside a paper margin, and everything else stands in its aperture.
        let imageX = Int(placement.image.x.rounded())
        let imageY = Int(placement.image.y.rounded())
        let top = canvasHeight - (imageY + photoHeight)
        if strip != nil {
            canvas.paste(pixels, width: width, height: height, at: 0, y: 0)
        } else if configuration.frame == .emulsion {
            canvas.paste(pixels, width: width, height: height,
                         at: imageX - film.left, y: top - film.top)
        } else {
            canvas.paste(pixels, width: width, height: height, at: imageX, y: top)
        }

        if let sheet = configuration.sheet, sheet.rebateMM > 0,
           configuration.frame.isPaperSheet {
            // The clear film's rebate printed around the photograph: the carrier's filed-out
            // line, or the paper's own printed border. Four sides of a ring.
            let inset = max(1, Int((sheet.rebateMM * placement.scale).rounded()))
            let rebate = Configuration.display(configuration.rebateRGB)
            canvas.fill(rect: (x: imageX - inset, y: top - inset, width: photoWidth + 2 * inset, height: inset), color: rebate)
            canvas.fill(rect: (x: imageX - inset, y: top + photoHeight, width: photoWidth + 2 * inset, height: inset), color: rebate)
            canvas.fill(rect: (x: imageX - inset, y: top, width: inset, height: photoHeight), color: rebate)
            canvas.fill(rect: (x: imageX + photoWidth, y: top, width: inset, height: photoHeight), color: rebate)
        }

        if let geometry = configuration.geometry, geometry.perforation != nil,
           configuration.frame.showsFilmStrip || configuration.frame == .emulsion {
            drawPerforations(&canvas, geometry: geometry, material: material.size,
                             placement: placement, color: Configuration.display(configuration.cutoutRGB))
        }
        if let geometry = configuration.geometry, geometry.isSheet,
           let code = configuration.sheetNotches {
            drawNotches(&canvas, size: material.size, code: code, placement: placement,
                        color: Configuration.display(configuration.cutoutRGB))
        }
        return (canvas.pixels, canvasWidth, canvasHeight)
    }

    // MARK: The material's holes

    private func drawPerforations(_ canvas: inout Canvas, geometry g: FilmBorderGeometry,
                                  material: PrintFramePlacement.Size,
                                  placement: PrintFramePlacement,
                                  color: (UInt8, UInt8, UInt8)) {
        guard let type = g.perforation else { return }
        let hole = type.dimensions
        let width = hole.width, height = hole.height
        let across = g.horizontalTransport ? g.heightMM : g.widthMM
        let along = g.horizontalTransport ? g.widthMM : g.heightMM
        let rows: [Double] = g.rows == 2 ? [hole.edge, across - hole.edge - width] : [hole.edge]
        let first = type == .sixteen ? 0 : g.pitchMM / 2
        for row in rows {
            var centre = first
            while centre <= along {
                let outline = Die.outline(
                    x: row, centre: centre, width: width, height: height,
                    radius: hole.radius, bellHowell: type == .bellHowell)
                let points = outline.map { point -> (Double, Double) in
                    // Across/along film transport into the material's millimetres, as the Mac
                    // renderer's rotated drawing context puts them.
                    let mx = g.horizontalTransport ? point.1 : point.0
                    let my = g.horizontalTransport ? material.height - point.0 : point.1
                    return CanvasPoint.material(mx, my, placement: placement, material: material)
                }
                canvas.fill(polygon: points, color: color)
                centre += g.pitchMM
            }
        }
    }

    private func drawNotches(_ canvas: inout Canvas, size: PrintFramePlacement.Size,
                             code: SheetFilmNotchCode, placement: PrintFramePlacement,
                             color: (UInt8, UInt8, UInt8)) {
        // The code occupies the upper right edge of an upright sheet, as the Mac renderer places
        // it: a 20 mm span, set back 10 mm from the corner.
        let span = 20.0
        let start = size.width - 10 - span
        for notch in code.notches {
            let x = start + notch.position * span
            let y = size.height - notch.depth * span
            let w = notch.width * span
            let h = notch.depth * span * 2
            let corners = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
            canvas.fill(polygon: corners.map {
                CanvasPoint.material($0.0, $0.1, placement: placement, material: size)
            }, color: color)
        }
    }

    /// The material's colours, in Display P3 codes as the encoder writes them.
    private enum Configuration {
        static let card: (UInt8, UInt8, UInt8) = display(SIMD3(repeating: 0.86))

        /// Display-linear P3 to the 8-bit encoding the stills carry.
        static func display(_ rgb: SIMD3<Float>) -> (UInt8, UInt8, UInt8) {
            func code(_ value: Float) -> UInt8 {
                let encoded = ColorScience.linearToSrgb(max(0, value))
                return UInt8(min(255, max(0, (encoded * 255).rounded())))
            }
            return (code(rgb.x), code(rgb.y), code(rgb.z))
        }
    }
}

/// The perforation die's outline in millimetres across and along the film, traced every 0.04 mm:
/// a rounded KS rectangle, or BH's circle clipped by two flats. `PrintFrameRenderer` draws the
/// same outline, and web/src/print-frame-renderer.js traces it again for the browser.
enum Die {
    enum Piece {
        case line((Double, Double), (Double, Double))
        case arc((Double, Double), radius: Double, from: Double, to: Double)

        var length: Double {
            switch self {
            case let .line(a, b): return ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            case let .arc(_, r, a0, a1): return r * abs(a1 - a0)
            }
        }

        func point(_ t: Double) -> (Double, Double) {
            switch self {
            case let .line(a, b): return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
            case let .arc(c, r, a0, a1):
                let angle = a0 + (a1 - a0) * t
                return (c.0 + cos(angle) * r, c.1 + sin(angle) * r)
            }
        }
    }

    static func outline(x: Double, centre: Double, width: Double, height: Double,
                        radius: Double, bellHowell: Bool) -> [(Double, Double)] {
        let y = centre - height / 2
        var pieces: [Piece]
        if bellHowell {
            let r = width / 2, half = height / 2
            let c = (x + r, centre)
            let flat = asin(min(1, half / r)), run = r * cos(flat)
            pieces = [.line((c.0 - run, c.1 - half), (c.0 + run, c.1 - half)),
                      .arc(c, radius: r, from: -flat, to: flat),
                      .line((c.0 + run, c.1 + half), (c.0 - run, c.1 + half)),
                      .arc(c, radius: r, from: .pi - flat, to: .pi + flat)]
        } else {
            let r = min(radius, width / 2, height / 2)
            pieces = [.line((x + r, y), (x + width - r, y)),
                      .arc((x + width - r, y + r), radius: r, from: -.pi / 2, to: 0),
                      .line((x + width, y + r), (x + width, y + height - r)),
                      .arc((x + width - r, y + height - r), radius: r, from: 0, to: .pi / 2),
                      .line((x + width - r, y + height), (x + r, y + height)),
                      .arc((x + r, y + height - r), radius: r, from: .pi / 2, to: .pi),
                      .line((x, y + height - r), (x, y + r)),
                      .arc((x + r, y + r), radius: r, from: .pi, to: 3 * .pi / 2)]
        }
        var outline: [(Double, Double)] = []
        for piece in pieces where piece.length > 0 {
            let steps = max(1, Int((piece.length / 0.04).rounded(.up)))
            for step in 0..<steps {
                outline.append(piece.point(Double(step) / Double(steps)))
            }
        }
        return outline
    }
}

/// A material's millimetre into the canvas's pixels, the origin at the top left.
private enum CanvasPoint {
    /// The placement's scale and rotation, as the Mac renderer's drawing context applies them.
    static func material(_ x: Double, _ y: Double, placement: PrintFramePlacement,
                         material: PrintFramePlacement.Size) -> (Double, Double) {
        let scale = placement.scale
        let canvasHeight = placement.size.height
        if placement.rotated {
            return ((material.height - y) * scale, canvasHeight - x * scale)
        }
        return (x * scale, canvasHeight - y * scale)
    }
}

/// An 8-bit RGBA canvas filled with opaque colours, anti-aliased by four samples a pixel.
private struct Canvas {
    var pixels: [UInt8]
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 255, count: width * height * 4)
    }

    mutating func fill(rect: (x: Int, y: Int, width: Int, height: Int),
                       color: (UInt8, UInt8, UInt8)) {
        let x0 = max(0, rect.x), y0 = max(0, rect.y)
        let x1 = min(width, rect.x + rect.width), y1 = min(height, rect.y + rect.height)
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            var index = (y * width + x0) * 4
            for _ in x0..<x1 {
                pixels[index] = color.0
                pixels[index + 1] = color.1
                pixels[index + 2] = color.2
                index += 4
            }
        }
    }

    /// The photograph's own pixels, clipped to the canvas.
    mutating func paste(_ source: [UInt8], width sourceWidth: Int, height sourceHeight: Int,
                        at x: Int, y: Int) {
        let x0 = max(0, -x), y0 = max(0, -y)
        let x1 = min(sourceWidth, width - x), y1 = min(sourceHeight, height - y)
        guard x0 < x1, y0 < y1 else { return }
        for row in y0..<y1 {
            let from = (row * sourceWidth + x0) * 4
            let to = ((row + y) * width + x + x0) * 4
            let count = (x1 - x0) * 4
            pixels.replaceSubrange(to..<(to + count), with: source[from..<(from + count)])
        }
    }

    /// Fills a closed polygon, four samples a pixel, so a punched hole's edge is smooth.
    mutating func fill(polygon: [(Double, Double)], color: (UInt8, UInt8, UInt8)) {
        guard polygon.count >= 3 else { return }
        let xs = polygon.map(\.0), ys = polygon.map(\.1)
        let minX = max(0, Int(xs.min()!.rounded(.down)))
        let maxX = min(width - 1, Int(xs.max()!.rounded(.up)))
        let minY = max(0, Int(ys.min()!.rounded(.down)))
        let maxY = min(height - 1, Int(ys.max()!.rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        let samples = [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
        for y in minY...maxY {
            for x in minX...maxX {
                var covered = 0
                for sample in samples {
                    if Canvas.contains(polygon, x: Double(x) + sample.0, y: Double(y) + sample.1) {
                        covered += 1
                    }
                }
                guard covered > 0 else { continue }
                blend(x: x, y: y, color: color, coverage: Double(covered) / 4)
            }
        }
    }

    private mutating func blend(x: Int, y: Int, color: (UInt8, UInt8, UInt8), coverage: Double) {
        guard coverage > 0 else { return }
        let index = (y * width + x) * 4
        let before = Double(pixels[index]),
            green = Double(pixels[index + 1]), blue = Double(pixels[index + 2])
        pixels[index] = UInt8((Double(color.0) * coverage + before * (1 - coverage)).rounded())
        pixels[index + 1] = UInt8((Double(color.1) * coverage + green * (1 - coverage)).rounded())
        pixels[index + 2] = UInt8((Double(color.2) * coverage + blue * (1 - coverage)).rounded())
    }

    private static func contains(_ polygon: [(Double, Double)], x: Double, y: Double) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.1 > y) != (b.1 > y),
               x < (b.0 - a.0) * (y - a.1) / (b.1 - a.1) + a.0 {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
#endif
