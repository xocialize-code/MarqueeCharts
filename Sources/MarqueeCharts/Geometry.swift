// MarqueeCharts — the geometry a chart is laid out in: points, boxes, affine transforms and paths, in the chart's own
// space (points, y down, the origin at its top-left corner).
import Foundation

/// A point in the chart's space.
public struct ChartPoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: ChartPoint, b: ChartPoint) -> ChartPoint { ChartPoint(a.x + b.x, a.y + b.y) }
    static func - (a: ChartPoint, b: ChartPoint) -> ChartPoint { ChartPoint(a.x - b.x, a.y - b.y) }
    static func / (a: ChartPoint, k: Double) -> ChartPoint { ChartPoint(a.x / k, a.y / k) }
}

/// A box by its edges: left `x0`, top `y0`, right `x1`, bottom `y1`.
public struct ChartRect: Hashable, Sendable, Codable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }
    public var center: ChartPoint { ChartPoint((x0 + x1) / 2, (y0 + y1) / 2) }

    /// The same box with its edges in order (a positive width and height).
    public var abs: ChartRect { ChartRect(x0.rustMin(x1), y0.rustMin(y1), x0.rustMax(x1), y0.rustMax(y1)) }

    public func contains(_ p: ChartPoint) -> Bool { p.x >= x0 && p.x < x1 && p.y >= y0 && p.y < y1 }

    /// The smallest box holding both.
    public func union(_ o: ChartRect) -> ChartRect {
        ChartRect(Swift.min(x0, o.x0), Swift.min(y0, o.y0), Swift.max(x1, o.x1), Swift.max(y1, o.y1))
    }

    /// Grown by `d` on every side.
    public func inset(by d: Double) -> ChartRect { ChartRect(x0 + d, y0 + d, x1 - d, y1 - d) }

    public var isFinite: Bool { x0.isFinite && y0.isFinite && x1.isFinite && y1.isFinite }
}

/// An affine transform: (x, y) → (a·x + c·y + tx, b·x + d·y + ty).
public struct ChartTransform: Hashable, Sendable, Codable {
    public var a, b, c, d, tx, ty: Double

    public init(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ tx: Double, _ ty: Double) {
        (self.a, self.b, self.c, self.d, self.tx, self.ty) = (a, b, c, d, tx, ty)
    }

    public static let identity = ChartTransform(1, 0, 0, 1, 0, 0)

    public static func translate(_ x: Double, _ y: Double) -> ChartTransform { ChartTransform(1, 0, 0, 1, x, y) }

    /// A turn by `angle` radians (clockwise on screen, the y axis pointing down).
    public static func rotate(_ angle: Double) -> ChartTransform {
        let (s, c) = (sin(angle), cos(angle))
        return ChartTransform(c, s, -s, c, 0, 0)
    }

    /// `self` applied after `o`: (self ∘ o)(p) = self(o(p)).
    public static func * (l: ChartTransform, r: ChartTransform) -> ChartTransform {
        ChartTransform(
            l.a * r.a + l.c * r.b, l.b * r.a + l.d * r.b,
            l.a * r.c + l.c * r.d, l.b * r.c + l.d * r.d,
            l.a * r.tx + l.c * r.ty + l.tx, l.b * r.tx + l.d * r.ty + l.ty
        )
    }

    public func apply(_ p: ChartPoint) -> ChartPoint { ChartPoint(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }

    public var isIdentity: Bool { self == .identity }
}

/// A path: moves, lines, cubic curves and closes.
public struct ChartPath: Hashable, Sendable {
    public enum Element: Hashable, Sendable {
        case move(ChartPoint)
        case line(ChartPoint)
        case curve(ChartPoint, ChartPoint, ChartPoint)
        case close
    }

    public var elements: [Element] = []

    public init() {}

    public mutating func move(to p: ChartPoint) { elements.append(.move(p)) }
    public mutating func line(to p: ChartPoint) { elements.append(.line(p)) }
    public mutating func curve(_ c1: ChartPoint, _ c2: ChartPoint, _ p: ChartPoint) { elements.append(.curve(c1, c2, p)) }
    public mutating func close() { elements.append(.close) }

    public static func rect(_ r: ChartRect) -> ChartPath {
        var p = ChartPath()
        p.move(to: ChartPoint(r.x0, r.y0))
        p.line(to: ChartPoint(r.x1, r.y0))
        p.line(to: ChartPoint(r.x1, r.y1))
        p.line(to: ChartPoint(r.x0, r.y1))
        p.close()
        return p
    }

    /// A circle as four cubic quarters, drawn clockwise from its rightmost point.
    public static func circle(_ c: ChartPoint, _ r: Double) -> ChartPath {
        var p = ChartPath()
        p.move(to: ChartPoint(c.x + r, c.y))
        p.arc(center: c, radius: r, start: 0, sweep: 2 * Double.pi)
        p.close()
        return p
    }

    /// Continue the path along an arc of the circle (`center`, `radius`) from angle `start` by `sweep` radians
    /// (positive clockwise on screen), as cubic curves of at most a quarter turn each. The path must already be
    /// at the arc's start.
    public mutating func arc(center c: ChartPoint, radius r: Double, start: Double, sweep: Double) {
        guard sweep.isFinite, r.isFinite, sweep != 0 else { return }
        let n = Swift.max(Int((Swift.abs(sweep) / (Double.pi / 2)).rounded(.up)), 1)
        let step = sweep / Double(n)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a = start
        for _ in 0 ..< n {
            let b = a + step
            let (ca, sa, cb, sb) = (cos(a), sin(a), cos(b), sin(b))
            curve(
                ChartPoint(c.x + r * (ca - k * sa), c.y + r * (sa + k * ca)),
                ChartPoint(c.x + r * (cb + k * sb), c.y + r * (sb - k * cb)),
                ChartPoint(c.x + r * cb, c.y + r * sb)
            )
            a = b
        }
    }

    /// The box of every point and control point (a curve's box may be smaller).
    public var bounds: ChartRect? {
        var r: ChartRect?
        func add(_ p: ChartPoint) {
            guard p.x.isFinite, p.y.isFinite else { return }
            r = r.map { ChartRect(Swift.min($0.x0, p.x), Swift.min($0.y0, p.y), Swift.max($0.x1, p.x), Swift.max($0.y1, p.y)) }
                ?? ChartRect(p.x, p.y, p.x, p.y)
        }
        for e in elements {
            switch e {
            case .move(let p), .line(let p): add(p)
            case .curve(let a, let b, let p):
                add(a)
                add(b)
                add(p)
            case .close: break
            }
        }
        return r
    }

    /// The path with every point mapped by `t`.
    public func transformed(_ t: ChartTransform) -> ChartPath {
        if t.isIdentity { return self }
        var p = ChartPath()
        p.elements = elements.map { e in
            switch e {
            case .move(let q): .move(t.apply(q))
            case .line(let q): .line(t.apply(q))
            case .curve(let a, let b, let q): .curve(t.apply(a), t.apply(b), t.apply(q))
            case .close: .close
            }
        }
        return p
    }
}
