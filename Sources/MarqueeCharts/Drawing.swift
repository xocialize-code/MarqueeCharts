// MarqueeCharts — a laid-out chart: its marks in drawing order, each tagged with the part of the chart it belongs to.
// Drawing every mark draws the chart; drawing a part's marks draws that part alone, so each part can animate on its
// own (a chart build) and still come out exactly as the whole chart does once every part has played.
import Foundation

/// A part of a chart: the background (title, legend, axes, gridlines and their labels) or one data point (a bar, a
/// slice, a line's segment to the point and its marker, an area from its first point), with its data label.
public enum ChartPart: Hashable, Sendable, Codable, Comparable {
    case background
    case point(series: Int, category: Int)

    /// A name for files and ids: `background`, `point-<series>-<category>`.
    public var name: String {
        switch self {
        case .background: "background"
        case .point(let s, let c): "point-\(s)-\(c)"
        }
    }

    public static func < (a: ChartPart, b: ChartPart) -> Bool {
        switch (a, b) {
        case (.background, .point): true
        case (.point(let s0, let c0), .point(let s1, let c1)): (s0, c0) < (s1, c1)
        default: false
        }
    }
}

/// A fill's paint. A colour's `opacity` multiplies its alpha.
public enum ChartPaint: Hashable, Sendable {
    case color(ChartColor, opacity: Double)
    case gradient(ChartGradient)
    case pattern(ChartPattern)

    public static func color(_ c: ChartColor) -> ChartPaint { .color(c, opacity: 1) }
}

/// A stroke: colour, width, dashes (lengths in points, alternately on and off), the joins' and ends' shapes.
public struct ChartStroke: Hashable, Sendable {
    public enum Join: Hashable, Sendable { case miter, round }
    public enum Cap: Hashable, Sendable { case butt, round }

    public var color: ChartColor
    public var width: Double
    public var dashes: [Double]
    public var join: Join
    public var cap: Cap

    /// Round joins and ends unless asked otherwise, as DeckCraft strokes.
    public init(_ color: ChartColor, width: Double, dashes: [Double] = [], join: Join = .round, cap: Cap = .round) {
        self.color = color
        self.width = width
        self.dashes = dashes
        self.join = join
        self.cap = cap
    }
}

/// Text placed in a box: on one line or several (split at newlines), never wrapped, aligned across the box and
/// anchored to its top, middle or bottom. `transform` maps the box's space into the chart's (a turned axis title).
public struct ChartText: Hashable, Sendable {
    public enum Align: Hashable, Sendable { case left, center, right }
    public enum Anchor: Hashable, Sendable { case top, middle, bottom }

    public var string: String
    public var box: ChartRect
    public var size: Double
    public var bold: Bool
    public var color: ChartColor
    public var align: Align
    public var anchor: Anchor
    public var transform: ChartTransform

    public init(
        _ string: String, box: ChartRect, size: Double, bold: Bool = false, color: ChartColor, align: Align, anchor: Anchor,
        transform: ChartTransform = .identity
    ) {
        self.string = string
        self.box = box
        self.size = size
        self.bold = bold
        self.color = color
        self.align = align
        self.anchor = anchor
        self.transform = transform
    }
}

/// One mark of a chart.
public struct ChartMark: Hashable, Sendable {
    /// What a mark draws, so an effect can move it the way its kind of mark moves: a bar grows from its base, a slice
    /// sweeps round, an area rises from its floor, a line segment draws on, a marker or a label appears.
    public enum Role: Hashable, Sendable {
        case none
        /// A bar (its fill or its outline): it grows from `base`, a position along the value axis (x on a horizontal bar
        /// chart, y otherwise).
        case bar(horizontal: Bool, base: Double)
        /// A pie or doughnut slice (fill or outline): from angle `start` by `sweep` radians, between radius `inner` and
        /// `outer`.
        case slice(center: ChartPoint, inner: Double, outer: Double, start: Double, sweep: Double)
        /// Line segment `index` of `count` in its series (it ends at its point).
        case segment(index: Int, count: Int)
        /// An area: its top edge, left to right, and the floor under each point.
        case area(top: [ChartPoint], floor: [ChartPoint])
        case marker
        case label
    }

    public enum Kind: Hashable, Sendable {
        /// `path` filled with `paint`, laid out over `box` (a gradient's or a pattern's extent).
        case fill(ChartPath, ChartPaint, box: ChartRect)
        case stroke(ChartPath, ChartStroke)
        case text(ChartText)
    }

    public var part: ChartPart
    public var kind: Kind
    public var role: Role

    public init(_ part: ChartPart, _ kind: Kind, role: Role = .none) {
        self.part = part
        self.kind = kind
        self.role = role
    }

    /// The box the mark covers in the chart's space (a text's box as laid out, a stroke grown by half its width).
    public var bounds: ChartRect? {
        switch kind {
        case .fill(let p, _, _): return p.bounds
        case .stroke(let p, let s): return p.bounds?.inset(by: -s.width / 2)
        case .text(let t):
            let corners = [ChartPoint(t.box.x0, t.box.y0), ChartPoint(t.box.x1, t.box.y0), ChartPoint(t.box.x0, t.box.y1), ChartPoint(t.box.x1, t.box.y1)]
                .map(t.transform.apply)
            guard let f = corners.first else { return nil }
            return corners.dropFirst().reduce(ChartRect(f.x, f.y, f.x, f.y)) { $0.union(ChartRect($1.x, $1.y, $1.x, $1.y)) }
        }
    }
}

/// A chart laid out at a size: its marks in drawing order.
public struct ChartDrawing: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public var marks: [ChartMark]

    public init(width: Double, height: Double, marks: [ChartMark] = []) {
        self.width = width
        self.height = height
        self.marks = marks
    }

    /// Every part with a mark, in the order of their first mark.
    public var parts: [ChartPart] {
        var seen = Set<ChartPart>()
        return marks.compactMap { seen.insert($0.part).inserted ? $0.part : nil }
    }

    /// The marks of `parts` alone, in drawing order.
    public func marks(of parts: Set<ChartPart>) -> [ChartMark] { marks.filter { parts.contains($0.part) } }

    /// The box a part's marks cover.
    public func bounds(of part: ChartPart) -> ChartRect? {
        marks.lazy.filter { $0.part == part }.compactMap(\.bounds).reduce(nil) { r, b in r.map { $0.union(b) } ?? b }
    }
}
