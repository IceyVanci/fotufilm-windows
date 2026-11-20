#if os(Windows)
import Foundation
import WinSDK
#if canImport(FotufilmCore)
import FotufilmCore
#endif
#if canImport(FotufilmImaging)
import FotufilmImaging
#endif

/// Draws print frames without Apple's frameworks.
///
/// The geometry and the materials are the Mac app's: PrintFramePlacement places the photograph in
/// its aperture, PrintFrameConfiguration states what the material is made of, and
/// PrintFrameRenderer states where every ink mark, hole and texture goes - all of it portable, so
/// a frame here is the same size, in the same place, as the Mac's. What differs is the rasterizer,
/// which is this file: a Canvas of encoded Display P3 samples, 16 bits when the export asked for
/// 16 bits and 8 when it asked for 8.
///
/// Drawn: the paper, card or rebate, the photograph in its aperture, a filed carrier's rebate, an
/// inverted scan's black point, a sheet's lustre, the photograph's material and its holes, and a
/// developed strip's edge printing and DX bars. The lettering is the system's vector type, as the
/// Mac's is: no manufacturer font is shipped.
struct WindowsFrameCompositor: HostFrameCompositor {
    func frame(_ pixels: [UInt8], width: Int, height: Int, configuration: PrintFrameConfiguration,
               edge: UnexposedEdge.Margins?) -> (pixels: [UInt8], width: Int, height: Int)? {
        draw(pixels, width: width, height: height, configuration: configuration, edge: edge)
    }

    func frame(_ pixels: [UInt16], width: Int, height: Int, configuration: PrintFrameConfiguration,
               edge: UnexposedEdge.Margins?) -> (pixels: [UInt16], width: Int, height: Int)? {
        draw(pixels, width: width, height: height, configuration: configuration, edge: edge)
    }

    private func draw<Code: CanvasCode>(
        _ pixels: [Code], width: Int, height: Int, configuration: PrintFrameConfiguration,
        edge: UnexposedEdge.Margins?
    ) -> (pixels: [Code], width: Int, height: Int)? {
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
        // A 16-bit canvas is twice the bytes per pixel of an 8-bit one, so it holds fewer of them.
        let ceiling = Code.levels > 256 ? 90_000_000 : 250_000_000
        guard canvasWidth > 0, canvasHeight > 0, canvasWidth * canvasHeight <= ceiling else {
            return nil
        }
        // A developed strip is the frame's whole canvas; anything else surrounds the photograph.
        if strip != nil, width != canvasWidth || height != canvasHeight { return nil }

        let material = PrintFramePlacement.materialGeometry(configuration)
        let scale = placement.scale
        var canvas = Canvas<Code>(width: canvasWidth, height: canvasHeight)
        let base = Configuration.display(configuration.baseRGB)
        // The card of a slide mount covers the whole canvas; the Emulsion Border's film reaches
        // past its carrier, where the paper saw no light, so that margin is the paper as
        // developed - the photograph's own corner.
        if let band, band.carrier > 0, let paper = Canvas<Code>.corner(pixels, width: width) {
            canvas.fill(rect: (0, 0, canvasWidth, canvasHeight), colour: paper, mode: .normal)
        } else {
            canvas.fill(rect: (0, 0, canvasWidth, canvasHeight),
                        colour: configuration.slideMount == nil ? base : Configuration.card,
                        mode: .normal)
        }

        // The photograph's rectangle in the material's millimetres, the origin at its lower left.
        func photoRect() -> (x: Double, y: Double, width: Double, height: Double) {
            let px = placement.image.x, py = placement.image.y
            let pw = Double(photoWidth), ph = Double(photoHeight)
            if placement.rotated {
                return (x: (Double(canvasHeight) - (py + ph)) / scale,
                        y: material.size.height - (px + pw) / scale,
                        width: ph / scale, height: pw / scale)
            }
            return (x: px / scale, y: (Double(canvasHeight) - (py + ph)) / scale,
                    width: pw / scale, height: ph / scale)
        }

        // A point of the material's millimetres on the canvas.
        func place(_ x: Double, _ y: Double) -> (Double, Double) {
            CanvasPoint.material(x, y, placement: placement, material: material.size)
        }

        // 135 exposed to its edges in a medium-format camera: the picture lies under the edge
        // printing and is punched with the perforations, so it goes down first.
        let exposed = configuration.geometry?.exposesEdges == true
        if strip == nil, exposed {
            canvas.paste(pixels, width: width, height: height, at: 0, y: 0)
        }
        if strip != nil {
            canvas.paste(pixels, width: width, height: height, at: 0, y: 0)
            if configuration.frame == .filmPositive {
                // The inverted scan's black point sits just past the developed base, so the film
                // stands a little above the open holes, its grain kept.
                canvas.liftBlackPoint(by: configuration.baseRGB)
            }
        }

        let imageX = placement.image.x, imageY = placement.image.y
        let top = Double(canvasHeight) - (imageY + Double(photoHeight))

        if configuration.frame == .emulsion || configuration.frame.isPlainMount
            || configuration.canvas != nil {
            // The base fill is the whole mount or canvas; the Emulsion Border's band is part of
            // the film that went down above.
        } else if let mount = configuration.slideMount {
            // The die-cut aperture, filled with the mount's base: visible around a photograph
            // smaller than the window it is seen through. The Mac's faint edge shadow lands under
            // the photograph there as here, so it cannot show.
            let aperture = (x: (mount.mountMM - mount.apertureWidth) / 2,
                            y: (mount.mountMM - mount.apertureHeight) / 2,
                            width: mount.apertureWidth, height: mount.apertureHeight)
            canvas.fill(polygon: RoundedRect.points(aperture, radius: mount.cornerRadiusMM,
                                                     in: place),
                        colour: base, mode: .normal)
        } else if let sheet = configuration.sheet {
            let photo = photoRect()
            if sheet.rebateMM > 0 {
                drawCarrierRebate(&canvas, photo: photo, width: sheet.rebateMM,
                                  colour: Configuration.display(configuration.rebateRGB),
                                  place: place)
            }
            if configuration.hasLustre {
                drawLustre(&canvas, size: material.size, scale: scale,
                           excluding: (x: photo.x - sheet.rebateMM, y: photo.y - sheet.rebateMM,
                                       width: photo.width + 2 * sheet.rebateMM,
                                       height: photo.height + 2 * sheet.rebateMM))
            }
        } else if let geometry = configuration.geometry {
            // On a developed strip a negative's letters pass a share of the rebate's light, grain
            // and glow included; lighter letters are laid over the dark rebate. Over a picture
            // exposed to the edges the edge printer's exposure adds to the camera's, and the
            // denser of the two develops, nearly: a negative's letters darken it, lighter letters
            // lighten.
            func marking(_ rgb: SIMD3<Float>, _ transmission: SIMD3<Float>?) -> (Colour, Blend) {
                if exposed {
                    return (Configuration.display(rgb), transmission == nil ? .lighten : .darken)
                }
                let shared = strip == nil ? nil : transmission
                return (Configuration.display(shared ?? rgb),
                        strip == nil ? .normal : shared == nil ? .screen : .multiply)
            }
            if let printing = configuration.edgePrinting {
                let (colour, blend) = marking(configuration.edgeRGB, configuration.edgeTransmission)
                drawEdgePrinting(&canvas, printing: printing, colour: colour, mode: blend,
                                 place: place)
            }
            if !configuration.edgeBars.isEmpty {
                let (colour, blend) = marking(configuration.barcodeRGB,
                                              configuration.barcodeTransmission)
                drawEdgeBars(&canvas, bars: configuration.edgeBars, colour: colour, mode: blend,
                             place: place)
            }
            let cutout = Configuration.display(configuration.cutoutRGB)
            drawPerforations(&canvas, geometry: geometry, material: material.size,
                             placement: placement, colour: cutout)
            if geometry.isSheet, let code = configuration.sheetNotches {
                drawNotches(&canvas, size: material.size, code: code, placement: placement,
                            colour: cutout)
            }
        }

        if strip == nil, !exposed {
            canvas.paste(pixels, width: width, height: height, at: Int(imageX.rounded()),
                         y: Int(top.rounded()))
        }
        return (canvas.pixels, canvasWidth, canvasHeight)
    }

    // MARK: The film's own marks

    /// The edge printer's lettering: each mark's ink stretched to the mark's millimetre box, as
    /// the Mac stretches the glyphs' bounding box.
    private func drawEdgePrinting<Code: CanvasCode>(
        _ canvas: inout Canvas<Code>, printing: FilmEdgePrinting, colour: Colour, mode: Blend,
        place: (Double, Double) -> (Double, Double)
    ) {
        for mark in printing.marks {
            guard let mask = Lettering.mask(mark.text) else { continue }
            let left = mark.xMM, bottom = mark.yMM
            let right = mark.xMM + mark.widthMM, top = mark.yMM + mark.heightMM
            let a = place(left, top), b = place(right, top), c = place(left, bottom)
            let du = (x: b.0 - a.0, y: b.1 - a.1)
            let dv = (x: c.0 - a.0, y: c.1 - a.1)
            let determinant = du.x * dv.y - du.y * dv.x
            guard abs(determinant) > 1e-9 else { continue }
            let inverse = (x: dv.y / determinant, y: -du.y / determinant,
                           x2: -dv.x / determinant, y2: du.x / determinant)
            let corners = [a, b, c, (b.0 + c.0 - a.0, b.1 + c.1 - a.1)]
            let minX = max(0, Int(corners.map(\.0).min()!.rounded(.down)))
            let maxX = min(canvas.width - 1, Int(corners.map(\.0).max()!.rounded(.up)))
            let minY = max(0, Int(corners.map(\.1).min()!.rounded(.down)))
            let maxY = min(canvas.height - 1, Int(corners.map(\.1).max()!.rounded(.up)))
            guard minX <= maxX, minY <= maxY else { continue }
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) + 0.5 - a.0, dy = Double(y) + 0.5 - a.1
                    let u = inverse.x * dx + inverse.y * dy
                    let v = inverse.x2 * dx + inverse.y2 * dy
                    guard u >= 0, u <= 1, v >= 0, v <= 1 else { continue }
                    let coverage = mask.coverage(u: u, v: v)
                    guard coverage > 0 else { continue }
                    canvas.blend(x: x, y: y, colour: colour, mode: mode, coverage: coverage)
                }
            }
        }
    }

    /// The DX barcode's bars, in the edge printing's coordinates.
    private func drawEdgeBars<Code: CanvasCode>(
        _ canvas: inout Canvas<Code>, bars: [FilmEdgePrinting.Bar], colour: Colour, mode: Blend,
        place: (Double, Double) -> (Double, Double)
    ) {
        for bar in bars {
            let corners = [place(bar.xMM, bar.yMM + bar.heightMM),
                           place(bar.xMM + bar.widthMM, bar.yMM + bar.heightMM),
                           place(bar.xMM + bar.widthMM, bar.yMM),
                           place(bar.xMM, bar.yMM)]
            canvas.fill(polygon: corners, colour: colour, mode: mode)
        }
    }

    // MARK: The material's holes

    private func drawPerforations<Code: CanvasCode>(
        _ canvas: inout Canvas<Code>, geometry g: FilmBorderGeometry,
        material: PrintFramePlacement.Size, placement: PrintFramePlacement, colour: Colour
    ) {
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
                canvas.fill(polygon: points, colour: colour, mode: .normal)
                centre += g.pitchMM
            }
        }
    }

    private func drawNotches<Code: CanvasCode>(
        _ canvas: inout Canvas<Code>, size: PrintFramePlacement.Size, code: SheetFilmNotchCode,
        placement: PrintFramePlacement, colour: Colour
    ) {
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
            }, colour: colour, mode: .normal)
        }
    }

    // MARK: The material's surface

    /// The clear rebate of the negative, exposed through a carrier filed wider than its aperture.
    /// Hand filing leaves a slightly uneven outer edge; the inner edge is the camera gate and
    /// stays straight, because the photograph is laid over it afterwards.
    private func drawCarrierRebate<Code: CanvasCode>(
        _ canvas: inout Canvas<Code>, photo: (x: Double, y: Double, width: Double, height: Double),
        width: Double, colour: Colour, place: (Double, Double) -> (Double, Double)
    ) {
        let outer = (x: photo.x - width, y: photo.y - width,
                     width: photo.width + 2 * width, height: photo.height + 2 * width)
        let corners = [(outer.x, outer.y), (outer.x + outer.width, outer.y),
                       (outer.x + outer.width, outer.y + outer.height),
                       (outer.x, outer.y + outer.height)]
        let normals = [(0.0, -1.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0)]
        let step = 0.5
        var path: [(Double, Double)] = []
        for side in 0..<4 {
            let from = corners[side], to = corners[(side + 1) % 4]
            let length = ((to.0 - from.0) * (to.0 - from.0) + (to.1 - from.1) * (to.1 - from.1))
                .squareRoot()
            let count = max(2, Int((length / step).rounded(.up)))
            for i in 0...count {
                let t = Double(i) / Double(count)
                let point = (x: from.0 + (to.0 - from.0) * t, y: from.1 + (to.1 - from.1) * t)
                // Displacement is normal to the side, in millimetres, bounded to a quarter of the
                // rebate so the line never closes over the photograph.
                let along = Float(length * t)
                let wobble = Filing.noise(along * 0.35, Float(side) * 7.3, seed: 409)
                    + 0.4 * Filing.noise(along * 1.6, Float(side) * 3.1, seed: 613)
                let amount = min(max(Double(wobble) * 0.22, -width * 0.25), width * 0.25)
                let normal = normals[side]
                path.append((x: point.x + normal.0 * amount, y: point.y + normal.1 * amount))
            }
        }
        canvas.fill(polygon: path.map { place($0.0, $0.1) }, colour: colour, mode: .normal)
    }

    /// Fine resin-coated stipple, never cotton fibres or deckled paper: the Mac's restrained
    /// procedural approximation, over the same 0.17 mm lattice and drawn from the same sequence,
    /// so the pattern is the same one wherever the frame is made.
    private func drawLustre<Code: CanvasCode>(
        _ canvas: inout Canvas<Code>, size: PrintFramePlacement.Size, scale: Double,
        excluding photo: (x: Double, y: Double, width: Double, height: Double)
    ) {
        // Below six pixels a millimetre the 0.065 mm dot is under a pixel: the lattice would
        // alias into noise instead of reading as tooth, so a preview leaves the paper smooth.
        guard scale >= 6 else { return }
        var random = MaterialRandom()
        let pitch = 0.17
        let dot = 0.065
        let colour = Colour(red: 0.12, green: 0.12, blue: 0.12)
        var y = 0.0
        while y < size.height {
            var x = 0.0
            while x < size.width {
                let px = x + Double(random.next()) * pitch
                let py = y + Double(random.next()) * pitch
                let inside = px >= photo.x && px <= photo.x + photo.width
                    && py >= photo.y && py <= photo.y + photo.height
                if !inside {
                    canvas.fill(ellipse: (px, py, dot, dot), scale: scale,
                                colour: colour, mode: .normal, alpha: 0.035)
                }
                x += pitch
            }
            y += pitch
        }
    }
}

/// Smooth value noise in about -1...1 for the filed carrier's hand-worked edge, bit for bit the
/// Mac renderer's filingNoise.
enum Filing {
    static func noise(_ x: Float, _ y: Float, seed: UInt32) -> Float {
        let ix = Int32(x.rounded(.down)), iy = Int32(y.rounded(.down))
        let fx = x - Float(ix), fy = y - Float(iy)
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        func sample(_ a: Int32, _ b: Int32) -> Float {
            var n = UInt32(bitPattern: a) &* 374_761_393
                &+ UInt32(bitPattern: b) &* 668_265_263 &+ seed &* 1_013_904_223
            n = (n ^ (n >> 13)) &* 1_274_126_177
            n ^= n >> 16
            return Float(n & 0xFFFF) / 32767.5 - 1
        }
        let a = sample(ix, iy), b = sample(ix &+ 1, iy)
        let c = sample(ix, iy &+ 1), d = sample(ix &+ 1, iy &+ 1)
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    }
}

/// The Mac renderer's MaterialRandom: a 64-bit linear congruential sequence with a fixed seed.
private struct MaterialRandom {
    var state: UInt64 = 0x5052_494E_5453_4854
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 40) / Double(1 << 24)
    }
}

/// The edge printer's lettering: the system's vector type rasterized once per mark.
///
/// The Mac asks CoreText for the glyph outlines and stretches their bounding box to the mark's
/// millimetre box. Windows has no CoreText, so the same box is filled by rasterizing the text at a
/// large size and stretching that mask: the ink still defines the corners, and the mark's box
/// still decides where it lands. System type approximates the edge printer; no manufacturer font
/// or scanned asset is shipped.
enum Lettering {
    struct Mask {
        let coverage: [UInt8]
        let width: Int
        let height: Int

        /// The mask's coverage at a point of its own unit square.
        func coverage(u: Double, v: Double) -> Double {
            let x = u * Double(width) - 0.5, y = v * Double(height) - 0.5
            let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
            let fx = x - Double(x0), fy = y - Double(y0)
            func sample(_ px: Int, _ py: Int) -> Double {
                guard px >= 0, py >= 0, px < width, py < height else { return 0 }
                return Double(coverage[py * width + px]) / 255
            }
            let a = sample(x0, y0), b = sample(x0 + 1, y0)
            let c = sample(x0, y0 + 1), d = sample(x0 + 1, y0 + 1)
            return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
        }
    }

    /// The text's ink, cropped to its own bounding box.
    static func mask(_ text: String, em: Int32 = 256) -> Mask? {
        let wide = Array(text.utf16)
        let count = Int32(wide.count)
        guard count > 0, let dc = CreateCompatibleDC(nil) else { return nil }
        defer { DeleteDC(dc) }
        let padding: Int32 = 48
        // The face: Arial is Windows' Helvetica; the Mac draws the same marks in Helvetica.
        let font = "Arial".withCString(encodedAs: UTF16.self) { name in
            CreateFontW(-em, 0, 0, 0, 400 /* FW_NORMAL */, 0, 0, 0,
                        1 /* DEFAULT_CHARSET */, 4 /* OUT_TT_PRECIS */, 0 /* CLIP_DEFAULT_PRECIS */,
                        4 /* ANTIALIASED_QUALITY */, 0 /* DEFAULT_PITCH|FF_DONTCARE */, name)
        }
        guard let font else { return nil }
        defer { DeleteObject(font) }
        _ = SelectObject(dc, font)
        var extent = SIZE()
        let measured = wide.withUnsafeBufferPointer { buffer -> Bool in
            GetTextExtentPoint32W(dc, buffer.baseAddress, count, &extent)
        }
        guard measured else { return nil }
        let width = Int(extent.cx) + Int(padding) * 2
        let height = Int(em) * 2
        guard width > 0, height > 0 else { return nil }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(width)
        info.bmiHeader.biHeight = LONG(-height)  // top-down
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(0)  // BI_RGB
        var bits: UnsafeMutableRawPointer?
        guard let bitmap = CreateDIBSection(dc, &info, UINT(0), &bits, nil, 0), let bits else {
            return nil
        }
        defer { DeleteObject(bitmap) }
        _ = SelectObject(dc, bitmap)
        _ = memset(bits, 0xFF, width * height * 4)
        _ = SetBkMode(dc, 1 /* TRANSPARENT */)
        _ = SetTextColor(dc, 0)
        _ = wide.withUnsafeBufferPointer { buffer in
            TextOutW(dc, padding, padding, buffer.baseAddress, count)
        }

        // The ink's own bounds: CoreText's path bounds are the same box.
        let bytes = bits.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 2] < 250 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let inkWidth = maxX - minX + 1, inkHeight = maxY - minY + 1
        var coverage = [UInt8](repeating: 0, count: inkWidth * inkHeight)
        for y in 0..<inkHeight {
            for x in 0..<inkWidth {
                coverage[y * inkWidth + x] = 255 - bytes[((y + minY) * width + x + minX) * 4 + 2]
            }
        }
        return Mask(coverage: coverage, width: inkWidth, height: inkHeight)
    }
}

/// A rounded rectangle traced as a polygon, for the slide mount's die-cut aperture.
enum RoundedRect {
    static func points(_ rect: (x: Double, y: Double, width: Double, height: Double),
                       radius: Double, in place: (Double, Double) -> (Double, Double))
        -> [(Double, Double)] {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let centres = [(rect.x + r, rect.y + r, Double.pi, Double.pi * 1.5),
                       (rect.x + rect.width - r, rect.y + r, Double.pi * 1.5, Double.pi * 2),
                       (rect.x + rect.width - r, rect.y + rect.height - r, 0, Double.pi * 0.5),
                       (rect.x + r, rect.y + rect.height - r, Double.pi * 0.5, Double.pi)]
        var points: [(Double, Double)] = []
        for (cx, cy, from, to) in centres {
            let steps = max(2, Int((abs(to - from) * r / 0.05).rounded(.up)))
            for step in 0...steps {
                let angle = from + (to - from) * Double(step) / Double(steps)
                points.append(place(cx + cos(angle) * r, cy + sin(angle) * r))
            }
        }
        return points
    }
}

/// An encoded Display P3 sample: 8 bits for a dithered export, 16 for the deep one.
protocol CanvasCode {
    init(code: Double)
    var code: Double { get }
    var level: Int { get }
    static var levels: Int { get }
}

extension UInt8: CanvasCode {
    init(code: Double) { self = UInt8((Swift.min(1, Swift.max(0, code)) * 255).rounded()) }
    var code: Double { Double(self) / 255 }
    var level: Int { Int(self) }
    static var levels: Int { 256 }
}

extension UInt16: CanvasCode {
    init(code: Double) { self = UInt16((Swift.min(1, Swift.max(0, code)) * 65535).rounded()) }
    var code: Double { Double(self) / 65535 }
    var level: Int { Int(self) }
    static var levels: Int { 65536 }
}

/// An encoded Display P3 colour, each channel 0 to 1.
typealias Colour = (red: Double, green: Double, blue: Double)

/// How a mark meets what is under it, in the delivery's encoding as Core Graphics blends.
enum Blend {
    case normal, multiply, screen, lighten, darken
}

/// A canvas of encoded Display P3 samples, anti-aliased by four samples a pixel, drawn into the
/// material's own millimetres by the caller.
struct Canvas<Code: CanvasCode> {
    var pixels: [Code]
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [Code](repeating: Code(code: 1), count: width * height * 4)
    }

    /// The photograph's own corner pixel, which is the paper the emulsion border prints on.
    static func corner(_ source: [Code], width: Int) -> Colour? {
        guard width > 0, source.count >= 4 else { return nil }
        return (red: source[0].code, green: source[1].code, blue: source[2].code)
    }

    mutating func fill(rect: (x: Int, y: Int, width: Int, height: Int), colour: Colour,
                       mode: Blend) {
        let x0 = max(0, rect.x), y0 = max(0, rect.y)
        let x1 = min(width, rect.x + rect.width), y1 = min(height, rect.y + rect.height)
        guard x0 < x1, y0 < y1 else { return }
        if mode == .normal {
            let red = Code(code: colour.red), green = Code(code: colour.green)
            let blue = Code(code: colour.blue)
            for y in y0..<y1 {
                var index = (y * width + x0) * 4
                for _ in x0..<x1 {
                    pixels[index] = red
                    pixels[index + 1] = green
                    pixels[index + 2] = blue
                    index += 4
                }
            }
            return
        }
        for y in y0..<y1 {
            for x in x0..<x1 {
                blend(x: x, y: y, colour: colour, mode: mode, coverage: 1)
            }
        }
    }

    /// The photograph's own pixels, clipped to the canvas.
    mutating func paste(_ source: [Code], width sourceWidth: Int, height sourceHeight: Int,
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

    /// Fills a closed polygon by scanline: four sub-scanlines a row, each span's ends resolved
    /// to the pixel, so a punched hole's edge is smooth and a thousand-vertex filed edge costs
    /// its rows and edges rather than its rows and edges and pixels.
    mutating func fill(polygon: [(Double, Double)], colour: Colour, mode: Blend) {
        guard polygon.count >= 3 else { return }
        let xs = polygon.map(\.0), ys = polygon.map(\.1)
        let minX = max(0, Int(xs.min()!.rounded(.down)))
        let maxX = min(width - 1, Int(xs.max()!.rounded(.up)))
        let minY = max(0, Int(ys.min()!.rounded(.down)))
        let maxY = min(height - 1, Int(ys.max()!.rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        let span = maxX - minX + 1
        var coverage = [Double](repeating: 0, count: span)
        var crossings: [Double] = []
        crossings.reserveCapacity(64)
        for y in minY...maxY {
            for i in 0..<span { coverage[i] = 0 }
            for sub in 0..<4 {
                let scan = Double(y) + (Double(sub) + 0.5) / 4
                crossings.removeAll(keepingCapacity: true)
                var previous = polygon.count - 1
                for index in 0..<polygon.count {
                    let a = polygon[index], b = polygon[previous]
                    if (a.1 > scan) != (b.1 > scan) {
                        crossings.append((b.0 - a.0) * (scan - a.1) / (b.1 - a.1) + a.0)
                    }
                    previous = index
                }
                guard crossings.count >= 2 else { continue }
                crossings.sort()
                var pair = 0
                while pair + 1 < crossings.count {
                    add(crossings[pair], crossings[pair + 1], weight: 0.25,
                        into: &coverage, from: minX, last: maxX)
                    pair += 2
                }
            }
            for i in 0..<span where coverage[i] > 0 {
                blend(x: minX + i, y: y, colour: colour, mode: mode,
                      coverage: Swift.min(1, coverage[i]))
            }
        }
    }

    /// One scanline span's x coverage, each pixel getting the share of it that it holds.
    private func add(_ from: Double, _ to: Double, weight: Double, into coverage: inout [Double],
                     from minX: Int, last maxX: Int) {
        guard to > from else { return }
        let start = Swift.max(Double(minX), from), end = Swift.min(Double(maxX + 1), to)
        guard end > start else { return }
        var pixel = Int(start.rounded(.down))
        while Double(pixel) < end {
            let left = Swift.max(start, Double(pixel))
            let right = Swift.min(end, Double(pixel + 1))
            if right > left { coverage[pixel - minX] += (right - left) * weight }
            pixel += 1
        }
    }

    /// Fills an ellipse given in the material's millimetres, four samples a pixel.
    mutating func fill(ellipse: (x: Double, y: Double, width: Double, height: Double),
                       scale: Double, colour: Colour, mode: Blend, alpha: Double) {
        let cx = ellipse.x + ellipse.width / 2, cy = ellipse.y + ellipse.height / 2
        let rx = max(0.01, ellipse.width / 2 * scale), ry = max(0.01, ellipse.height / 2 * scale)
        let px = cx * scale, py = Double(height) - cy * scale
        let minX = max(0, Int((px - rx).rounded(.down)))
        let maxX = min(width - 1, Int((px + rx).rounded(.up)))
        let minY = max(0, Int((py - ry).rounded(.down)))
        let maxY = min(height - 1, Int((py + ry).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        let samples = [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
        for y in minY...maxY {
            for x in minX...maxX {
                var covered = 0
                for sample in samples {
                    let dx = (Double(x) + sample.0 - px) / rx
                    let dy = (Double(y) + sample.1 - py) / ry
                    if dx * dx + dy * dy <= 1 { covered += 1 }
                }
                guard covered > 0 else { continue }
                blend(x: x, y: y, colour: colour, mode: mode,
                      coverage: Double(covered) / 4 * alpha)
            }
        }
    }

    mutating func blend(x: Int, y: Int, colour: Colour, mode: Blend, coverage: Double) {
        guard coverage > 0, x >= 0, y >= 0, x < width, y < height else { return }
        let alpha = min(1, coverage)
        let index = (y * width + x) * 4
        let red = pixels[index].code, green = pixels[index + 1].code, blue = pixels[index + 2].code
        func mix(_ under: Double, _ over: Double) -> Double {
            switch mode {
            case .normal: return under * (1 - alpha) + over * alpha
            case .multiply: return under * ((1 - alpha) + alpha * over)
            case .screen: return under + alpha * over * (1 - under)
            case .lighten: return under * (1 - alpha) + max(under, over) * alpha
            case .darken: return under * (1 - alpha) + min(under, over) * alpha
            }
        }
        pixels[index] = Code(code: mix(red, colour.red))
        pixels[index + 1] = Code(code: mix(green, colour.green))
        pixels[index + 2] = Code(code: mix(blue, colour.blue))
    }

    /// Raises every sample by the lift in linear light, screened so white stays white: the black
    /// point of an inverted scan, set a little below its film.
    mutating func liftBlackPoint(by lift: SIMD3<Float>) {
        var tables = [[Code]](repeating: [], count: 3)
        for channel in 0..<3 {
            var table = [Code](repeating: Code(code: 0), count: Code.levels)
            for level in 0..<Code.levels {
                let value = Double(level) / Double(Code.levels - 1)
                let light = Double(ColorScience.srgbToLinear(Float(value)))
                let lifted = light + Double(lift[channel]) * max(0, 1 - light)
                table[level] = Code(code: Double(ColorScience.linearToSrgb(Float(lifted))))
            }
            tables[channel] = table
        }
        var index = 0
        while index + 3 < pixels.count {
            for channel in 0..<3 {
                pixels[index + channel] = tables[channel][pixels[index + channel].level]
            }
            index += 4
        }
    }

}

/// The material's millimetre into the canvas's pixels, the origin at the top left.
enum CanvasPoint {
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

/// The perforation die's outline in millimetres across and along the film, traced every 0.04 mm:
/// a rounded KS rectangle, or BH's circle clipped by two flats. PrintFrameRenderer draws the same
/// outline, and web/src/print-frame-renderer.js traces it again for the browser.
enum Die {
    enum Piece {
        case line((Double, Double), (Double, Double))
        case arc((Double, Double), radius: Double, from: Double, to: Double)

        var length: Double {
            switch self {
            case let .line(a, b):
                return ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
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

/// The material's colours, in Display P3 codes as the encoder writes them.
enum Configuration {
    static let card = display(SIMD3(repeating: 0.86))

    /// Display-linear P3 to the encoding the stills carry.
    static func display(_ rgb: SIMD3<Float>) -> Colour {
        func code(_ value: Float) -> Double { Double(ColorScience.linearToSrgb(max(0, value))) }
        return (red: code(rgb.x), green: code(rgb.y), blue: code(rgb.z))
    }
}
#endif