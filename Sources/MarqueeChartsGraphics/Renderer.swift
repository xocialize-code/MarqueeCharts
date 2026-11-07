// MarqueeChartsGraphics — drawing a laid-out chart with CoreGraphics and CoreText: into any CGContext whose user space
// is the chart's (points, y down), or into an image. A build's part states (shown, faded, wiped) apply per part.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import MarqueeCharts
import UniformTypeIdentifiers

public enum ChartRenderer {
    /// Draw `drawing` into `ctx`, whose user space must be the chart's (points, y down). `states` gives parts their
    /// state in a build; a part it leaves out is drawn whole.
    /// `outlines`: text drawn as filled glyph outlines (as a Lottie or an SVG render carries it) instead of with CoreText.
    public static func draw(_ drawing: ChartDrawing, in ctx: CGContext, theme: ChartTheme, states: [ChartPart: ChartPartState]? = nil, outlines: Bool = false) {
        var bounds: [ChartPart: ChartRect] = [:]
        func boundsOf(_ p: ChartPart) -> ChartRect? {
            if let b = bounds[p] { return b }
            let b = drawing.bounds(of: p)
            bounds[p] = b
            return b
        }
        let fonts = FontCache(family: theme.fontFamily, outlines: outlines)
        var i = 0
        let marks = drawing.marks
        while i < marks.count {
            let part = marks[i].part
            var j = i
            while j < marks.count && marks[j].part == part { j += 1 }
            let state = states?[part] ?? .shown
            defer { i = j }
            if !state.visible || state.opacity <= 0.001 || state.reveal <= 0.0001 || (state.grow ?? 1) <= 0 { continue }
            ctx.saveGState()
            if state.offset != ChartPoint(0, 0) { ctx.translateBy(x: state.offset.x, y: state.offset.y) }
            if let b = boundsOf(part), let r = state.visibleBox(b) {
                ctx.clip(to: CGRect(x: r.x0, y: r.y0, width: Swift.max(r.width, 0), height: Swift.max(r.height, 0)))
            }
            let layered = state.opacity < 0.999
            if layered {
                ctx.setAlpha(state.opacity.clamped(0, 1))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            for m in marks[i ..< j] {
                guard let g = state.grow else {
                    draw(m, in: ctx, fonts: fonts)
                    continue
                }
                // Growing in: each mark as far as it has grown, faded where it fades in.
                guard let (gm, o) = m.grown(g, alongSeries: state.alongSeries) else { continue }
                if o < 0.999 {
                    ctx.saveGState()
                    ctx.setAlpha(o)
                    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                    draw(gm, in: ctx, fonts: fonts)
                    ctx.endTransparencyLayer()
                    ctx.restoreGState()
                } else {
                    draw(gm, in: ctx, fonts: fonts)
                }
            }
            if layered { ctx.endTransparencyLayer() }
            ctx.restoreGState()
        }
    }

    /// `drawing` as an image at `scale` pixels per point, over `background` (nil: transparent).
    public static func image(
        _ drawing: ChartDrawing, theme: ChartTheme, scale: Double = 2, background: ChartColor? = .white, states: [ChartPart: ChartPartState]? = nil,
        outlines: Bool = false
    ) -> CGImage? {
        let scale = scale.isFinite ? scale.clamped(0.05, 16) : 1
        let w = Int((drawing.width * scale).rounded(.up))
        let h = Int((drawing.height * scale).rounded(.up))
        guard w > 0, h > 0, w <= 16384, h <= 16384, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let bg = background {
            ctx.setFillColor(cg(bg))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(drawing, in: ctx, theme: theme, states: states, outlines: outlines)
        return ctx.makeImage()
    }

    /// `image` as PNG data.
    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: Marks

    static func cg(_ c: ChartColor, _ opacity: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255 * opacity.clamped(0, 1))
    }

    static func cgPath(_ p: ChartPath) -> CGPath {
        let out = CGMutablePath()
        var open = false
        for e in p.elements {
            switch e {
            case .move(let q):
                out.move(to: CGPoint(x: q.x, y: q.y))
                open = true
            case .line(let q):
                if open { out.addLine(to: CGPoint(x: q.x, y: q.y)) } else { out.move(to: CGPoint(x: q.x, y: q.y)) }
                open = true
            case .curve(let a, let b, let q):
                if !open { out.move(to: CGPoint(x: a.x, y: a.y)) }
                out.addCurve(to: CGPoint(x: q.x, y: q.y), control1: CGPoint(x: a.x, y: a.y), control2: CGPoint(x: b.x, y: b.y))
                open = true
            case .close:
                if open { out.closeSubpath() }
            }
        }
        return out
    }

    static func draw(_ m: ChartMark, in ctx: CGContext, fonts: FontCache) {
        switch m.kind {
        case .fill(let p, let paint, let box): fill(cgPath(p), paint, box, ctx)
        case .stroke(let p, let s):
            ctx.saveGState()
            ctx.addPath(cgPath(p))
            ctx.setStrokeColor(cg(s.color))
            ctx.setLineWidth(s.width)
            ctx.setLineJoin(s.join == .round ? .round : .miter)
            ctx.setLineCap(s.cap == .round ? .round : .butt)
            if !s.dashes.isEmpty { ctx.setLineDash(phase: 0, lengths: s.dashes.map { CGFloat($0) }) }
            ctx.strokePath()
            ctx.restoreGState()
        case .text(let t): text(t, ctx, fonts)
        }
    }

    static func fill(_ path: CGPath, _ paint: ChartPaint, _ box: ChartRect, _ ctx: CGContext) {
        switch paint {
        case .color(let c, let opacity):
            ctx.addPath(path)
            ctx.setFillColor(cg(c, opacity))
            ctx.fillPath()
        case .gradient(let g):
            let stops = g.stops.sorted { $0.position < $1.position }
            guard let first = stops.first, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
            if stops.count == 1 {
                fill(path, .color(first.color), box, ctx)
                return
            }
            guard let grad = CGGradient(colorsSpace: space, colors: stops.map { cg($0.color) } as CFArray,
                                        locations: stops.map { CGFloat($0.position.clamped(0, 1)) })
            else { return }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            let c = box.center
            switch g.shape {
            case .linear(let angle, let scaled):
                var a = angle * Double.pi / 180
                // Scaled: the angle follows the box's aspect, as DrawingML's `scaled` lays it out.
                if scaled, box.width > 0, box.height > 0 { a = atan2(sin(a) * box.height, cos(a) * box.width) }
                let d = (cos(a), sin(a))
                let ts = [(box.x0, box.y0), (box.x1, box.y0), (box.x0, box.y1), (box.x1, box.y1)].map { ($0.0 - c.x) * d.0 + ($0.1 - c.y) * d.1 }
                let (lo, hi) = (ts.min() ?? 0, ts.max() ?? 0)
                ctx.drawLinearGradient(grad, start: CGPoint(x: c.x + d.0 * lo, y: c.y + d.1 * lo), end: CGPoint(x: c.x + d.0 * hi, y: c.y + d.1 * hi), options: opts)
            case .path(_, let focus):
                let (l, t, r, b) = (focus.at(0) ?? 0.5, focus.at(1) ?? 0.5, focus.at(2) ?? 0.5, focus.at(3) ?? 0.5)
                let fx = box.x0 + box.width * (l + (1 - l - r) / 2)
                let fy = box.y0 + box.height * (t + (1 - t - b) / 2)
                let radius = [(box.x0, box.y0), (box.x1, box.y0), (box.x0, box.y1), (box.x1, box.y1)].map { hypot($0.0 - fx, $0.1 - fy) }.max() ?? 0
                ctx.drawRadialGradient(grad, startCenter: CGPoint(x: fx, y: fy), startRadius: 0, endCenter: CGPoint(x: fx, y: fy), endRadius: radius, options: opts)
            }
            ctx.restoreGState()
        case .pattern(let p):
            guard let tile = patternTile(p) else { return }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.interpolationQuality = .none
            // One cell is 0.75 pt, as PowerPoint draws its patterns at 96 dpi.
            let side = 8 * ChartPatterns.cell
            ctx.draw(tile, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
            ctx.restoreGState()
        }
    }

    /// The 8 × 8 tile of a pattern, its rows upside down: the chart's space has y pointing down, and CoreGraphics
    /// draws an image's first row at its rectangle's top in a y-up space.
    static func patternTile(_ p: ChartPattern) -> CGImage? {
        let t = ChartPatterns.tile(p.preset)
        var data = [UInt8](repeating: 0, count: 64 * 4)
        func premul(_ c: ChartColor) -> [UInt8] {
            let a = Double(c.a)
            return [c.r, c.g, c.b].map { UInt8((Double($0) * a / 255).rounded()) } + [c.a]
        }
        let (f, b) = (premul(p.foreground), premul(p.background))
        for y in 0 ..< 8 {
            for x in 0 ..< 8 {
                let px = ChartPatterns.isForeground(t, x, 7 - y) ? f : b
                for ch in 0 ..< 4 { data[(y * 8 + x) * 4 + ch] = px[ch] }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: Text

    /// Fonts by size and weight, for one drawing.
    final class FontCache {
        let family: String?
        let outlines: Bool
        var fonts: [String: CTFont] = [:]

        init(family: String?, outlines: Bool = false) {
            self.family = family
            self.outlines = outlines
        }

        func font(_ size: Double, bold: Bool) -> CTFont {
            let key = "\(size)-\(bold)"
            if let f = fonts[key] { return f }
            let base: CTFont = family.map { CTFontCreateWithName($0 as CFString, size, nil) }
                ?? CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let f = bold ? CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base : base
            fonts[key] = f
            return f
        }
    }

    /// A text mark's glyphs as outlines in the chart's space (y down), laid out exactly as `draw` draws them: what a
    /// writer that can't carry fonts (Lottie, SVG) draws instead of the text.
    public static func textOutlines(_ t: ChartText, fontFamily: String?) -> CGPath {
        let out = CGMutablePath()
        guard t.size.isFinite, t.size > 0 else { return out }
        let font = FontCache(family: fontFamily).font(t.size, bold: t.bold)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        let lines = t.string.split(separator: "\n", omittingEmptySubsequences: false).map { s in
            CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, String(s) as CFString, attrs as CFDictionary))
        }
        let (lineHeight, ascent) = lineMetrics(font, t.size)
        let blockH = lineHeight * CGFloat(lines.count)
        let top: CGFloat = switch t.anchor {
        case .top: t.box.y0
        case .middle: t.box.center.y - blockH / 2
        case .bottom: t.box.y1 - blockH
        }
        let m = t.transform
        let place = CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty)
        for (k, line) in lines.enumerated() {
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            let x: CGFloat = switch t.align {
            case .left: t.box.x0
            case .center: t.box.center.x - w / 2
            case .right: t.box.x1 - w
            }
            let baseline = top + lineHeight * CGFloat(k) + ascent
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                let n = CTRunGetGlyphCount(run)
                guard n > 0 else { continue }
                // The run's own font: CoreText substitutes one for characters the chosen font lacks.
                var runFont = font
                if let v = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as CFTypeRef?, CFGetTypeID(v) == CTFontGetTypeID() {
                    runFont = unsafeBitCast(v, to: CTFont.self)
                }
                var glyphs = [CGGlyph](repeating: 0, count: n)
                var positions = [CGPoint](repeating: .zero, count: n)
                CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
                for i in 0 ..< n {
                    // Glyph space is y up: flip it onto the baseline, then place it with the mark's transform.
                    var g = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x + positions[i].x, ty: baseline - positions[i].y).concatenating(place)
                    if let path = CTFontCreatePathForGlyph(runFont, glyphs[i], &g) { out.addPath(path) }
                }
            }
        }
        return out
    }

    /// A line's height and where its baseline sits below its top, as PowerPoint spaces text: single lines 1.2 times the
    /// size apart in every font, split at the baseline in the font's own ascent-to-descent proportion.
    static func lineMetrics(_ font: CTFont, _ size: Double) -> (CGFloat, CGFloat) {
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        let h = CGFloat(size) * 1.2
        return (h, a + d > 0 ? h * a / (a + d) : h * 0.8)
    }

    static func text(_ t: ChartText, _ ctx: CGContext, _ fonts: FontCache) {
        guard t.size.isFinite, t.size > 0 else { return }
        if fonts.outlines {
            ctx.addPath(textOutlines(t, fontFamily: fonts.family))
            ctx.setFillColor(cg(t.color))
            ctx.fillPath()
            return
        }
        let font = fonts.font(t.size, bold: t.bold)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: cg(t.color)]
        let lines = t.string.split(separator: "\n", omittingEmptySubsequences: false).map { s in
            CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, String(s) as CFString, attrs as CFDictionary))
        }
        let (lineHeight, ascent) = lineMetrics(font, t.size)
        let blockH = lineHeight * CGFloat(lines.count)
        let top: CGFloat = switch t.anchor {
        case .top: t.box.y0
        case .middle: t.box.center.y - blockH / 2
        case .bottom: t.box.y1 - blockH
        }
        ctx.saveGState()
        let m = t.transform
        ctx.concatenate(CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty))
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (k, line) in lines.enumerated() {
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            let x: CGFloat = switch t.align {
            case .left: t.box.x0
            case .center: t.box.center.x - w / 2
            case .right: t.box.x1 - w
            }
            ctx.textPosition = CGPoint(x: x, y: top + lineHeight * CGFloat(k) + ascent)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }
}

extension Double {
    fileprivate func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

extension Array {
    fileprivate func at(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
