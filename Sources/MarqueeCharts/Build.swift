// MarqueeCharts — chart builds: a chart that plays in steps, as PowerPoint's chart animations do (as one object, by
// series, by category, or by element in series or in category, with the background first or not), and the state of
// each part at a moment of the build. The steps follow DeckCraftNative's DCModel/ChartBuild.swift (MIT OR Apache-2.0).
import Foundation

/// How a chart's parts are grouped into steps.
public enum ChartBuildKind: String, Codable, CaseIterable, Sendable {
    case asOneObject, bySeries, byCategory, bySeriesElement, byCategoryElement

    public var label: String {
        switch self {
        case .asOneObject: "As One Object"
        case .bySeries: "By Series"
        case .byCategory: "By Category"
        case .bySeriesElement: "By Element in Series"
        case .byCategoryElement: "By Element in Category"
        }
    }
}

/// How a step comes in.
public enum ChartEffect: String, Codable, CaseIterable, Sendable {
    case appear, fade, wipe
    /// Each mark the way its kind moves: bars rise, slices sweep, areas rise, lines draw on, labels fade in at the end.
    case grow

    public var label: String {
        switch self {
        case .appear: "Appear"
        case .fade: "Fade"
        case .wipe: "Wipe"
        case .grow: "Grow"
        }
    }
}

/// Where a wipe starts.
public enum WipeDirection: String, Codable, CaseIterable, Sendable {
    case fromBottom, fromLeft, fromTop, fromRight

    public var label: String {
        switch self {
        case .fromBottom: "From Bottom"
        case .fromLeft: "From Left"
        case .fromTop: "From Top"
        case .fromRight: "From Right"
        }
    }
}

/// One step of a build: what it brings in.
public enum ChartBuildStep: Hashable, Sendable, Codable {
    case background
    case series(Int)
    case category(Int)
    case point(series: Int, category: Int)
    /// The whole chart at once.
    case all

    /// Does this step bring `part` in?
    public func covers(_ part: ChartPart) -> Bool {
        switch (self, part) {
        case (.all, _): true
        case (.background, .background): true
        case (.series(let s), .point(let ps, _)): s == ps
        case (.category(let c), .point(_, let pc)): c == pc
        case (.point(let s, let c), .point(let ps, let pc)): s == ps && c == pc
        default: false
        }
    }

    public var label: String {
        switch self {
        case .background: "Background"
        case .series(let s): "Series \(s + 1)"
        case .category(let c): "Category \(c + 1)"
        case .point(let s, let c): "Series \(s + 1), point \(c + 1)"
        case .all: "Chart"
        }
    }
}

/// A part's state at a moment: whether it shows, its opacity, and how much of it a wipe has revealed (1: all of it)
/// from which side.
public struct ChartPartState: Hashable, Sendable {
    public var visible: Bool
    public var opacity: Double
    public var reveal: Double
    public var direction: WipeDirection
    /// How far it has grown in (0–1; `ChartMark.grown`), when it comes in by growing.
    public var grow: Double?
    /// It grows in as part of its whole series (a line draws on along it).
    public var alongSeries: Bool
    /// The part drawn only within this box, given as fractions of its own bounds (left, top, right, bottom); nil: whole
    /// (`reveal` still applies).
    public var clip: ChartRect?
    /// Moved by this many points.
    public var offset: ChartPoint

    public init(visible: Bool = true, opacity: Double = 1, reveal: Double = 1, direction: WipeDirection = .fromBottom, grow: Double? = nil,
                alongSeries: Bool = false, clip: ChartRect? = nil, offset: ChartPoint = ChartPoint(0, 0)) {
        self.visible = visible
        self.opacity = opacity
        self.reveal = reveal
        self.direction = direction
        self.grow = grow
        self.alongSeries = alongSeries
        self.clip = clip
        self.offset = offset
    }

    /// The box the part is drawn within, given its bounds: its clip, else what a wipe has revealed; nil: all of it.
    public func visibleBox(_ b: ChartRect) -> ChartRect? {
        if let c = clip {
            return ChartRect(b.x0 + b.width * c.x0, b.y0 + b.height * c.y0, b.x0 + b.width * c.x1, b.y0 + b.height * c.y1)
        }
        guard reveal < 0.9999 else { return nil }
        let f = reveal.clamped(0, 1)
        return switch direction {
        case .fromBottom: ChartRect(b.x0, b.y1 - b.height * f, b.x1, b.y1)
        case .fromTop: ChartRect(b.x0, b.y0, b.x1, b.y0 + b.height * f)
        case .fromLeft: ChartRect(b.x0, b.y0, b.x0 + b.width * f, b.y1)
        case .fromRight: ChartRect(b.x1 - b.width * f, b.y0, b.x1, b.y1)
        }
    }

    public static let shown = ChartPartState()
    public static let hidden = ChartPartState(visible: false, opacity: 0, reveal: 0)

    /// Drawn exactly as the finished chart draws it.
    public var isFinished: Bool {
        visible && opacity >= 0.999 && reveal >= 0.999 && (grow ?? 1) >= 0.999 && clip == nil && offset == ChartPoint(0, 0)
    }
}

/// A chart's build: its steps, how each comes in, and its timing (each step after the one before).
public struct ChartBuild: Hashable, Sendable, Codable {
    public var kind: ChartBuildKind
    public var effect: ChartEffect
    public var direction: WipeDirection
    /// The background (axes, gridlines, legend, titles) is a step of its own, first; otherwise it is there from the start.
    public var animateBackground: Bool
    /// Seconds each step takes.
    public var duration: Double
    /// Seconds between one step's end and the next one's start.
    public var delay: Double
    /// How much of a step the next one overlaps (0–0.9): staggered steps, each starting before the one before ends.
    public var overlap: Double
    public var easing: ChartEasing

    public init(
        kind: ChartBuildKind = .bySeries, effect: ChartEffect = .wipe, direction: WipeDirection = .fromBottom, animateBackground: Bool = true,
        duration: Double = 0.5, delay: Double = 0, overlap: Double = 0, easing: ChartEasing = .linear
    ) {
        self.kind = kind
        self.effect = effect
        self.direction = direction
        self.animateBackground = animateBackground
        self.duration = duration
        self.delay = delay
        self.overlap = overlap
        self.easing = easing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChartBuild()
        self.init(
            kind: try c.decodeIfPresent(ChartBuildKind.self, forKey: .kind) ?? d.kind,
            effect: try c.decodeIfPresent(ChartEffect.self, forKey: .effect) ?? d.effect,
            direction: try c.decodeIfPresent(WipeDirection.self, forKey: .direction) ?? d.direction,
            animateBackground: try c.decodeIfPresent(Bool.self, forKey: .animateBackground) ?? d.animateBackground,
            duration: try c.decodeIfPresent(Double.self, forKey: .duration) ?? d.duration,
            delay: try c.decodeIfPresent(Double.self, forKey: .delay) ?? 0,
            overlap: try c.decodeIfPresent(Double.self, forKey: .overlap) ?? 0,
            easing: try c.decodeIfPresent(ChartEasing.self, forKey: .easing) ?? .linear
        )
    }

    /// The most steps a build plays (more data plays as one object).
    public static let maxSteps = 1_000

    /// The steps this build plays on `chart`, in order: the background unless it is left out, then each series,
    /// category or point (points series by series for a by-element-in-series build, category by category for the
    /// other). As one object when the chart has no data or would need more than `maxSteps`.
    public func steps(_ chart: ChartSpec) -> [ChartBuildStep] {
        let ns = chart.series.count
        let nc = chart.pointCount
        let data: Int
        switch kind {
        case .asOneObject: data = 0
        case .bySeries: data = ns
        case .byCategory: data = nc
        case .bySeriesElement, .byCategoryElement:
            let (p, o) = ns.multipliedReportingOverflow(by: nc)
            data = o ? Int.max : p
        }
        if kind == .asOneObject || ns == 0 || nc == 0 || data >= Self.maxSteps { return [.all] }
        var out: [ChartBuildStep] = animateBackground ? [.background] : []
        out.reserveCapacity(data + 1)
        switch kind {
        case .asOneObject: break
        case .bySeries: out += (0 ..< ns).map { .series($0) }
        case .byCategory: out += (0 ..< nc).map { .category($0) }
        case .bySeriesElement:
            for s in 0 ..< ns { for c in 0 ..< nc { out.append(.point(series: s, category: c)) } }
        case .byCategoryElement:
            for c in 0 ..< nc { for s in 0 ..< ns { out.append(.point(series: s, category: c)) } }
        }
        return out
    }

    var safeDuration: Double { duration.isFinite ? duration.clamped(0, 60) : 0 }
    var safeDelay: Double { delay.isFinite ? delay.clamped(0, 60) : 0 }
    var safeOverlap: Double { overlap.isFinite ? overlap.clamped(0, 0.9) : 0 }
    /// Seconds from one step's start to the next one's.
    var period: Double { safeDuration * (1 - safeOverlap) + safeDelay }

    /// When step `k` starts, in seconds from the build's start.
    public func start(ofStep k: Int) -> Double { Double(k) * period }

    /// The whole build's length in seconds.
    public func length(_ chart: ChartSpec) -> Double {
        let n = steps(chart).count
        return n == 0 ? 0 : start(ofStep: n - 1) + safeDuration
    }

    /// The step playing (or last played) at `time`, if any has started.
    public func step(at time: Double, _ chart: ChartSpec) -> Int? {
        let n = steps(chart).count
        guard n > 0, time >= 0 else { return nil }
        let per = period
        guard per > 0 else { return n - 1 }
        return Swift.min(Int(rustCast: (time / per).rounded(.down)), n - 1)
    }

    /// Every part's state at `time` seconds into the build: a part no step brings in is there from the start.
    public func states(_ chart: ChartSpec, parts: [ChartPart], at time: Double) -> [ChartPart: ChartPartState] {
        let steps = self.steps(chart)
        var out: [ChartPart: ChartPartState] = [:]
        for p in parts {
            guard let k = steps.firstIndex(where: { $0.covers(p) }) else {
                out[p] = .shown
                continue
            }
            let t0 = start(ofStep: k)
            if time < t0 {
                out[p] = .hidden
                continue
            }
            let d = safeDuration
            let f = easing(d > 0 ? ((time - t0) / d).clamped(0, 1) : 1)
            switch effect {
            case .appear: out[p] = .shown
            case .fade: out[p] = ChartPartState(opacity: f)
            case .wipe: out[p] = ChartPartState(reveal: f, direction: direction)
            case .grow:
                let whole: Bool = switch steps[k] { case .series, .all: true; default: false }
                out[p] = ChartPartState(grow: f, alongSeries: whole)
            }
        }
        return out
    }
}
