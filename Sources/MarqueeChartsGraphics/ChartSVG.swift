// MarqueeChartsGraphics — marks as a fill-only SVG document: paths and gradients, nothing else. Strokes are outlined,
// text is drawn as glyph outlines (so a reader needs no fonts), and patterns are drawn in their two colours' blend.
// Path data is absolute `M L Q C Z`. What the Marquee Show format's renders (and many strict SVG readers) take.
import CoreGraphics
import Foundation
import MarqueeCharts

public enum ChartSVG {
    /// `marks` as an SVG document whose view box is `box` (in the chart's space), sized `scale` pixels per point.
    /// `fontFamily`: the typeface the text is outlined in (nil: the system's).
    public static func document(_ marks: [ChartMark], box: ChartRect, scale: Double = 1, fontFamily: String?) -> String {
        var defs: [String] = []
        var body: [String] = []
        for m in marks {
            switch m.kind {
            case .fill(let path, let paint, let pbox):
                let d = pathData(ChartRenderer.cgPath(path))
                if d.isEmpty { continue }
                switch paint {
                case .color(let c, let opacity):
                    body.append(element(d, fill: c, opacity: Double(c.a) / 255 * opacity))
                case .pattern(let p):
                    body.append(element(d, fill: blend(p), opacity: 1))
                case .gradient(let g):
                    let id = "g\(defs.count)"
                    defs.append(gradient(g, pbox, id))
                    body.append("<path d=\"\(d)\" fill=\"url(#\(id))\"/>")
                }
            case .stroke(let path, let s):
                var cg = ChartRenderer.cgPath(path)
                if !s.dashes.isEmpty { cg = cg.copy(dashingWithPhase: 0, lengths: s.dashes.map { CGFloat($0) }) }
                let outline = cg.copy(strokingWithWidth: s.width, lineCap: s.cap == .round ? .round : .butt,
                                      lineJoin: s.join == .round ? .round : .miter, miterLimit: 4)
                let d = pathData(outline)
                if !d.isEmpty { body.append(element(d, fill: s.color, opacity: Double(s.color.a) / 255)) }
            case .text(let t):
                let d = pathData(ChartRenderer.textOutlines(t, fontFamily: fontFamily))
                if !d.isEmpty { body.append(element(d, fill: t.color, opacity: Double(t.color.a) / 255)) }
            }
        }
        let (w, h) = (box.width * scale, box.height * scale)
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(num(w))\" height=\"\(num(h))\" viewBox=\"\(num(box.x0)) \(num(box.y0)) \(num(box.width)) \(num(box.height))\">"
            + (defs.isEmpty ? "" : "<defs>" + defs.joined() + "</defs>") + body.joined() + "</svg>\n"
    }

    /// The box the marks cover (strokes' outlines and text boxes included), or nil when they cover nothing.
    public static func ink(_ marks: [ChartMark]) -> ChartRect? {
        marks.compactMap(\.bounds).reduce(nil) { r, b in r.map { $0.union(b) } ?? b }
    }

    static func element(_ d: String, fill c: ChartColor, opacity: Double) -> String {
        let hex = String(format: "#%02x%02x%02x", c.r, c.g, c.b)
        let o = opacity < 0.999 ? " fill-opacity=\"\(num(Swift.max(opacity, 0)))\"" : ""
        return "<path d=\"\(d)\" fill=\"\(hex)\"\(o)/>"
    }

    static func blend(_ p: ChartPattern) -> ChartColor {
        let tile = ChartPatterns.tile(p.preset)
        var fg = 0
        for y in 0 ..< 8 { for x in 0 ..< 8 where ChartPatterns.isForeground(tile, x, y) { fg += 1 } }
        let k = Double(fg) / 64
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * k + Double(b) * (1 - k)).rounded()) }
        let (f, b) = (p.foreground, p.background)
        return ChartColor(r: mix(f.r, b.r), g: mix(f.g, b.g), b: mix(f.b, b.b), a: mix(f.a, b.a))
    }

    static func gradient(_ g: ChartGradient, _ box: ChartRect, _ id: String) -> String {
        let stops = g.stops.sorted { $0.position < $1.position }.map { s in
            let c = s.color
            let o = c.a < 255 ? " stop-opacity=\"\(num(Double(c.a) / 255))\"" : ""
            return "<stop offset=\"\(num(Swift.min(Swift.max(s.position, 0), 1)))\" stop-color=\"\(String(format: "#%02x%02x%02x", c.r, c.g, c.b))\"\(o)/>"
        }.joined()
        let c = box.center
        switch g.shape {
        case .linear(let angle, let scaled):
            var a = angle * Double.pi / 180
            if scaled, box.width > 0, box.height > 0 { a = atan2(sin(a) * box.height, cos(a) * box.width) }
            let (dx, dy) = (cos(a), sin(a))
            let ts = [(box.x0, box.y0), (box.x1, box.y0), (box.x0, box.y1), (box.x1, box.y1)].map { ($0.0 - c.x) * dx + ($0.1 - c.y) * dy }
            let (lo, hi) = (ts.min() ?? 0, ts.max() ?? 0)
            return "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(num(c.x + dx * lo))\" y1=\"\(num(c.y + dy * lo))\" "
                + "x2=\"\(num(c.x + dx * hi))\" y2=\"\(num(c.y + dy * hi))\">\(stops)</linearGradient>"
        case .path:
            let r = [(box.x0, box.y0), (box.x1, box.y1)].map { hypot($0.0 - c.x, $0.1 - c.y) }.max() ?? 0
            return "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(num(c.x))\" cy=\"\(num(c.y))\" r=\"\(num(r))\">\(stops)</radialGradient>"
        }
    }

    /// A path's data in absolute `M L Q C Z`.
    static func pathData(_ p: CGPath) -> String {
        var d = ""
        p.applyWithBlock { el in
            let e = el.pointee
            let pts = e.points
            switch e.type {
            case .moveToPoint: d += "M\(num(pts[0].x)) \(num(pts[0].y))"
            case .addLineToPoint: d += "L\(num(pts[0].x)) \(num(pts[0].y))"
            case .addQuadCurveToPoint: d += "Q\(num(pts[0].x)) \(num(pts[0].y)) \(num(pts[1].x)) \(num(pts[1].y))"
            case .addCurveToPoint:
                d += "C\(num(pts[0].x)) \(num(pts[0].y)) \(num(pts[1].x)) \(num(pts[1].y)) \(num(pts[2].x)) \(num(pts[2].y))"
            case .closeSubpath: d += "Z"
            @unknown default: break
            }
        }
        return d
    }

    /// A number with at most three decimals, without trailing zeros.
    static func num(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let r = (v * 1000).rounded() / 1000
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.3f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
