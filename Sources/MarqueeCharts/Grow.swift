// MarqueeCharts — Grow: a chart part coming in the way its kind of mark moves. A bar rises from its base, a slice sweeps
// round from where it starts, an area rises from its floor, a line draws on (along its series when the whole series
// comes in at once), and markers and data labels fade in as their point finishes. Every renderer draws the same
// geometry: the CoreGraphics renderer at any moment, the Lottie writer as keyframes and trim paths.
import Foundation

/// An easing curve: a CSS cubic Bézier from (0, 0) to (1, 1) through two control points.
public enum ChartEasing: String, Codable, CaseIterable, Sendable {
    case linear, easeIn, easeOut, easeInOut

    public var label: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease In"
        case .easeOut: "Ease Out"
        case .easeInOut: "Ease In and Out"
        }
    }

    /// The control points (x1, y1, x2, y2), as CSS writes them.
    public var controlPoints: (Double, Double, Double, Double) {
        switch self {
        case .linear: (0, 0, 1, 1)
        case .easeIn: (0.42, 0, 1, 1)
        case .easeOut: (0, 0, 0.58, 1)
        case .easeInOut: (0.42, 0, 0.58, 1)
        }
    }

    /// The eased value at `t` (0–1): the curve's y where its x is `t`.
    public func callAsFunction(_ t: Double) -> Double {
        let t = t.isFinite ? t.clamped(0, 1) : 0
        if self == .linear { return t }
        let (x1, y1, x2, y2) = controlPoints
        func bez(_ a: Double, _ b: Double, _ s: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        // Bisection on x: monotone for these control points.
        var lo = 0.0, hi = 1.0
        for _ in 0 ..< 40 {
            let mid = (lo + hi) / 2
            if bez(x1, x2, mid) < t { lo = mid } else { hi = mid }
        }
        return bez(y1, y2, (lo + hi) / 2)
    }
}

extension ChartMark {
    /// The share of its point's growth after which a marker or a data label starts to fade in.
    static let finishShare = 0.7

    /// The mark `progress` (0–1) of the way through growing in: its geometry and the opacity it is drawn with, or nil
    /// while it isn't drawn yet. `alongSeries`: the step brings a whole series in, so its line draws on segment after
    /// segment.
    public func grown(_ progress: Double, alongSeries: Bool) -> (mark: ChartMark, opacity: Double)? {
        let p = progress.isFinite ? progress.clamped(0, 1) : 1
        if p >= 1 { return (self, 1) }
        if p <= 0 { return nil }
        var m = self
        switch role {
        case .none:
            return (self, p)
        case .marker, .label:
            let o = ((p - Self.finishShare) / (1 - Self.finishShare)).clamped(0, 1)
            return o > 0 ? (self, o) : nil
        case .bar(let horizontal, let base):
            let t = ChartTransform(horizontal ? p : 1, 0, 0, horizontal ? 1 : p, horizontal ? base * (1 - p) : 0, horizontal ? 0 : base * (1 - p))
            m.kind = m.kind.mapPath { $0.transformed(t) }
        case .slice(let c, let inner, let outer, let start, let sweep):
            let path = ChartPath.slice(center: c, inner: inner, outer: outer, start: start, sweep: sweep * p, segments: ChartPath.arcSegments(sweep))
            m.kind = m.kind.mapPath { _ in path }
        case .area(let top, let floor):
            guard top.count == floor.count, !top.isEmpty else { return (self, p) }
            let risen = zip(top, floor).map { t, f in ChartPoint(t.x, f.y + (t.y - f.y) * p) }
            var path = ChartPath()
            for (k, q) in risen.enumerated() {
                if k == 0 { path.move(to: q) } else { path.line(to: q) }
            }
            for q in floor.reversed() { path.line(to: q) }
            path.close()
            m.kind = m.kind.mapPath { _ in path }
        case .bubble(let c, _), .radial(let c):
            // From its centre: its radius grows with the step, so its area comes in as the square.
            let t = ChartTransform(p, 0, 0, p, c.x * (1 - p), c.y * (1 - p))
            m.kind = m.kind.mapPath { $0.transformed(t) }
        case .segment(let index, let count):
            let local = alongSeries && count > 0 ? (p * Double(count) - Double(index)).clamped(0, 1) : p
            if local <= 0 { return nil }
            if local >= 1 { return (self, 1) }
            m.kind = m.kind.mapPath { $0.trimmed(to: local) }
        }
        return (m, 1)
    }
}

extension ChartMark.Kind {
    /// The same mark with its path replaced (text has none).
    func mapPath(_ f: (ChartPath) -> ChartPath) -> ChartMark.Kind {
        switch self {
        case .fill(let p, let paint, let box): .fill(f(p), paint, box: box)
        case .stroke(let p, let s): .stroke(f(p), s)
        case .text: self
        }
    }
}

extension ChartPath {
    /// Quarter-turn arcs needed for a sweep of `sweep` radians (at least one): the count a slice keeps while it grows,
    /// so its outline has the same points at every moment (an animation can interpolate them).
    public static func arcSegments(_ sweep: Double) -> Int {
        guard sweep.isFinite else { return 1 }
        return Swift.max(Int((Swift.abs(sweep) / (Double.pi / 2) - 1e-9).rounded(.up)), 1)
    }

    /// A pie slice (a ring sector when `inner` > 0) from angle `start` by `sweep`, its arcs in `segments` equal pieces.
    public static func slice(center c: ChartPoint, inner: Double, outer: Double, start: Double, sweep: Double, segments: Int) -> ChartPath {
        var p = ChartPath()
        let n = Swift.max(segments, 1)
        func arc(_ r: Double, _ a0: Double, _ sw: Double) {
            let step = sw / Double(n)
            let k = 4.0 / 3.0 * tan(step / 4)
            var a = a0
            for _ in 0 ..< n {
                let b = a + step
                let (ca, sa, cb, sb) = (cos(a), sin(a), cos(b), sin(b))
                p.curve(ChartPoint(c.x + r * (ca - k * sa), c.y + r * (sa + k * ca)), ChartPoint(c.x + r * (cb + k * sb), c.y + r * (sb - k * cb)),
                        ChartPoint(c.x + r * cb, c.y + r * sb))
                a = b
            }
        }
        if inner > 0 {
            p.move(to: ChartPoint(c.x + outer * cos(start), c.y + outer * sin(start)))
            arc(outer, start, sweep)
            p.line(to: ChartPoint(c.x + inner * cos(start + sweep), c.y + inner * sin(start + sweep)))
            arc(inner, start + sweep, -sweep)
        } else {
            p.move(to: c)
            p.line(to: ChartPoint(c.x + outer * cos(start), c.y + outer * sin(start)))
            arc(outer, start, sweep)
        }
        p.close()
        return p
    }

    /// The path's first piece (a line or a curve from its start) cut at `t` (0–1): a segment drawn on.
    public func trimmed(to t: Double) -> ChartPath {
        guard elements.count >= 2, case .move(let a) = elements[0] else { return self }
        var out = ChartPath()
        out.move(to: a)
        switch elements[1] {
        case .line(let b):
            out.line(to: ChartPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
        case .curve(let c1, let c2, let b):
            // De Casteljau: the curve's first part, up to t.
            func lerp(_ p: ChartPoint, _ q: ChartPoint) -> ChartPoint { ChartPoint(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t) }
            let (p01, p12, p23) = (lerp(a, c1), lerp(c1, c2), lerp(c2, b))
            let (p012, p123) = (lerp(p01, p12), lerp(p12, p23))
            out.curve(p01, p012, lerp(p012, p123))
        default:
            return self
        }
        return out
    }
}
