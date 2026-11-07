// MarqueeChartsLottie — a chart and its build as a Lottie animation (Bodymovin JSON), for players that play Lottie
// frame-accurately (ThorVG, lottie-web, rlottie). Every part's marks are shapes in a layer of their own, text included
// as glyph outlines so a player needs no fonts. The build plays as the CoreGraphics renderer draws it: Appear as the
// layer's in point, Fade as its opacity, Wipe as a mask, and Grow as each mark's own motion (bars and areas by path
// keyframes, slices sampled frame by frame, lines by trim paths, labels and markers by opacity).
//
// What Lottie can't carry: pattern fills are drawn in their two colours' blend (the share of the tile each covers).
import CoreGraphics
import Foundation
import MarqueeCharts
import MarqueeChartsGraphics

public enum ChartLottie {
    public struct Options: Sendable {
        /// Frames per second.
        public var fps: Double
        /// Pixels per point: the animation's size is the chart's times this.
        public var scale: Double
        /// A background colour behind the chart; nil: transparent.
        public var background: ChartColor?
        /// Seconds the finished chart holds after the build.
        public var hold: Double

        public init(fps: Double = 30, scale: Double = 1, background: ChartColor? = nil, hold: Double = 0) {
            self.fps = fps
            self.scale = scale
            self.background = background
            self.hold = hold
        }
    }

    /// The most frames an animation gets (10 minutes at 30 fps).
    public static let maxFrames = 18_000

    /// `drawing` (laid out in `theme`) as Lottie JSON of `frames` frames, each part in the state `states` gives at each
    /// frame (a part it leaves out is drawn whole). Whatever the states do — opacity, an offset, a clip or a wipe,
    /// growing in — the animation draws at every frame what the CoreGraphics renderer draws for the same states.
    public static func animation(_ drawing: ChartDrawing, theme: ChartTheme, frames: Int, options: Options = Options(),
                                 states: (Int) -> [ChartPart: ChartPartState]?) -> Data {
        let n = Swift.min(Swift.max(frames, 1), maxFrames)
        let all = (0 ..< n).map { states($0) ?? [:] }
        var w = Writer(drawing: drawing, theme: theme, frames: n, o: options, states: all)
        let json = w.document()
        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
    }

    /// `drawing` (laid out from `chart` in `theme`) playing `build` (nil: the finished chart, one frame) as Lottie JSON,
    /// the finished chart then held for `options.hold` seconds.
    public static func animation(_ drawing: ChartDrawing, chart: ChartSpec, theme: ChartTheme, build: ChartBuild?, options: Options = Options()) -> Data {
        let fps = options.fps.isFinite ? Swift.min(Swift.max(options.fps, 1), 120) : 30
        var o = options
        o.fps = fps
        let length = (build?.length(chart) ?? 0) + (options.hold.isFinite ? Swift.max(options.hold, 0) : 0)
        let frames = Swift.max(Int((length * fps).rounded(.up)) + 1, 1)
        let parts = drawing.parts
        return animation(drawing, theme: theme, frames: frames, options: o) { f in build?.states(chart, parts: parts, at: Double(f) / fps) }
    }

    /// A chart document laid out and played as Lottie JSON.
    public static func animation(_ doc: ChartDocument, build: ChartBuild?, options: Options = Options()) -> Data {
        animation(doc.drawing(), chart: doc.chart, theme: doc.theme, build: build, options: options)
    }
}

/// The JSON writer.
struct Writer {
    let drawing: ChartDrawing
    let theme: ChartTheme
    let frames: Int
    let o: ChartLottie.Options
    let states: [[ChartPart: ChartPartState]]
    var bounds: [ChartPart: ChartRect] = [:]

    init(drawing: ChartDrawing, theme: ChartTheme, frames: Int, o: ChartLottie.Options, states: [[ChartPart: ChartPartState]]) {
        self.drawing = drawing
        self.theme = theme
        self.frames = frames
        self.o = o
        self.states = states
    }

    var fps: Double { o.fps.isFinite ? Swift.min(Swift.max(o.fps, 1), 120) : 30 }
    var scale: Double { o.scale.isFinite && o.scale > 0 ? o.scale : 1 }

    mutating func document() -> [String: Any] {
        var layers: [[String: Any]] = []
        // Runs of marks of one part, in drawing order (a part's marks can sit between another part's).
        var runs: [(ChartPart, [ChartMark])] = []
        for m in drawing.marks {
            if let last = runs.last, last.0 == m.part { runs[runs.count - 1].1.append(m) } else { runs.append((m.part, [m])) }
        }
        for (k, (part, marks)) in runs.enumerated() {
            if bounds[part] == nil { bounds[part] = drawing.bounds(of: part) }
            layers.append(layer(k + 1, part, marks))
        }
        if let bg = o.background {
            // Under everything: first in drawing order.
            layers.insert(shapeLayer(runs.count + 1, "backdrop", [group([rectShape(ChartRect(0, 0, drawing.width, drawing.height)), fill(bg, 1), transform(still(100))])]), at: 0)
        }
        // Lottie draws its first layer on top.
        layers.reverse()
        return [
            "v": "5.7.0", "fr": fps, "ip": 0, "op": frames, "w": Int((drawing.width * scale).rounded()), "h": Int((drawing.height * scale).rounded()),
            "nm": "chart", "ddd": 0, "assets": [] as [Any], "layers": layers,
        ]
    }

    // MARK: Values over time

    func state(_ part: ChartPart, _ f: Int) -> ChartPartState { states.at(f)?[part] ?? .shown }

    func still(_ v: Any) -> [String: Any] { ["a": 0, "k": v] }

    /// A property's value at every frame, as keyframes: linear between frames, a frame kept only where the value
    /// changes (and the frame before a change), still when it never changes.
    func animated(_ value: (Int) -> Any) -> [String: Any] {
        let values = (0 ..< frames).map(value)
        guard let first = values.first else { return still(0) }
        if values.allSatisfy({ ($0 as AnyObject).isEqual(first) }) { return still(first) }
        var keys: [[String: Any]] = []
        for f in values.indices {
            let changes = f == 0 || !(values[f] as AnyObject).isEqual(values[f - 1])
            let changesNext = f + 1 < values.count && !(values[f] as AnyObject).isEqual(values[f + 1])
            if changes || changesNext {
                keys.append(["t": f, "s": values[f], "o": ["x": [0], "y": [0]], "i": ["x": [1], "y": [1]]])
            }
        }
        return ["a": 1, "k": keys]
    }

    // MARK: Layers

    func shapeLayer(_ index: Int, _ name: String, _ shapes: [[String: Any]], opacity: [String: Any]? = nil, position: [String: Any]? = nil,
                    masks: [[String: Any]]? = nil) -> [String: Any] {
        var l: [String: Any] = [
            "ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1, "ao": 0, "bm": 0, "st": 0, "ip": 0, "op": frames,
            "ks": [
                "o": opacity ?? still(100), "r": still(0), "p": position ?? still([0, 0, 0]), "a": still([0, 0, 0]),
                "s": still([scale * 100, scale * 100, 100]),
            ] as [String: Any],
            "shapes": shapes,
        ]
        if let masks {
            l["hasMask"] = true
            l["masksProperties"] = masks
        }
        return l
    }

    func layer(_ index: Int, _ part: ChartPart, _ marks: [ChartMark]) -> [String: Any] {
        let all = (0 ..< frames).map { state(part, $0) }
        let opacity = all.contains { !$0.visible || $0.opacity < 0.999 }
            ? animated { f in [all[f].visible ? all[f].opacity.clamped(0, 1) * 100 : 0] } : nil
        let position = all.contains { $0.offset != ChartPoint(0, 0) }
            ? animated { f in [all[f].offset.x * scale, all[f].offset.y * scale, 0] } : nil
        var masks: [[String: Any]]?
        if let b = bounds[part], all.contains(where: { $0.visibleBox(b) != nil }) {
            // The whole part, with room for a stroke's ends, when nothing clips it.
            let whole = b.inset(by: -4)
            masks = [[
                "inv": false, "mode": "a", "nm": "clip", "o": still(100), "x": still(0),
                "pt": animated { f in [bezier(ChartPath.rect(all[f].visibleBox(b) ?? whole)).first ?? [:]] },
            ]]
        }
        let growing = all.contains { $0.grow != nil }
        // Within a layer too, Lottie draws its first shapes on top.
        let shapes = marks.flatMap { groups($0, growing ? all : nil) }.reversed()
        return shapeLayer(index, part.name, Array(shapes), opacity: opacity, position: position, masks: masks)
    }

    // MARK: Marks

    /// How far a part has grown at a state: its grow, or all the way (none, while it isn't shown).
    func grown(_ s: ChartPartState) -> Double { s.grow ?? (s.visible ? 1 : 0) }

    /// A mark as a shape group. `growth`: the part's state at every frame, when it grows in.
    func groups(_ m: ChartMark, _ growth: [ChartPartState]?) -> [[String: Any]] {
        var items: [[String: Any]] = []
        switch m.kind {
        case .fill(let path, let paint, let box):
            items += shapes(path, m, growth)
            items.append(fillItem(paint, box))
        case .stroke(let path, let s):
            if let g = growth, case .segment(let index, let count) = m.role {
                // A line draws on: its segment trimmed.
                items += bezier(path).map { ["ty": "sh", "ks": still($0)] }
                items.append(["ty": "tm", "s": still(0), "o": still(0), "m": 1, "e": animated { f in
                    let p = grown(g[f])
                    let local = g[f].alongSeries && count > 0 ? (p * Double(count) - Double(index)).clamped(0, 1) : p
                    return [(local * 1000).rounded() / 10]
                }])
            } else {
                items += shapes(path, m, growth)
            }
            items.append(strokeItem(s))
        case .text(let t):
            let outlines = ChartRenderer.textOutlines(t, fontFamily: theme.fontFamily)
            items += bezier(outlines).map { ["ty": "sh", "ks": still($0)] }
            items.append(fill(t.color, 1))
        }
        // Opacity: marks that fade in as they grow (labels, markers, and marks without a motion of their own).
        var opacity = still(100)
        if let g = growth {
            switch m.role {
            case .none, .marker, .label:
                opacity = animated { f in [((m.grown(grown(g[f]), alongSeries: g[f].alongSeries)?.opacity ?? 0) * 1000).rounded() / 10] }
            default: break
            }
        }
        items.append(transform(opacity))
        return [group(items)]
    }

    /// A mark's path items: still, or keyframed through its growth (the same points at every frame).
    func shapes(_ still0: ChartPath, _ m: ChartMark, _ growth: [ChartPartState]?) -> [[String: Any]] {
        guard let g = growth else { return bezier(still0).map { ["ty": "sh", "ks": still($0)] } }
        switch m.role {
        case .bar, .area, .slice, .bubble: break
        default: return bezier(still0).map { ["ty": "sh", "ks": still($0)] }
        }
        func pathOf(_ mark: ChartMark?) -> ChartPath {
            switch mark?.kind {
            case .fill(let p, _, _)?, .stroke(let p, _)?: p
            default: ChartPath()
            }
        }
        // The mark at a moment of its growth, built the same way at every moment: from nothing to finished.
        func geometry(_ p: Double) -> ChartPath {
            let q = p.clamped(1e-9, 1 - 1e-12)
            return pathOf(m.grown(q, alongSeries: false)?.mark)
        }
        let n = bezier(geometry(1)).count
        return (0 ..< n).map { i in
            ["ty": "sh", "ks": animated { f in [bezier(geometry(grown(g[f]))).at(i) ?? [:]] }]
        }
    }

    func group(_ items: [[String: Any]]) -> [String: Any] { ["ty": "gr", "nm": "mark", "it": items] }

    func transform(_ opacity: [String: Any]) -> [String: Any] {
        ["ty": "tr", "p": ["a": 0, "k": [0, 0]], "a": ["a": 0, "k": [0, 0]], "s": ["a": 0, "k": [100, 100]], "r": ["a": 0, "k": 0], "o": opacity]
    }

    func rgba(_ c: ChartColor) -> [Double] { [Double(c.r) / 255, Double(c.g) / 255, Double(c.b) / 255, 1] }

    func fill(_ c: ChartColor, _ opacity: Double) -> [String: Any] {
        ["ty": "fl", "c": ["a": 0, "k": rgba(c)], "o": ["a": 0, "k": Double(c.a) / 255 * opacity * 100], "r": 1]
    }

    func fillItem(_ paint: ChartPaint, _ box: ChartRect) -> [String: Any] {
        switch paint {
        case .color(let c, let opacity): return fill(c, opacity)
        case .pattern(let p):
            // Lottie has no patterns: the tile's two colours blended by the share each covers.
            let tile = ChartPatterns.tile(p.preset)
            var fg = 0
            for y in 0 ..< 8 { for x in 0 ..< 8 where ChartPatterns.isForeground(tile, x, y) { fg += 1 } }
            let k = Double(fg) / 64
            func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * k + Double(b) * (1 - k)).rounded()) }
            let (f, b) = (p.foreground, p.background)
            return fill(ChartColor(r: mix(f.r, b.r), g: mix(f.g, b.g), b: mix(f.b, b.b), a: mix(f.a, b.a)), 1)
        case .gradient(let g):
            let stops = g.stops.sorted { $0.position < $1.position }
            var colours: [Double] = []
            var alphas: [Double] = []
            for s in stops {
                colours += [s.position] + rgba(s.color).prefix(3)
                alphas += [s.position, Double(s.color.a) / 255]
            }
            let c = box.center
            var item: [String: Any] = ["ty": "gf", "o": ["a": 0, "k": 100], "r": 1, "g": ["p": stops.count, "k": ["a": 0, "k": colours + alphas]]]
            switch g.shape {
            case .linear(let angle, let scaled):
                var a = angle * Double.pi / 180
                if scaled, box.width > 0, box.height > 0 { a = atan2(sin(a) * box.height, cos(a) * box.width) }
                let (dx, dy) = (cos(a), sin(a))
                let ts = [(box.x0, box.y0), (box.x1, box.y0), (box.x0, box.y1), (box.x1, box.y1)].map { ($0.0 - c.x) * dx + ($0.1 - c.y) * dy }
                let (lo, hi) = (ts.min() ?? 0, ts.max() ?? 0)
                item["t"] = 1
                item["s"] = ["a": 0, "k": [c.x + dx * lo, c.y + dy * lo]]
                item["e"] = ["a": 0, "k": [c.x + dx * hi, c.y + dy * hi]]
            case .path:
                let r = [(box.x0, box.y0), (box.x1, box.y1)].map { hypot($0.0 - c.x, $0.1 - c.y) }.max() ?? 0
                item["t"] = 2
                item["s"] = ["a": 0, "k": [c.x, c.y]]
                item["e"] = ["a": 0, "k": [c.x + r, c.y]]
            }
            return item
        }
    }

    func strokeItem(_ s: ChartStroke) -> [String: Any] {
        var item: [String: Any] = [
            "ty": "st", "c": ["a": 0, "k": rgba(s.color)], "o": ["a": 0, "k": Double(s.color.a) / 255 * 100], "w": ["a": 0, "k": s.width],
            "lc": s.cap == .round ? 2 : 1, "lj": s.join == .round ? 2 : 1, "ml": 4,
        ]
        if !s.dashes.isEmpty {
            item["d"] = s.dashes.enumerated().map { i, v in ["n": i % 2 == 0 ? "d" : "g", "nm": i % 2 == 0 ? "dash" : "gap", "v": ["a": 0, "k": v]] }
                + [["n": "o", "nm": "offset", "v": ["a": 0, "k": 0]]]
        }
        return item
    }

    func rectShape(_ r: ChartRect) -> [String: Any] { ["ty": "sh", "ks": ["a": 0, "k": bezier(ChartPath.rect(r)).first ?? [:]]] }

    // MARK: Paths

    /// A path as Lottie bezier shapes, one per subpath: vertices, with their in and out tangents relative to them.
    func bezier(_ path: ChartPath) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var v: [[Double]] = [], ins: [[Double]] = [], outs: [[Double]] = []
        var closed = false
        func flush() {
            guard !v.isEmpty else { return }
            // A closed subpath ending where it began: the last vertex is the first.
            if closed, v.count > 1, let f = v.first, let l = v.last, Swift.abs(f[0] - l[0]) < 1e-9, Swift.abs(f[1] - l[1]) < 1e-9 {
                ins[0] = ins[ins.count - 1]
                v.removeLast()
                ins.removeLast()
                outs.removeLast()
            }
            out.append(["c": closed, "v": v, "i": ins, "o": outs])
            v = []
            ins = []
            outs = []
            closed = false
        }
        for e in path.elements {
            switch e {
            case .move(let p):
                flush()
                v = [[p.x, p.y]]
                ins = [[0, 0]]
                outs = [[0, 0]]
            case .line(let p):
                if v.isEmpty { v = [[p.x, p.y]]; ins = [[0, 0]]; outs = [[0, 0]]; continue }
                v.append([p.x, p.y])
                ins.append([0, 0])
                outs.append([0, 0])
            case .curve(let c1, let c2, let p):
                guard let last = v.last else { continue }
                outs[outs.count - 1] = [c1.x - last[0], c1.y - last[1]]
                v.append([p.x, p.y])
                ins.append([c2.x - p.x, c2.y - p.y])
                outs.append([0, 0])
            case .close:
                closed = true
                flush()
            }
        }
        flush()
        return out
    }

    /// A CoreGraphics path (glyph outlines) as Lottie bezier shapes.
    func bezier(_ cg: CGPath) -> [[String: Any]] {
        var p = ChartPath()
        var current = ChartPoint(0, 0)
        cg.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                current = ChartPoint(e.points[0].x, e.points[0].y)
                p.move(to: current)
            case .addLineToPoint:
                current = ChartPoint(e.points[0].x, e.points[0].y)
                p.line(to: current)
            case .addQuadCurveToPoint:
                // A quadratic as the cubic it is.
                let q = ChartPoint(e.points[0].x, e.points[0].y), end = ChartPoint(e.points[1].x, e.points[1].y)
                p.curve(ChartPoint(current.x + 2 / 3 * (q.x - current.x), current.y + 2 / 3 * (q.y - current.y)),
                        ChartPoint(end.x + 2 / 3 * (q.x - end.x), end.y + 2 / 3 * (q.y - end.y)), end)
                current = end
            case .addCurveToPoint:
                current = ChartPoint(e.points[2].x, e.points[2].y)
                p.curve(ChartPoint(e.points[0].x, e.points[0].y), ChartPoint(e.points[1].x, e.points[1].y), current)
            case .closeSubpath:
                p.close()
            @unknown default:
                break
            }
        }
        return bezier(p)
    }
}

extension Array {
    fileprivate func at(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Double {
    fileprivate func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
