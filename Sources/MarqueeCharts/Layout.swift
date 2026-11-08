// MarqueeCharts — laying a chart out: title, legend, axes, gridlines and their labels, then each series' marks, as
// marks tagged by part. From DeckCraftNative's DCRender/Chart.swift, a port of deckcraft crates/render/src/chart.rs
// (MIT OR Apache-2.0, © ArtCraft Team and the DeckCraft contributors), for the first chart types. Sizes are
// measured in points; text widths are estimated from character counts, as DeckCraft does, so a layout needs no fonts.
import Foundation

public enum ChartLayout {
    /// Lay `chart` out at `width` × `height` points in `theme`.
    public static func draw(_ chart: ChartSpec, theme: ChartTheme, width: Double, height: Double) -> ChartDrawing {
        // A histogram is drawn as the column chart of its bins (a Pareto as a combo), a box and whisker chart as a column
        // chart's frame with its boxes in place of the columns.
        var spec = chart
        var boxes: [[BoxStats?]]?
        if spec.kind.isBinned {
            spec = spec.histogramView()
        } else if spec.kind == .boxWhisker {
            let (frame, stats) = spec.boxView()
            spec = frame
            boxes = stats
        }
        var l = Layout(c: spec, theme: theme, w: width.isFinite ? Swift.max(width, 0) : 0, h: height.isFinite ? Swift.max(height, 0) : 0)
        l.boxes = boxes
        l.run()
        return ChartDrawing(width: l.w, height: l.h, marks: l.marks)
    }
}

/// How a bar, or its legend key, is painted.
enum BarPaint: Equatable {
    case color(ChartColor)
    case pattern(ChartPattern)
    /// Only the outline, if any, shows.
    case nothing
    /// Laid out over each bar's own box.
    case gradient(ChartGradient)
    /// A legend key drawn as a short line: its colour and dash pattern.
    case line(ChartColor, [Double])
}

struct Layout {
    let c: ChartSpec
    let theme: ChartTheme
    let w: Double
    let h: Double
    var marks: [ChartMark] = []
    /// The part the next marks belong to, and what they draw.
    var part: ChartPart = .background
    var role: ChartMark.Role = .none
    /// A box and whisker chart's summaries, per series, per group.
    var boxes: [[BoxStats?]]?

    init(c: ChartSpec, theme: ChartTheme, w: Double, h: Double) {
        self.c = c
        self.theme = theme
        self.w = w
        self.h = h
    }

    // MARK: Marks

    mutating func fill(_ p: ChartPath, _ paint: ChartPaint, _ box: ChartRect) { marks.append(ChartMark(part, .fill(p, paint, box: box), role: role)) }

    mutating func fill(_ p: ChartPath, _ col: ChartColor, _ opacity: Double = 1) {
        marks.append(ChartMark(part, .fill(p, .color(col, opacity: opacity), box: p.bounds ?? ChartRect(0, 0, 0, 0)), role: role))
    }

    mutating func stroke(_ p: ChartPath, _ s: ChartStroke) { marks.append(ChartMark(part, .stroke(p, s), role: role)) }

    mutating func label(
        _ text: String, _ r: ChartRect, _ size: Double, _ align: ChartText.Align, _ anchor: ChartText.Anchor, _ col: ChartColor, _ bold: Bool,
        _ transform: ChartTransform = .identity
    ) {
        if text.isEmpty { return }
        // A point's text is its data label; the background's has no role.
        let r0: ChartMark.Role = part == .background ? .none : .label
        marks.append(ChartMark(part, .text(ChartText(text, box: r, size: size, bold: bold, color: col, align: align, anchor: anchor, transform: transform)), role: r0))
    }

    // MARK: Colours and paints

    func seriesColor(_ i: Int) -> ChartColor { theme.seriesColor(i, monochrome: c.monochrome) }

    /// A series' one colour (lines, areas, markers): its solid fill, a pattern's foreground, a gradient's first stop,
    /// else the palette's.
    func seriesFill(_ i: Int, _ s: ChartSeries?) -> ChartColor {
        switch s?.fill {
        case .solid(let cc)?: cc
        case .pattern(let p)?: p.foreground
        case .gradient(let g)? where !g.stops.isEmpty: g.stops[0].color
        default: seriesColor(i)
        }
    }

    /// The paint of fill `f`; `fallback` when there is none.
    func paintOf(_ f: ChartFill?, _ fallback: ChartColor) -> BarPaint {
        switch f {
        case .solid(let cc)?: .color(cc)
        case .pattern(let p)?: .pattern(p)
        case .none?: .nothing
        case .gradient(let g)? where !g.stops.isEmpty: .gradient(g)
        default: .color(fallback)
        }
    }

    /// A bar series' outline: colour and width.
    func barOutline(_ s: ChartSeries) -> (ChartColor, Double)? {
        guard let l = s.line, let col = l.color else { return nil }
        return (col, (l.width ?? 0.75).clamped(0, 20))
    }

    /// Paint of one bar: a point's own fill wins, and a single series that varies colours by point uses one accent per
    /// point.
    func barPaint(_ si: Int, _ pi: Int, _ s: ChartSeries) -> BarPaint {
        if let pf = s.pointFills.first(where: { $0.index == pi }) { return paintOf(pf.fill, seriesFill(si, s)) }
        if c.varyColors && c.series.count == 1 && s.fill == nil && c.kind != .waterfall { return .color(seriesColor(pi)) }
        return paintOf(s.fill, seriesColor(si))
    }

    /// A line series' colour: its line's own, else its fill's, else the palette's.
    func seriesLine(_ i: Int, _ s: ChartSeries) -> ChartColor { s.line?.color ?? seriesFill(i, s) }

    /// Fill box `r` with `p`; with `path`, that shape laid out over `r`.
    mutating func fillWith(_ p: BarPaint, _ r: ChartRect, _ path: ChartPath? = nil) {
        switch p {
        case .color(let col): fill(path ?? .rect(r), .color(col), r)
        case .pattern(let pat): fill(path ?? .rect(r), .pattern(pat), r)
        case .gradient(let g): fill(path ?? .rect(r), .gradient(g), r)
        case .line(let col, let dashes):
            var l = ChartPath()
            l.move(to: ChartPoint(r.x0 - r.width * 0.4, r.center.y))
            l.line(to: ChartPoint(r.x1, r.center.y))
            stroke(l, ChartStroke(col, width: 1.6, dashes: dashes))
        case .nothing: break
        }
    }

    // MARK: Helpers

    static func polyline(_ pts: [ChartPoint]) -> ChartPath {
        var p = ChartPath()
        for (k, q) in pts.enumerated() {
            if k == 0 { p.move(to: q) } else { p.line(to: q) }
        }
        return p
    }

    /// The smoothed segment from point `k` to `k + 1` (a Catmull-Rom spline as a cubic Bézier, as PowerPoint draws
    /// `c:smooth`): its two control points.
    static func smoothControls(_ pts: [ChartPoint], _ k: Int) -> (ChartPoint, ChartPoint) {
        let p0 = pts[Swift.max(k - 1, 0)]
        let (p1, p2) = (pts[k], pts[k + 1])
        let p3 = pts[Swift.min(k + 2, pts.count - 1)]
        return (p1 + (p2 - p0) / 6, p2 - (p3 - p1) / 6)
    }

    /// A category label on two lines, split at its middle space ("03.11.2025 - 09.11.2025").
    static func splitLabel(_ name: String) -> String {
        let chars = Array(name.unicodeScalars)
        let mid = chars.count / 2
        var best: Int?
        for (i, ch) in chars.enumerated() where ch.properties.isWhitespace {
            if best.map({ Swift.abs(i - mid) < Swift.abs($0 - mid) }) ?? true { best = i }
        }
        guard let i = best, i > 0, i + 1 < chars.count else { return name }
        let a = String(String.UnicodeScalarView(chars[..<i]))
        let b = String(String.UnicodeScalarView(chars[i...]))
        return "\(trimEnd(a))\n\(trimStart(b))"
    }

    /// Where the legend goes, and the plot area left over: the legend block's top-left corner and the plot area. An
    /// overlaid legend leaves the plot area as it was.
    static func legendLayout(_ pos: LegendPosition, _ size: (Double, Double), _ area: ChartRect, _ base: Double, _ overlay: Bool) -> (ChartPoint, ChartRect) {
        let (lw, lh) = size
        let gap = base * 0.5
        let cx = (area.x0 + area.x1) / 2
        let cy = ((area.y0 + area.y1) / 2 - lh / 2).rustMax(area.y0)
        var plot = area
        let origin: ChartPoint
        switch pos {
        case .bottom:
            plot.y1 = area.y1 - lh - gap
            origin = ChartPoint(cx - lw / 2, area.y1 - lh)
        case .top:
            plot.y0 = area.y0 + lh + gap
            origin = ChartPoint(cx - lw / 2, area.y0)
        case .left:
            plot.x0 = area.x0 + lw + gap
            origin = ChartPoint(area.x0, cy)
        case .topRight:
            plot.x1 = area.x1 - lw - gap
            origin = ChartPoint(area.x1 - lw, area.y0)
        case .right:
            plot.x1 = area.x1 - lw - gap
            origin = ChartPoint(area.x1 - lw, cy)
        }
        return (origin, overlay ? area : plot)
    }

    static func positiveSpan(_ s: Double) -> Double { s > 0 && s.isFinite ? s : 1 }

    /// The tick values of an axis (min, max, major step), one per step (at most 51).
    static func axisTicks(_ sc: (Double, Double, Double)) -> [Double] {
        let (lo, hi, st) = sc
        let n = st > 0 ? Swift.min(Swift.max(Int64(rustCast: ((hi - lo) / st).rounded()), 1), 50) : 1
        return (0 ... n).map { lo + Double($0) * st }
    }

    /// `v` within `lo...hi` without a trap when `lo > hi`: the upper bound wins.
    static func clampSoft(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        let v = v < lo ? lo : v
        return v > hi ? hi : v
    }

    static func labelExtent(_ text: String, _ size: Double) -> (Double, Double) {
        let lines = rustLines(text)
        let widest = Double(lines.map(\.unicodeScalars.count).max() ?? 0)
        return (widest * size * 0.55, Double(Swift.max(lines.count, 1)) * size * 1.25)
    }

    // MARK: The chart

    mutating func run() {
        part = .background
        // Text without a colour of its own takes the theme's.
        let textCol = c.textColor ?? theme.text
        let gridCol = ChartColor.rgb(0xD9, 0xD9, 0xD9)
        if let f = c.chartFill {
            let all = ChartRect(0, 0, w, h)
            fillWith(paintOf(f, .white), all)
        }
        // The chart's text size when it has one; otherwise one that suits the chart.
        let base = c.textSize ?? (h.rustMin(w) / 22).clamped(7, 18)
        let titleSize = c.titleSize ?? base * 1.4
        var area = ChartRect(w * 0.04, h * 0.04, w * 0.96, h * 0.96)
        if let t = c.title {
            label(t, ChartRect(0, area.y0, w, area.y0 + titleSize * 1.3), titleSize, .center, .top, textCol, false)
            area.y0 += titleSize * 1.7
        }
        let pie = c.kind.isPie
        // Each legend entry: its name, its key's paint and the key's outline.
        let legendItems: [(String, BarPaint, (ChartColor, Double)?)]
        if c.kind == .waterfall {
            legendItems = ["Increase", "Decrease", "Total"].enumerated().map { ($1, .color(seriesColor($0)), nil) }
        } else if c.kind == .treemap || c.kind == .sunburst {
            // A hierarchy's legend names its top-level groups.
            legendItems = c.categoryTree().prefix(1000).enumerated().map { ($1.name, .color(seriesColor($0)), nil) }
        } else if c.kind == .funnel {
            legendItems = []
        } else if pie {
            legendItems = c.categories.enumerated().map { ($1, .color(seriesColor($0)), nil) }
        } else {
            legendItems = c.series.enumerated().map { i, s in
                let k = c.seriesKind(s)
                if !k.isBarLike && !k.isArea { return (s.name, .color(seriesLine(i, s)), nil) }
                if k.isBarLike {
                    let paint: BarPaint = c.varyColors && c.series.count == 1 && s.fill == nil ? .color(seriesColor(i)) : paintOf(s.fill, seriesColor(i))
                    return (s.name, paint, barOutline(s))
                }
                return (s.name, .color(seriesFill(i, s)), nil)
            } + c.series.flatMap { s in
                // The trendlines' entries, after the series', as PowerPoint lists them: each a dashed line in its ink.
                s.trendlines.prefix(8).enumerated().map { ti, t in
                    (t.legendName(series: s.name), BarPaint.line(Self.trendInk.at(ti % Self.trendInk.count) ?? .rgb(0x22, 0x22, 0x22), [6, 3.5]), nil)
                }
            }
        }
        if let pos = c.legend, !legendItems.isEmpty {
            let vertical = [.left, .right, .topRight].contains(pos)
            let itemWs = legendItems.map { Double($0.0.unicodeScalars.count) * base * 0.55 + base * 1.6 }
            let size: (Double, Double) = vertical
                ? (itemWs.reduce(0.0) { $0.rustMax($1) }.rustMin(w * 0.4), Double(legendItems.count) * base * 1.5)
                : (itemWs.reduce(0, +).rustMin(w * 0.9), base * 1.4)
            let (origin, plotArea) = Self.legendLayout(pos, size, area, base, c.legendOverlay)
            area = plotArea
            var (x, y) = (origin.x, origin.y)
            for (name, paint, outline) in legendItems {
                let key = ChartRect(x, y + base * 0.3, x + base * 0.7, y + base)
                let tw = Double(name.unicodeScalars.count) * base * 0.55 + base
                fillWith(paint, key)
                if let (oc, ow) = outline, ow > 0 { stroke(.rect(key), ChartStroke(oc, width: ow.rustMin(base * 0.2))) }
                label(name, ChartRect(x + base, y, x + base + tw, y + base * 1.3), base, .left, .middle, textCol, false)
                if vertical { y += base * 1.5 } else { x += tw + base * 0.6 }
            }
        }
        if pie {
            drawPie(area, base, textCol)
        } else if c.kind.isRadar {
            drawRadar(area, base, textCol)
        } else if c.kind.isAxisless {
            drawOffice(area, base, textCol)
        } else {
            drawAxes(area, base, textCol, gridCol)
        }
    }

    // MARK: Pie and doughnut

    mutating func drawPie(_ area: ChartRect, _ base: Double, _ textCol: ChartColor) {
        guard let s = c.series.first else { return }
        let vals = s.values.map { ($0 ?? 0).rustMax(0) }
        let total = vals.reduce(0, +)
        if !(total > 0) || !total.isFinite { return }
        let r = (area.width.rustMin(area.height) / 2) * 0.95
        if !(r > 0) { return }
        let cen = area.center
        // A doughnut's slices are rings: its hole shows what is behind the chart, as in PowerPoint.
        let hole = c.kind == .doughnut ? r * c.holeSize.clamped(0.1, 0.9) : 0
        var a0 = -Double.pi / 2
        for (i, v) in vals.enumerated() {
            part = .point(series: 0, category: i)
            let sweep = v / total * 2 * Double.pi
            var p = ChartPath()
            if hole > 0 {
                p.move(to: ChartPoint(cen.x + r * cos(a0), cen.y + r * sin(a0)))
                p.arc(center: cen, radius: r, start: a0, sweep: sweep)
                p.line(to: ChartPoint(cen.x + hole * cos(a0 + sweep), cen.y + hole * sin(a0 + sweep)))
                p.arc(center: cen, radius: hole, start: a0 + sweep, sweep: -sweep)
            } else {
                p.move(to: cen)
                p.line(to: ChartPoint(cen.x + r * cos(a0), cen.y + r * sin(a0)))
                p.arc(center: cen, radius: r, start: a0, sweep: sweep)
            }
            p.close()
            var col = seriesColor(i)
            if let pf = s.pointFills.first(where: { $0.index == i }), case .solid(let cc) = pf.fill { col = cc }
            role = .slice(center: cen, inner: hole, outer: r, start: a0, sweep: sweep)
            fill(p, col)
            stroke(p, ChartStroke(theme.separator, width: 1))
            role = .none
            if c.showsDataLabels(s) {
                let mid = a0 + sweep / 2
                let o = c.labelOptions(s)
                let pos = o.position(for: c.kind, threeD: c.threeD)
                // Along the radius by position; unset, two thirds out (on a doughnut, across the ring).
                let k: Double = switch pos {
                case .center?: 0.5
                case .insideEnd?: 0.8
                case .outsideEnd?: 1.12
                default: hole > 0 ? (1 + hole / r) / 2 : 0.65
                }
                let lp = ChartPoint(cen.x + r * k * cos(mid), cen.y + r * k * sin(mid))
                let outside = k > 1 || o.callout
                let text = c.labelText(s, i, v, share: v / total)
                let lcol = c.textColor != nil || outside ? textCol : .white
                if outside {
                    // Outside the pie, the label reads away from the centre.
                    let right = cos(mid) >= 0
                    let at = o.callout ? ChartPoint(cen.x + r * 1.1 * cos(mid), cen.y + r * 1.1 * sin(mid)) : lp
                    let box = ChartRect(right ? at.x : at.x - 200, at.y - base, right ? at.x + 200 : at.x, at.y + base)
                    dataLabel(s, 0, i, text, box, right ? .left : .right, .middle, base, lcol, ChartPoint(cen.x + r * 0.95 * cos(mid), cen.y + r * 0.95 * sin(mid)), textCol)
                } else {
                    // On the slices themselves: white, unless the chart's text was given a colour.
                    dataLabel(s, 0, i, text, ChartRect(lp.x - 30, lp.y - 10, lp.x + 30, lp.y + 10), .center, .middle, base, lcol, nil, textCol)
                }
            }
            a0 += sweep
        }
        part = .background
    }

    // MARK: Columns, bars, lines and areas

    /// An error bar to draw over everything else: its part, its position across the value axis, its two ends along
    /// it, its cap's half length, and whether it has caps.
    struct ErrorMark {
        var part: ChartPart
        var mid: Double
        var from: Double
        var to: Double
        var cap: Double
        var endCap: Bool
    }

    mutating func drawAxes(_ area0: ChartRect, _ base: Double, _ textCol: ChartColor, _ gridCol: ChartColor) {
        var area = area0
        let combo = c.kind == .combo
        // Bars are drawn first and lines over them; a combo chart has both.
        let spec = c
        let barKind = spec.series.map { spec.seriesKind($0) }.first { $0.isBarLike }
        let horiz = combo ? (barKind?.horizontal ?? false) : c.kind.horizontal
        // Axis titles: the left one turned to read upwards, the bottom one centred under the axis. On a horizontal bar
        // chart the category axis is the left one.
        let (leftTitle, bottomTitle) = horiz ? (c.categoryAxisTitle, c.valueAxisTitle) : (c.valueAxisTitle, c.categoryAxisTitle)
        let bandH = base * 1.6
        if let t = bottomTitle, !t.isEmpty {
            label(t, ChartRect(area.x0, area.y1 - bandH, area.x1, area.y1), base, .center, .bottom, textCol, true)
            area.y1 -= bandH + base * 0.3
        }
        if let t = leftTitle, !t.isEmpty {
            let (cx, cy) = (area.x0 + bandH / 2, (area.y0 + area.y1) / 2)
            let turned = ChartTransform.translate(cx, cy) * ChartTransform.rotate(-Double.pi / 2)
            let half = area.height / 2
            label(t, ChartRect(-half, -bandH / 2, half, bandH / 2), base, .center, .middle, textCol, true, turned)
            area.x0 += bandH + base * 0.3
        }
        // As many major units as the value axis has room for labels (PowerPoint's automatic unit).
        let axisLen = horiz ? area.width - base * 4.5 : area.height - base * 1.8
        let maxIntervals = Int(rustCast: (axisLen / (horiz ? base * 6 : base * 1.9)).rounded(.down).clamped(2, 12))
        // A logarithmic axis is scaled in exponents of its base.
        let logBase = c.valueAxis.logBase ?? 10
        let log = c.logAxisScale(maxIntervals)
        let (min, max, step) = log ?? c.axisScale(maxIntervals)
        let toE = { (v: Double) -> Double in
            guard log != nil else { return v }
            return (Foundation.log(v.rustMax(Double.leastNormalMagnitude)) / Foundation.log(logBase)).rustMax(min - 1)
        }
        // A combo chart's secondary value axis, on the right (vertical value axes only).
        let second = horiz ? nil : c.axisScale(secondary: true, maxIntervals)
        // Label gutters as wide as the longest value label.
        let primaryTicks = Self.axisTicks((min, max, step)).map { k in log != nil ? pow(logBase, k) : k }
        func labelW(_ ticks: [Double], _ secondary: Bool) -> Double {
            Double(ticks.map { c.axisLabel($0, secondary: secondary).unicodeScalars.count }.max() ?? 1) * base * 0.55 + base * 0.6
        }
        // A data table under the plot takes the category labels' place, its series names left of the plot.
        // (Not on a box and whisker chart, though its frame is a column chart's: PowerPoint doesn't offer one.)
        let table = horiz || boxes != nil ? nil : c.dataTable.flatMap { t in c.takesDataTable ? DataTableLayout(c, t, base) : nil }
        let gutter0 = horiz ? base * 4.5 : c.valueAxis.hidden ? base * 0.5 : Self.clampSoft(labelW(primaryTicks, false), base * 1.5, area.width * 0.3)
        let gutter = table.map { gutter0.rustMax($0.nameWidth.rustMin(area.width * 0.4)) } ?? gutter0
        let gutterR = second.flatMap { c.secondaryAxis.hidden ? nil : $0 }
            .map { Self.clampSoft(labelW(Self.axisTicks(($0.min, $0.max, $0.step)), true), base * 1.5, area.width * 0.3) } ?? 0
        let plot = horiz
            ? ChartRect(area.x0 + gutter, area.y0, area.x1, area.y1 - base * 1.6)
            : ChartRect(area.x0 + gutter, area.y0, area.x1 - gutterR, area.y1 - (table.map { $0.height.rustMin(area.height * 0.6) } ?? base * 1.8))
        if let f = c.plotFill { fillWith(paintOf(f, .white), plot) }
        let span = Self.positiveSpan(max - min)
        // Values past the axis limits stop at the plot's edge.
        let toV = { (v: Double) -> Double in
            let v = toE(v).rustMax(min).rustMin(max)
            return horiz ? plot.x0 + (v - min) / span * plot.width : plot.y1 - (v - min) / span * plot.height
        }
        // A series' value as a position on its own axis.
        let toAxis = { (sec: Bool, v: Double) -> Double in
            if sec, let s2 = second {
                return plot.y1 - (v.rustMax(s2.min).rustMin(s2.max) - s2.min) / Self.positiveSpan(s2.max - s2.min) * plot.height
            }
            return toV(v)
        }
        // Minor gridlines, under the major ones: five to a major unit.
        if c.minorGridlines {
            let minor = step / 5
            let n = minor > 0 ? Swift.min(Swift.max(Int64(rustCast: ((max - min) / minor).rounded()), 1), 500) : 1
            var g = ChartPath()
            for k in 0 ... n where k % 5 != 0 {
                // On a logarithmic axis `min`, `max` and `step` are exponents of the base.
                let e = min + Double(k) * minor
                let pos = toV(log != nil ? pow(logBase, e) : e)
                if horiz {
                    g.move(to: ChartPoint(pos, plot.y0))
                    g.line(to: ChartPoint(pos, plot.y1))
                } else {
                    g.move(to: ChartPoint(plot.x0, pos))
                    g.line(to: ChartPoint(plot.x1, pos))
                }
            }
            stroke(g, ChartStroke(.rgb(0xF2, 0xF2, 0xF2), width: 0.75))
        }
        // Gridlines and value labels.
        for v in primaryTicks {
            let pos = toV(v)
            let text = c.valueAxis.hidden ? "" : c.axisLabel(v)
            var g = ChartPath()
            if horiz {
                g.move(to: ChartPoint(pos, plot.y0))
                g.line(to: ChartPoint(pos, plot.y1))
                label(text, ChartRect(pos - 30, plot.y1 + 2, pos + 30, plot.y1 + base * 1.5), base, .center, .top, textCol, false)
            } else {
                g.move(to: ChartPoint(plot.x0, pos))
                g.line(to: ChartPoint(plot.x1, pos))
                label(text, ChartRect(area.x0, pos - base, plot.x0 - base * 0.4, pos + base), base, .right, .middle, textCol, false)
            }
            if c.gridlines { stroke(g, ChartStroke(gridCol, width: 0.75)) }
        }
        // The secondary axis' labels, on the right, without gridlines of their own.
        if let s2 = second, !c.secondaryAxis.hidden {
            for v in Self.axisTicks((s2.min, s2.max, s2.step)) {
                let pos = toAxis(true, v)
                label(c.axisLabel(v, secondary: true), ChartRect(plot.x1 + base * 0.4, pos - base, area.x1, pos + base), base, .left, .middle, textCol, false)
            }
        }
        let ncat = Swift.max(c.pointCount, 1)
        // A trendline's forecast reserves empty category slots, so the line can run past the data.
        let (back, fwd) = forecastPad()
        let nspan = Double(ncat) + back + fwd
        let band = horiz ? plot.height / nspan : plot.width / nspan
        // Where category `i`'s band starts along its axis: left to right, or bottom to top on a horizontal bar chart,
        // unless the axis is reversed. The forecast's empty slots stay on their own side of the data.
        let backwards = horiz != c.categoriesReversed
        let slot = { (i: Int) -> Double in backwards ? Double(Swift.max(ncat - (i + 1), 0)) + fwd : Double(i) + back }
        // Scatter and bubble charts have a value x axis: one scale over every series' x values, its tick labels in place
        // of the category names.
        let bubbles = BubbleScale(c, plot)
        let xscale = horiz ? nil : c.xAxisScale(Int(rustCast: (plot.width / (base * 2.5)).rounded(.down).clamped(2, 12)), pad: bubbles.padding(plot.width))
        let toX = { (v: Double) -> Double? in xscale.map { plot.x0 + (v - $0.min) / Self.positiveSpan($0.max - $0.min) * plot.width } }
        if let sc = xscale {
            for v in Self.axisTicks((sc.min, sc.max, sc.step)) {
                let pos = plot.x0 + (v - sc.min) / Self.positiveSpan(sc.max - sc.min) * plot.width
                label(ChartSpec.xAxisLabel(v), ChartRect(pos - 30, plot.y1 + 3, pos + 30, plot.y1 + base * 1.6), base, .center, .top, textCol, false)
            }
        }
        if let t = table {
            t.draw(&self, plot, band, slot, ncat, gutter, textCol)
        } else if xscale == nil {
            // Category labels: on two lines when they don't fit their band.
            let wraps = !horiz && c.categories.contains { Double($0.unicodeScalars.count) * base * 0.5 > band }
            for (i, name) in c.categories.enumerated() {
                let mid = horiz ? plot.y0 + band * (slot(i) + 0.5) : plot.x0 + band * (slot(i) + 0.5)
                if horiz {
                    label(name, ChartRect(area.x0, mid - base, plot.x0 - base * 0.4, mid + base), base, .right, .middle, textCol, false)
                } else {
                    let text = wraps ? Self.splitLabel(name) : name
                    label(text, ChartRect(mid - band / 2, plot.y1 + 3, mid + band / 2, plot.y1 + base * (wraps ? 2.8 : 1.6)), base, .center, .top, textCol, false)
                }
            }
        }
        if let b = boxes {
            drawBoxes(b, plot, band, horiz, toV)
            part = .background
            return
        }
        let zero = log != nil ? toV(pow(logBase, min)) : toV(Self.clampSoft(0, min, max))
        var errors: [ErrorMark] = []
        drawBars(plot, band, slot, ncat, horiz, toV, toAxis, base, textCol, &errors)
        if c.kind == .stock {
            for i in 0 ..< ncat { drawStockMarks(plot.x0 + band * (slot(i) + 0.5), band, i) { toAxis(false, $0) } }
        }
        drawUpDownBars(plot, band, slot, ncat, toAxis)
        drawLines(plot, band, slot, ncat, toAxis, zero, base, textCol, toX, bubbles, &errors)
        // A category position (0-based, fractional) as a slot, the way `slot` places the bars.
        let slotAt = { (x: Double) -> Double in backwards ? Double(ncat) - 1 - x + fwd : x + back }
        drawTrendlines(plot, band, slotAt, xscale.map { ($0.min, $0.max) }, ncat, horiz, base, textCol, toAxis)
        // Error bars, over everything: a horizontal bar chart's run across, its value axis being horizontal.
        for e in errors {
            part = e.part
            func pt(_ along: Double, _ across: Double) -> ChartPoint { horiz ? ChartPoint(along, across) : ChartPoint(across, along) }
            var p = ChartPath()
            p.move(to: pt(e.from, e.mid))
            p.line(to: pt(e.to, e.mid))
            if e.endCap {
                for end in [e.from, e.to] {
                    p.move(to: pt(end, e.mid - e.cap))
                    p.line(to: pt(end, e.mid + e.cap))
                }
            }
            stroke(p, ChartStroke(textCol, width: 0.75))
        }
        // The axis line.
        part = .background
        var ax = ChartPath()
        if horiz {
            ax.move(to: ChartPoint(zero, plot.y0))
            ax.line(to: ChartPoint(zero, plot.y1))
        } else {
            ax.move(to: ChartPoint(plot.x0, zero))
            ax.line(to: ChartPoint(plot.x1, zero))
        }
        stroke(ax, ChartStroke(.rgb(0xBF, 0xBF, 0xBF), width: 0.75))
    }

    mutating func drawBars(
        _ plot: ChartRect, _ band: Double, _ slot: (Int) -> Double, _ ncat: Int, _ horiz: Bool, _ toV: (Double) -> Double,
        _ toAxis: (Bool, Double) -> Double, _ base: Double, _ textCol: ChartColor, _ errors: inout [ErrorMark]
    ) {
        let bars = c.series.enumerated().filter { c.seriesKind($0.element).isBarLike }
        guard let bk = bars.first.map({ c.seriesKind($0.element) }) else { return }
        let ns = Swift.max(bars.count, 1)
        // Gap width and overlap are fractions of one bar's width: a category's band holds its bars (overlapping by
        // `overlap` of a bar between neighbours) plus one gap.
        let gap = c.gapWidth.clamped(0, 5)
        let stacked = bk.stacked
        let ov = stacked ? 1 : c.overlap.clamped(-1, 1)
        let n = Double(ns)
        let bar = band / (n - (n - 1) * ov + gap)
        let step = bar * (1 - ov)
        let group = bar + step * (n - 1)
        // Error bars need each series' mean and spread: worked out once, not per point.
        let stats = bars.map { $0.element.errorBars == nil ? SeriesStats() : SeriesStats.of($0.element.values) }
        let waterfall = c.kind == .waterfall
        let wf = waterfall ? c.waterfallBars() : []
        for i in 0 ..< ncat {
            var posAcc = 0.0
            var negAcc = 0.0
            let total = bk.percent
                ? bars.reduce(0.0) { $0 + Swift.abs(($1.element.values.at(i) ?? nil) ?? 0) }.rustMax(1e-9)
                : 1.0
            for (bi, (si, s)) in bars.enumerated() {
                part = .point(series: si, category: i)
                let sec = c.onSecondary(s)
                let v = ((s.values.at(i) ?? nil) ?? 0) / total
                let start = band * slot(i) + (band - group) / 2 + (stacked ? 0 : step * Double(bi))
                let (a, b): (Double, Double)
                if waterfall {
                    (a, b) = wf.at(i) ?? (0, 0)
                } else if stacked {
                    if v >= 0 {
                        (a, b) = (posAcc, posAcc + v)
                        posAcc += v
                    } else {
                        (a, b) = (negAcc + v, negAcc)
                        negAcc += v
                    }
                } else {
                    (a, b) = (0.0.rustMin(v), 0.0.rustMax(v))
                }
                let r = (horiz
                    ? ChartRect(toV(a), plot.y0 + start, toV(b), plot.y0 + start + bar)
                    : ChartRect(plot.x0 + start, toAxis(sec, b), plot.x0 + start + bar, toAxis(sec, a))).abs
                // A bar grows from the end nearer its stack's base (zero, or the bar under it); a waterfall's from the
                // running total it starts at.
                let baseValue = waterfall ? a : stacked ? (v >= 0 ? a : b) : 0
                role = .bar(horizontal: horiz, base: horiz ? toV(baseValue) : toAxis(sec, baseValue))
                // A waterfall colours increases, decreases and totals, and joins each bar's end to the next bar's start.
                fillWith(waterfall ? .color(seriesColor(c.subtotals.contains(i) ? 2 : b < a ? 1 : 0)) : barPaint(si, i, s), r)
                if !waterfall, let (oc, ow) = barOutline(s), ow > 0 { stroke(.rect(r), ChartStroke(oc, width: ow)) }
                role = .none
                if waterfall && i + 1 < ncat && !horiz {
                    let y = toV(b)
                    var j = ChartPath()
                    j.move(to: ChartPoint(r.x1, y))
                    j.line(to: ChartPoint(r.x1 + (band - bar), y))
                    stroke(j, ChartStroke(.rgb(0xA6, 0xA6, 0xA6), width: 0.75))
                }
                if let e = s.errorBars, let st = stats.at(bi), let (lo, hi) = e.range(st, i, v >= 0 ? b : a) {
                    let (p0, p1) = horiz ? (toV(lo), toV(hi)) : (toAxis(sec, lo), toAxis(sec, hi))
                    errors.append(ErrorMark(part: part, mid: horiz ? r.center.y : r.center.x, from: p0, to: p1, cap: bar.rustMin(base * 0.8) * 0.5, endCap: e.endCap))
                }
                if c.showsDataLabels(s), let v = s.values.at(i) ?? nil {
                    barLabel(s, si, i, c.labelText(s, i, v), r, horiz, v < 0, base, textCol)
                }
            }
        }
    }

    /// A line chart's up/down bars, behind its lines: from the first series to the last in each category, hollow where
    /// it rose. Each comes with its category's last series.
    mutating func drawUpDownBars(_ plot: ChartRect, _ band: Double, _ slot: (Int) -> Double, _ ncat: Int, _ toAxis: (Bool, Double) -> Double) {
        guard c.upDownBars, [.line, .lineMarkers, .stackedLine, .percentLine].contains(c.kind), !c.threeD, c.series.count >= 2 else { return }
        let ink = ChartColor.rgb(0x40, 0x40, 0x40)
        for i in 0 ..< ncat {
            let vals = c.series.map { ($0.values.at(i) ?? nil) ?? 0 }
            guard let o0 = c.series.first.flatMap({ $0.values.at(i) ?? nil }), let l0 = c.series.last.flatMap({ $0.values.at(i) ?? nil }) else { continue }
            let total = vals.reduce(0.0) { $0 + Swift.abs($1) }.rustMax(1e-9)
            let sum = vals.reduce(0.0, +)
            let (o, cl): (Double, Double) = switch c.kind {
            case .stackedLine: (o0, sum)
            case .percentLine: (o0 / total, sum / total)
            default: (o0, l0)
            }
            part = .point(series: c.series.count - 1, category: i)
            let x = plot.x0 + band * (slot(i) + 0.5)
            let w = band * 0.4
            let (y0, y1) = (toAxis(false, o.rustMax(cl)), toAxis(false, o.rustMin(cl)))
            let r = ChartRect(x - w / 2, y0.rustMin(y1), x + w / 2, y1.rustMax(y0 + 1))
            fill(.rect(r), cl >= o ? .white : ink)
            stroke(.rect(r), ChartStroke(ink, width: 1))
        }
        part = .background
    }

    mutating func drawLines(
        _ plot: ChartRect, _ band: Double, _ slot: (Int) -> Double, _ ncat: Int, _ toAxis: (Bool, Double) -> Double, _ zero: Double, _ base: Double,
        _ textCol: ChartColor, _ toX: (Double) -> Double?, _ bubbles: BubbleScale, _ errors: inout [ErrorMark]
    ) {
        var acc = [Double](repeating: 0, count: ncat)
        // A 100 % line or area plots each value as its share of the category's total over those series.
        let shares = c.series.filter { s in let k = c.seriesKind(s); return k.percent && !k.isBarLike }
        let totals: [Double] = shares.isEmpty ? [] : (0 ..< ncat).map { i in
            shares.reduce(0.0) { $0 + Swift.abs(($1.values.at(i) ?? nil) ?? 0) }.rustMax(1e-9)
        }
        for (si, s) in c.series.enumerated() {
            let kind = c.seriesKind(s)
            // A stock chart's series are drawn as its high-low lines and up/down bars.
            if kind.isBarLike || kind == .stock { continue }
            let xy = kind.isXY
            let sec = c.onSecondary(s)
            let markers = kind == .lineMarkers
            let areaKind = kind.isArea
            let col = areaKind ? seriesFill(si, s) : seriesLine(si, s)
            let stats = s.errorBars.map { _ in SeriesStats.of(s.values) }
            var pts: [ChartPoint] = []
            // The category of each point: the part it belongs to.
            var cats: [Int] = []
            // A stacked area's floor at each point: the top of the series below it.
            var floors: [Double] = []
            for i in 0 ..< ncat {
                guard let raw = s.values.at(i) ?? nil else { continue }
                let v0 = kind.percent ? raw / (totals.at(i) ?? 1) : raw
                var v = v0
                var floor = 0.0
                if kind.stacked {
                    let baseV = acc.at(i) ?? 0
                    if acc.indices.contains(i) { acc[i] += v0 }
                    v = baseV + v0
                    floor = baseV
                }
                var x = plot.x0 + band * (slot(i) + 0.5)
                if xy {
                    if let xv = s.xValues.at(i) ?? nil, xv.isFinite, let px = toX(xv) {
                        x = px
                    } else if s.xValues.allSatisfy({ $0 == nil }) {
                        // No x values at all: the points are numbered 1, 2, 3…
                        x = toX(Double(i) + 1) ?? x
                    } else {
                        continue
                    }
                }
                if let e = s.errorBars, let st = stats, let (lo, hi) = e.range(st, i, v) {
                    errors.append(ErrorMark(part: .point(series: si, category: i), mid: x, from: toAxis(sec, lo), to: toAxis(sec, hi), cap: base * 0.4, endCap: e.endCap))
                }
                pts.append(ChartPoint(x, toAxis(sec, v)))
                cats.append(i)
                floors.append(toAxis(sec, floor))
            }
            guard let first = pts.first, let fc = cats.first else { continue }
            if areaKind {
                // An area comes with its first point.
                part = .point(series: si, category: fc)
                role = .area(top: pts, floor: kind.stacked ? pts.indices.map { ChartPoint(pts[$0].x, floors.at($0) ?? zero) } : pts.map { ChartPoint($0.x, zero) })
                defer { role = .none }
                var a = Self.polyline(pts)
                if kind.stacked {
                    // A stacked area fills the band between its line and the series' below (the port's own; DeckCraft
                    // fills each down to the axis, so the areas overlap).
                    for (j, q) in pts.enumerated().reversed() { a.line(to: ChartPoint(q.x, floors.at(j) ?? zero)) }
                    a.close()
                } else if let l = pts.last {
                    a.line(to: ChartPoint(l.x, zero))
                    a.line(to: ChartPoint(first.x, zero))
                    a.close()
                }
                fill(a, col, kind.stacked ? 1 : 0.85)
            } else if !xy || (kind == .scatter && s.line?.color != nil) {
                // A line's segment comes with the point it runs to (a scatter series' only when it has a line). Joined
                // with round caps, the segments draw as the whole line does with round joins.
                let lw = (s.line?.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 2.25).clamped(0.25, 20)
                let smooth = s.smooth && pts.count > 2
                for j in pts.indices.dropFirst() {
                    part = .point(series: si, category: cats[j])
                    role = .segment(index: j - 1, count: pts.count - 1)
                    defer { role = .none }
                    var p = ChartPath()
                    p.move(to: pts[j - 1])
                    if smooth {
                        let (c1, c2) = Self.smoothControls(pts, j - 1)
                        p.curve(c1, c2, pts[j])
                    } else {
                        p.line(to: pts[j])
                    }
                    stroke(p, ChartStroke(col, width: lw, join: .round, cap: .round))
                }
            }
            if kind == .bubble {
                for (j, q) in pts.enumerated() {
                    part = .point(series: si, category: cats[j])
                    guard let r = bubbles.radius(s, cats[j]) else { continue }
                    let box = ChartRect(q.x - r, q.y - r, q.x + r, q.y + r)
                    role = .bubble(center: q, radius: r)
                    fillWith(barPaint(si, cats[j], s), box, .circle(q, r))
                    if let (oc, ow) = barOutline(s), ow > 0 { stroke(.circle(q, r), ChartStroke(oc, width: ow)) }
                    role = .none
                }
            }
            if markers || kind == .scatter {
                role = .marker
                for (j, q) in pts.enumerated() {
                    part = .point(series: si, category: cats[j])
                    fill(.circle(q, 3.5), col)
                }
                role = .none
            }
            for (j, q) in pts.enumerated() {
                part = .point(series: si, category: cats[j])
                // An area's points stay unlabelled, as PowerPoint places an area's labels without a position.
                if !areaKind, c.showsDataLabels(s), let v = s.values.at(cats[j]) ?? nil {
                    let gap = kind == .bubble ? bubbles.radius(s, cats[j]) ?? 0 : markers || s.marker || kind == .scatter ? 3.5 : 0
                    pointLabel(s, si, cats[j], c.labelText(s, cats[j], v), q, gap, base * 0.9, textCol)
                }
            }
        }
        part = .background
    }

    // MARK: Box and whisker

    /// Boxes from the first to the third quartile with the median line and a mean marker, whiskers to the furthest
    /// points within 1.5 IQR, and outliers as dots; series side by side in each group's band. Each box is its series'
    /// point in its group.
    mutating func drawBoxes(_ b: [[BoxStats?]], _ plot: ChartRect, _ band: Double, _ horiz: Bool, _ toV: (Double) -> Double) {
        let ns = Swift.max(b.count, 1)
        let group = band / (1 + c.gapWidth.clamped(0, 5))
        let w = group / Double(ns)
        let line = ChartColor.rgb(0x40, 0x40, 0x40)
        for (si, per) in b.enumerated() {
            let fillCol = seriesColor(si)
            for (gi, st) in per.enumerated() {
                guard let st else { continue }
                part = .point(series: si, category: gi)
                let c0 = (horiz ? plot.y0 : plot.x0) + band * Double(gi) + (band - group) / 2 + w * Double(si)
                let (a, z) = (c0 + w * 0.1, c0 + w * 0.9)
                let mid = (a + z) / 2
                // Along the category axis `a…z`, along the value axis `toV`.
                func rect(_ p: Double, _ q: Double, _ u: Double, _ v: Double) -> ChartRect {
                    horiz ? ChartRect(u.rustMin(v), p, u.rustMax(v), q) : ChartRect(p, u.rustMin(v), q, u.rustMax(v))
                }
                func pt(_ along: Double, _ val: Double) -> ChartPoint { horiz ? ChartPoint(val, along) : ChartPoint(along, val) }
                let bx = rect(a, z, toV(st.q1), toV(st.q3))
                fill(.rect(bx), fillCol)
                var p = ChartPath()
                // Whiskers with caps, and the median.
                for (from, to) in [(st.q3, st.high), (st.q1, st.low)] {
                    p.move(to: pt(mid, toV(from)))
                    p.line(to: pt(mid, toV(to)))
                    p.move(to: pt(mid - w * 0.2, toV(to)))
                    p.line(to: pt(mid + w * 0.2, toV(to)))
                }
                p.move(to: pt(a, toV(st.median)))
                p.line(to: pt(z, toV(st.median)))
                let ink = ChartStroke(line, width: 1.25)
                stroke(p, ink)
                stroke(.rect(bx), ink)
                // The mean as an x.
                let (mx, r) = (pt(mid, toV(st.mean)), (w * 0.08).clamped(1.5, 5))
                var x = ChartPath()
                x.move(to: ChartPoint(mx.x - r, mx.y - r))
                x.line(to: ChartPoint(mx.x + r, mx.y + r))
                x.move(to: ChartPoint(mx.x - r, mx.y + r))
                x.line(to: ChartPoint(mx.x + r, mx.y - r))
                stroke(x, ink)
                for o in st.outliers.prefix(10_000) {
                    let q = pt(mid, toV(o))
                    fill(.circle(q, r), fillCol)
                    stroke(.circle(q, r), ink)
                }
            }
        }
    }

    // MARK: Funnel, treemap and sunburst

    /// Office 2016's charts without axes, inside `area`. From DeckCraftNative's DCRender/ChartEx.swift, a port of
    /// deckcraft crates/render/src/chartex.rs (MIT OR Apache-2.0).
    mutating func drawOffice(_ area: ChartRect, _ base: Double, _ textCol: ChartColor) {
        guard let s = c.series.first else { return }
        let vals = s.values.prefix(100_000).map { ($0 ?? 0).isFinite ? ($0 ?? 0).rustMax(0) : 0 }
        if vals.allSatisfy({ $0 <= 0 }) { return }
        let labels = c.showsDataLabels(s) || c.kind == .funnel
        let spec = c
        let (th, mono) = (theme, c.monochrome)
        let valueLabel: ((Double) -> String)? = labels ? { v in spec.dataLabel(s, v) } : nil
        switch c.kind {
        case .funnel: drawFunnel(area, base, textCol, vals, s)
        case .treemap: placeTiles(c.categoryTree(), area, base, { th.seriesColor($0, monochrome: mono) }, 0, valueLabel)
        default: drawSunburst(area, base)
        }
        part = .background
    }

    /// Bars centred on one axis, as wide as their value, widest first as given: category labels on the left, values
    /// inside. Each bar grows out from the middle.
    mutating func drawFunnel(_ area: ChartRect, _ base: Double, _ textCol: ChartColor, _ vals: [Double], _ s: ChartSeries) {
        let n = Swift.max(vals.count, 1)
        let gutter = Double(c.categories.prefix(n).map(\.unicodeScalars.count).max() ?? 0) * base * 0.55 + base
        let plot = ChartRect(area.x0 + gutter.rustMin(area.width * 0.4), area.y0, area.x1, area.y1)
        let max = vals.reduce(0.0) { $0.rustMax($1) }.rustMax(1e-9)
        let band = plot.height / Double(n)
        let cx = plot.center.x
        for (i, v) in vals.enumerated() {
            let w = v / max * plot.width
            let y = plot.y0 + band * Double(i)
            let r = ChartRect(cx - w / 2, y + band * 0.05, cx + w / 2, y + band * 0.95)
            part = .background
            if let name = c.categories.at(i) {
                label(name, ChartRect(area.x0, y, plot.x0 - base * 0.4, y + band), base, .right, .middle, textCol, false)
            }
            part = .point(series: 0, category: i)
            role = .bar(horizontal: true, base: cx)
            fill(.rect(r), seriesColor(0))
            role = .none
            label(c.dataLabel(s, v), ChartRect(cx - 60, y, cx + 60, y + band), base, .center, .middle, .white, false)
        }
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk): rows of tiles laid along the short side, each row kept while it
    /// improves the worst aspect ratio.
    static func squarify(_ vals: [Double], _ r: ChartRect) -> [ChartRect] {
        let total = vals.reduce(0, +)
        var out = [ChartRect](repeating: ChartRect(0, 0, 0, 0), count: vals.count)
        let area = r.width * r.height
        if !(total > 0) || !total.isFinite || !(area > 0) { return out }
        let scale = area / total
        // Largest first, ties in order.
        let order = vals.indices.filter { vals[$0] > 0 }.enumerated().sorted { a, b in
            let (x, y) = (vals[a.element], vals[b.element])
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
        var free = r
        var i = 0
        while i < order.count {
            let short = free.width.rustMin(free.height)
            if !short.isFinite || short <= 1e-9 { break }
            let s2 = short * short
            let a0 = vals[order[i]] * scale
            var (curSum, curMax, curMin) = (a0, a0, a0)
            var curWorst = ((s2 * curMax) / (curSum * curSum)).rustMax((curSum * curSum) / (s2 * curMin))
            var end = i + 1
            while end < order.count {
                let nextA = vals[order[end]] * scale
                let candSum = curSum + nextA
                let candMax = curMax.rustMax(nextA)
                let candMin = curMin.rustMin(nextA)
                let candWorst = ((s2 * candMax) / (candSum * candSum)).rustMax((candSum * candSum) / (s2 * candMin))
                if candWorst.isFinite && candWorst <= curWorst {
                    (curSum, curMax, curMin, curWorst) = (candSum, candMax, candMin, candWorst)
                    end += 1
                } else {
                    break
                }
            }
            let thick = curSum / short
            if !thick.isFinite || thick <= 0 { break }
            var at = 0.0
            for k in order[i ..< end] {
                let len = vals[k] * scale / thick
                out[k] = free.width >= free.height
                    ? ChartRect(free.x0, free.y0 + at, free.x0 + thick, free.y0 + at + len)
                    : ChartRect(free.x0 + at, free.y0, free.x0 + at + len, free.y0 + thick)
                at += len
            }
            free = free.width >= free.height
                ? ChartRect(free.x0 + thick, free.y0, free.x1, free.y1)
                : ChartRect(free.x0, free.y0 + thick, free.x1, free.y1)
            i = end
        }
        return out
    }

    /// `col` mixed toward white by `k` (0…0.8): deeper hierarchy levels are lighter.
    static func lighten(_ col: ChartColor, _ k: Double) -> ChartColor {
        let k = k.clamped(0, 0.8)
        func f(_ v: UInt8) -> UInt8 { UInt8(rustCast: (Double(v) + (255 - Double(v)) * k).rounded()) }
        return .rgb(f(col.r), f(col.g), f(col.b))
    }

    /// A treemap's tiles: `nodes` squarified in `r`. A leaf is a tile with its name (and value); a group is a tile with
    /// its name in a banner along the top and its children squarified below it, lighter. A tile grows out from its
    /// centre; a group comes with its first category.
    mutating func placeTiles(
        _ nodes: [ChartTreeNode], _ r: ChartRect, _ base: Double, _ col: (Int) -> ChartColor, _ depth: Int, _ valueLabel: ((Double) -> String)?
    ) {
        if depth > Self.maxTreeDepth { return }
        let flat = c.categoryLevels.isEmpty
        for (i, (n, t)) in zip(nodes, Self.squarify(nodes.map(\.value), r)).enumerated() where t.width * t.height > 0 {
            let fillCol = col(i)
            part = .point(series: 0, category: n.firstLeaf ?? 0)
            if n.children.isEmpty {
                role = .radial(center: t.center)
                fill(.rect(t), fillCol)
                stroke(.rect(t), ChartStroke(.white, width: flat ? 1.5 : 1))
                role = .none
                var text = n.name
                if let f = valueLabel { text = "\(text)\n\(f(n.value))" }
                let inner = t.inset(by: base * 0.3)
                if inner.width > base && inner.height > base { label(text, inner, flat ? base : base * 0.9, .left, .top, .white, false) }
                continue
            }
            // A group: its banner, then its children below it.
            let banner = (base * 1.5).rustMin(t.height * 0.3)
            role = .radial(center: t.center)
            fill(.rect(t), fillCol)
            role = .none
            if t.width > base * 2 && banner > base * 0.8 {
                label(n.name, ChartRect(t.x0 + base * 0.3, t.y0, t.x1 - base * 0.3, t.y0 + banner), base, .left, .middle, .white, true)
            }
            let inner = ChartRect(t.x0 + 1, t.y0 + banner, t.x1 - 1, t.y1 - 1)
            let k = Self.lighten(fillCol, 0.12 * Double(depth + 1))
            placeTiles(n.children, inner, base, { _ in k }, depth + 1, valueLabel)
            part = .point(series: 0, category: n.firstLeaf ?? 0)
            role = .radial(center: t.center)
            stroke(.rect(t), ChartStroke(.white, width: 2))
            role = .none
        }
    }

    static let maxTreeDepth = 16

    /// A closed ring segment from angle `a` sweeping `sweep`, between radii `ri` and `ro`.
    static func ringSegment(_ cen: ChartPoint, _ ri: Double, _ ro: Double, _ a: Double, _ sweep: Double) -> ChartPath {
        var p = ChartPath()
        p.move(to: ChartPoint(cen.x + ri * cos(a), cen.y + ri * sin(a)))
        p.line(to: ChartPoint(cen.x + ro * cos(a), cen.y + ro * sin(a)))
        p.arc(center: cen, radius: ro, start: a, sweep: sweep)
        let a1 = a + sweep
        p.line(to: ChartPoint(cen.x + ri * cos(a1), cen.y + ri * sin(a1)))
        p.arc(center: cen, radius: ri, start: a1, sweep: -sweep)
        p.close()
        return p
    }

    /// A sunburst: without outer levels one ring with the centre open; with them, the top level as the inner ring and
    /// each deeper level in the next ring out, within its parent's angle, coloured by top-level group and lighter
    /// further out. A segment sweeps round as it grows and comes with its first category.
    mutating func drawSunburst(_ area: ChartRect, _ base: Double) {
        let tree = c.categoryTree()
        let flat = c.categoryLevels.isEmpty
        func depth(_ n: [ChartTreeNode], _ d: Int) -> Int { d > Self.maxTreeDepth ? d : n.map { 1 + depth($0.children, d + 1) }.max() ?? 0 }
        let levels = Swift.max(depth(tree, 0), 1)
        let total = tree.reduce(0.0) { $0 + $1.value }
        if !(total > 0) { return }
        let r = area.width.rustMin(area.height) / 2 * 0.95
        if !(r > 0) { return }
        let hole = r * (flat ? 0.35 : 0.2)
        let ring = (r - hole) / Double(levels)
        let cen = area.center
        func ringOf(_ l: inout Layout, _ nodes: [ChartTreeNode], _ a0: Double, _ span: Double, _ d: Int, _ col: (Int) -> ChartColor) {
            if d > Self.maxTreeDepth { return }
            let sum = nodes.reduce(0.0) { $0 + $1.value }
            if sum <= 0 { return }
            let (ri, ro) = (hole + ring * Double(d), hole + ring * Double(d + 1))
            var a = a0
            for (i, n) in nodes.enumerated() {
                let sweep = n.value / sum * span
                if !(sweep > 0) { continue }
                let fillCol = col(i)
                let p = Self.ringSegment(cen, ri, ro, a, sweep)
                l.part = .point(series: 0, category: n.firstLeaf ?? 0)
                l.role = .slice(center: cen, inner: ri, outer: ro, start: a, sweep: sweep)
                l.fill(p, fillCol)
                l.stroke(p, ChartStroke(.white, width: 1.5))
                l.role = .none
                let mid = a + sweep / 2
                let rr = (ri + ro) / 2
                if flat {
                    if sweep > 0.25, !n.name.isEmpty {
                        let lp = ChartPoint(cen.x + rr * cos(mid), cen.y + rr * sin(mid))
                        l.label(n.name, ChartRect(lp.x - 50, lp.y - base, lp.x + 50, lp.y + base), base, .center, .middle, .white, false)
                    }
                } else if sweep * rr > base * 2.5 && !n.name.isEmpty {
                    // Labels where the segment has room for them.
                    let lp = ChartPoint(cen.x + rr * cos(mid), cen.y + rr * sin(mid))
                    let half = (ring * 0.48).rustMax(base)
                    l.label(n.name, ChartRect(lp.x - half, lp.y - base, lp.x + half, lp.y + base), base * 0.9, .center, .middle, .white, false)
                }
                if !n.children.isEmpty {
                    let k = Self.lighten(fillCol, 0.15)
                    ringOf(&l, n.children, a, sweep, d + 1) { _ in k }
                }
                a += sweep
            }
        }
        let (th, mono) = (theme, c.monochrome)
        var l = self
        ringOf(&l, tree, -Double.pi / 2, 2 * Double.pi, 0) { th.seriesColor($0, monochrome: mono) }
        self = l
    }

    // MARK: Stock

    /// A stock chart's marks at category `i`: the high-low line, then the up/down bar between the first (open) and last
    /// (close) series, else a dash at the close. They come with the category's last series.
    mutating func drawStockMarks(_ x: Double, _ band: Double, _ i: Int, _ toY: (Double) -> Double) {
        let vals = c.series.compactMap { $0.values.at(i) ?? nil }
        if vals.count < 2 { return }
        part = .point(series: c.series.count - 1, category: i)
        defer { part = .background }
        let hi = vals.reduce(-Double.greatestFiniteMagnitude) { $0.rustMax($1) }
        let lo = vals.reduce(Double.greatestFiniteMagnitude) { $0.rustMin($1) }
        let ink = ChartColor.rgb(0x40, 0x40, 0x40)
        var p = ChartPath()
        p.move(to: ChartPoint(x, toY(hi)))
        p.line(to: ChartPoint(x, toY(lo)))
        stroke(p, ChartStroke(ink, width: 1))
        let open = c.series.first.flatMap { $0.values.at(i) ?? nil }
        let close = c.series.last.flatMap { $0.values.at(i) ?? nil }
        if c.upDownBars && c.series.count >= 4 {
            guard let o = open, let cl = close else { return }
            let w = band * 0.4
            let (y0, y1) = (toY(o.rustMax(cl)), toY(o.rustMin(cl)))
            let r = ChartRect(x - w / 2, y0, x + w / 2, y1.rustMax(y0 + 1))
            // PowerPoint's default: white when the price rose, dark when it fell.
            fill(.rect(r), cl >= o ? .white : ink)
            stroke(.rect(r), ChartStroke(ink, width: 1))
            return
        }
        if let cl = close, let last = c.series.last {
            let y = toY(cl)
            var d = ChartPath()
            d.move(to: ChartPoint(x - band * 0.12, y))
            d.line(to: ChartPoint(x + band * 0.12, y))
            stroke(d, ChartStroke(seriesLine(c.series.count - 1, last), width: 2.5))
        }
    }

    // MARK: Radar

    /// The point at `frac` of the radius along spoke `i` of `n` (the first spoke points up).
    static func spoke(_ cen: ChartPoint, _ r: Double, _ i: Int, _ n: Int, _ frac: Double) -> ChartPoint {
        let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(Swift.max(n, 1))
        return ChartPoint(cen.x + r * frac * cos(a), cen.y + r * frac * sin(a))
    }

    /// A radar chart: one spoke per category, the value axis running up the first spoke, a polygon of gridlines per
    /// major unit, and each series a closed polygon (filled on a filled radar). A series' polygon comes with its first
    /// point and grows out from the centre; its markers and labels come with their points. From DeckCraftNative's
    /// DCRender/Radar.swift, a port of deckcraft crates/render/src/radar.rs (MIT OR Apache-2.0).
    mutating func drawRadar(_ area: ChartRect, _ base: Double, _ textCol: ChartColor) {
        let n = Swift.min(c.pointCount, 1000)
        // Fewer than three spokes make no polygon; PowerPoint draws a line, this draws nothing.
        if n < 3 { return }
        let gridCol = ChartColor.rgb(0xD9, 0xD9, 0xD9)
        // Room for the category labels around the outside.
        let r = (area.width.rustMin(area.height) / 2 - base * 1.9).rustMax(base)
        let cen = area.center
        let (min, max, step) = c.axisScale(secondary: false, 5) ?? (0, 1, 0.2)
        let span = Self.positiveSpan(max - min)
        let ticks = step > 0 ? Swift.min(Swift.max(Int64(rustCast: ((max - min) / step).rounded()), 1), 20) : 1
        if c.gridlines {
            for k in 1 ... ticks {
                let frac = Double(k) / Double(ticks)
                var p = ChartPath()
                for i in 0 ..< n {
                    let q = Self.spoke(cen, r, i, n, frac)
                    if i == 0 { p.move(to: q) } else { p.line(to: q) }
                }
                p.close()
                stroke(p, ChartStroke(gridCol, width: 0.75))
            }
        }
        for i in 0 ..< n {
            var p = ChartPath()
            p.move(to: cen)
            p.line(to: Self.spoke(cen, r, i, n, 1))
            stroke(p, ChartStroke(gridCol, width: 0.75))
            if let name = c.categories.at(i) {
                let q = Self.spoke(cen, r + base * 1.3, i, n, 1)
                let w = Double(name.unicodeScalars.count) * base * 0.55 + base
                let align: ChartText.Align = Swift.abs(q.x - cen.x) < base ? .center : q.x > cen.x ? .left : .right
                let x0 = switch align {
                case .left: q.x - base * 0.3
                case .right: q.x - w + base * 0.3
                default: q.x - w / 2
                }
                label(name, ChartRect(x0, q.y - base * 0.7, x0 + w, q.y + base * 0.7), base, align, .middle, textCol, false)
            }
        }
        // Value labels up the first spoke.
        if !c.valueAxis.hidden {
            for k in 0 ... ticks {
                let v = min + step * Double(k)
                let q = Self.spoke(cen, r, 0, n, Double(k) / Double(ticks))
                let t = c.axisLabel(v)
                let w = Double(t.unicodeScalars.count) * base * 0.55 + base * 0.4
                label(t, ChartRect(q.x - w - base * 0.3, q.y - base * 0.6, q.x - base * 0.3, q.y + base * 0.6), base * 0.9, .right, .middle, textCol, false)
            }
        }
        let filled = c.kind == .filledRadar
        for (si, s) in c.series.enumerated() {
            let pts = (0 ..< n).map { i -> ChartPoint in
                let v = (s.values.at(i) ?? nil) ?? min
                return Self.spoke(cen, r, i, n, ((v - min) / span).clamped(0, 1.2))
            }
            var p = ChartPath()
            for (i, q) in pts.enumerated() {
                if i == 0 { p.move(to: q) } else { p.line(to: q) }
            }
            p.close()
            part = .point(series: si, category: 0)
            role = .radial(center: cen)
            if filled {
                fill(p, seriesFill(si, s), 0.75)
            } else {
                let lw = (s.line?.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 2.25).clamped(0.25, 20)
                stroke(p, ChartStroke(seriesLine(si, s), width: lw, join: .round))
            }
            role = .none
            if !filled && s.marker {
                role = .marker
                for (i, q) in pts.enumerated() {
                    part = .point(series: si, category: i)
                    fill(.circle(q, 3.5), seriesLine(si, s))
                }
                role = .none
            }
            if c.showsDataLabels(s) {
                for (i, q) in pts.enumerated() {
                    guard let v = s.values.at(i) ?? nil else { continue }
                    part = .point(series: si, category: i)
                    label(c.labelText(s, i, v), ChartRect(q.x - 40, q.y - base * 1.4, q.x + 40, q.y - base * 0.2), base * 0.9, .center, .bottom, textCol, false)
                }
            }
        }
        part = .background
    }

    // MARK: Trendlines

    static func padUnits(_ v: Double?) -> Double { v.flatMap { $0.isFinite && $0 > 0 ? $0.rustMin(3) : nil } ?? 0 }

    /// Empty category slots reserved for a trendline forecast (backward, forward), capped so the data still fills the
    /// plot.
    func forecastPad() -> (Double, Double) {
        if c.kind.isXY { return (0, 0) }
        var back = 0.0
        var fwd = 0.0
        for s in c.series where !c.seriesKind(s).isXY {
            for t in s.trendlines.prefix(8) where t.kind != .movingAvg {
                back = back.rustMax(Self.padUnits(t.backward))
                fwd = fwd.rustMax(Self.padUnits(t.forward))
            }
        }
        return (back, fwd)
    }

    /// A trendline's ink, by its place among its series' trendlines.
    static let trendInk: [ChartColor] = [.rgb(0x22, 0x22, 0x22), .rgb(0xB0, 0x30, 0x30), .rgb(0x1A, 0x5C, 0x7A), .rgb(0xA0, 0x68, 0x00)]

    static func mapXY(
        _ plot: ChartRect, _ band: Double, _ slot: (Double) -> Double, _ horiz: Bool, _ scatter: Bool, _ sx0: Double, _ sx1: Double,
        _ sec: Bool, _ x: Double, _ y: Double, _ toAxis: (Bool, Double) -> Double
    ) -> ChartPoint? {
        if !x.isFinite || !y.isFinite { return nil }
        let value = toAxis(sec, y)
        if !value.isFinite { return nil }
        let along: Double
        if scatter && sx1 > sx0 {
            along = plot.x0 + (x - sx0) / (sx1 - sx0) * plot.width
        } else {
            along = (horiz ? plot.y0 : plot.x0) + band * (slot(x - 1) + 0.5)
        }
        if !along.isFinite { return nil }
        return horiz && !scatter ? ChartPoint(value, along) : ChartPoint(along, value)
    }

    /// The part of segment `a`–`b` that lies inside `r`.
    static func clipSegment(_ a: ChartPoint, _ b: ChartPoint, _ r: ChartRect) -> (ChartPoint, ChartPoint)? {
        var (t0, t1) = (0.0, 1.0)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let p = [-dx, dx, -dy, dy]
        let q = [a.x - r.x0, r.x1 - a.x, a.y - r.y0, r.y1 - a.y]
        for i in 0 ..< 4 {
            let (pi, qi) = (p[i], q[i])
            if Swift.abs(pi) < 1e-12 {
                if qi < 0 { return nil }
            } else {
                let t = qi / pi
                if pi < 0 {
                    if t > t1 { return nil } else if t > t0 { t0 = t }
                } else if t < t0 {
                    return nil
                } else if t < t1 {
                    t1 = t
                }
            }
        }
        return (ChartPoint(a.x + t0 * dx, a.y + t0 * dy), ChartPoint(a.x + t1 * dx, a.y + t1 * dy))
    }

    /// A corner of `plot` whose box stays clear of `pts` (the drawn trendline).
    static func captionAt(_ plot: ChartRect, _ boxW: Double, _ boxH: Double, _ pts: [ChartPoint], _ n: Int) -> (Double, Double) {
        let pad = 4.0
        let shift = Double(n) * (boxH + 2)
        let xRight = (plot.x1 - boxW - pad).rustMax(plot.x0 + pad)
        let yBottom = (plot.y1 - boxH - pad - shift).rustMax(plot.y0 + pad)
        let yTop = (plot.y0 + pad + shift).rustMin(yBottom)
        let corners = [(plot.x0 + pad, yTop), (xRight, yTop), (plot.x0 + pad, yBottom), (xRight, yBottom)]
        var best = corners[0]
        var bestD = -1.0
        for (x, y) in corners {
            var minD = Double.greatestFiniteMagnitude
            for p in pts {
                let dx = p.x < x ? x - p.x : p.x > x + boxW ? p.x - (x + boxW) : 0
                let dy = p.y < y ? y - p.y : p.y > y + boxH ? p.y - (y + boxH) : 0
                minD = minD.rustMin((dx * dx + dy * dy).squareRoot())
            }
            if pts.isEmpty { minD = 1 }
            if minD > bestD {
                bestD = minD
                best = (x, y)
            }
        }
        return best
    }

    /// Each series' trendlines, dashed, with their equation and R² in a box in the corner that stays clearest of them.
    /// A trendline comes with its series' last point.
    mutating func drawTrendlines(
        _ plot: ChartRect, _ band: Double, _ slot: (Double) -> Double, _ xscale: (Double, Double)?, _ ncat: Int, _ horiz: Bool, _ base: Double,
        _ textCol: ChartColor, _ toAxis: (Bool, Double) -> Double
    ) {
        var labelN = 0
        for (si, s) in c.series.enumerated() where !s.trendlines.isEmpty {
            let scatter = c.seriesKind(s).isXY
            let sec = c.onSecondary(s)
            var xs: [Double] = []
            var ys: [Double] = []
            for i in 0 ..< ncat {
                guard let y = s.values.at(i) ?? nil, y.isFinite else { continue }
                let x: Double
                if scatter {
                    guard let xv = s.xValues.at(i) ?? nil, xv.isFinite else { continue }
                    x = xv
                } else {
                    x = Double(i + 1)
                }
                xs.append(x)
                ys.append(y)
            }
            // The same x extent the scatter marks use, so the fit sits on the points: the chart's value x axis where it
            // has one, else the series' own x values.
            var (sx0, sx1) = (0.0, 0.0)
            if scatter, let (lo, hi) = xscale {
                (sx0, sx1) = (lo, hi)
            } else if scatter {
                var lo = Double.greatestFiniteMagnitude
                var hi = -Double.greatestFiniteMagnitude
                for v in s.xValues.compactMap({ $0 }) where v.isFinite {
                    lo = lo.rustMin(v)
                    hi = hi.rustMax(v)
                }
                (sx0, sx1) = (lo, hi)
            }
            part = .point(series: si, category: ncat - 1)
            for (ti, t) in s.trendlines.prefix(8).enumerated() {
                guard let fit = t.fit(xs, ys) else { continue }
                let (x0, x1) = fit.span(t.forward, t.backward)
                let samples = fit.samples(x0, x1)
                var path = ChartPath()
                var prev: ChartPoint?
                var inkPts: [ChartPoint] = []
                var any = false
                for k in samples.indices.dropLast() {
                    let (w0, w1) = (samples[k], samples[k + 1])
                    guard let a = Self.mapXY(plot, band, slot, horiz, scatter, sx0, sx1, sec, w0.x, w0.y, toAxis),
                          let b = Self.mapXY(plot, band, slot, horiz, scatter, sx0, sx1, sec, w1.x, w1.y, toAxis),
                          let (ca, cb) = Self.clipSegment(a, b, plot)
                    else {
                        prev = nil
                        continue
                    }
                    let cont = prev.map { Swift.abs($0.x - ca.x) < 0.6 && Swift.abs($0.y - ca.y) < 0.6 } ?? false
                    if !cont { path.move(to: ca) }
                    path.line(to: cb)
                    prev = cb
                    if inkPts.count < 64 {
                        inkPts.append(ca)
                        inkPts.append(cb)
                    }
                    any = true
                }
                if !any { continue }
                let ink = Self.trendInk.at(ti % Self.trendInk.count) ?? .rgb(0x22, 0x22, 0x22)
                stroke(path, ChartStroke(ink, width: 1.6, dashes: [6, 3.5], cap: .round))
                let caption = t.caption(fit)
                if caption.isEmpty { continue }
                let lines = caption.unicodeScalars.filter { $0 == "\n" }.count + 1
                let boxH = base * 1.3 * Double(lines) + 2
                let widest = Double(rustLines(caption).map(\.unicodeScalars.count).max() ?? 1)
                let boxW = Self.clampSoft(widest * base * 0.62, 48, plot.width * 0.72)
                let (x, y) = Self.captionAt(plot, boxW, boxH, inkPts, labelN)
                let box = ChartRect(x, y, x + boxW, y + boxH)
                fill(.rect(box), .white)
                label(caption, box, (base * 0.9).clamped(8, 13), .left, .top, textCol, false)
                labelN += 1
            }
        }
        part = .background
    }

    // MARK: Data labels

    /// One data label of series `s` (index `si`, point `i`): `text` placed in `box`, with the series' legend key before
    /// it when its options show one, and in a callout box pointing at `target` when they ask for one.
    mutating func dataLabel(
        _ s: ChartSeries, _ si: Int, _ i: Int, _ text: String, _ box: ChartRect, _ align: ChartText.Align, _ anchor: ChartText.Anchor, _ size: Double,
        _ col: ChartColor, _ target: ChartPoint?, _ textCol: ChartColor
    ) {
        let o = c.labelOptions(s)
        let was = role
        role = .label
        defer { role = was }
        if !o.legendKey && !o.callout {
            label(text, box, size, align, anchor, col, false)
            return
        }
        let (tw, th) = Self.labelExtent(text, size)
        let key = o.legendKey ? size * 0.6 : 0
        let gap = key > 0 ? size * 0.3 : 0
        let w = tw + key + gap
        let x0 = align == .left ? box.x0 : align == .right ? box.x1 - w : box.center.x - w / 2
        let y0 = anchor == .top ? box.y0 : anchor == .bottom ? box.y1 - th : box.center.y - th / 2
        if o.callout {
            let pad = size * 0.3
            let r = ChartRect(x0 - pad, y0 - pad, x0 + w + pad, y0 + th + pad)
            var p = ChartPath.rect(r)
            if let t = target, !r.contains(t) {
                // The pointer leaves the box's side nearest the point.
                let half = Swift.min(r.width, r.height) * 0.2
                if t.y > r.y1 || t.y < r.y0 {
                    let y = t.y > r.y1 ? r.y1 : r.y0
                    let x = t.x.clamped(r.x0 + half, r.x1 - half)
                    p.move(to: ChartPoint(x - half, y))
                    p.line(to: t)
                    p.line(to: ChartPoint(x + half, y))
                } else {
                    let x = t.x > r.x1 ? r.x1 : r.x0
                    let y = t.y.clamped(r.y0 + half, r.y1 - half)
                    p.move(to: ChartPoint(x, y - half))
                    p.line(to: t)
                    p.line(to: ChartPoint(x, y + half))
                }
                p.close()
            }
            fill(p, theme.separator)
            stroke(p, ChartStroke(.rgb(0xA6, 0xA6, 0xA6), width: 0.75))
        }
        if key > 0 {
            let k = ChartRect(x0, y0 + (th - key) / 2, x0 + key, y0 + (th + key) / 2)
            fillWith(c.varyColors && c.series.count == 1 ? .color(seriesColor(i)) : paintOf(s.fill, seriesColor(si)), k)
        }
        let tx = x0 + key + gap
        label(text, ChartRect(tx, y0, tx + tw + size, y0 + th), size, .left, .top, o.callout ? textCol : col, false)
    }

    /// A bar's data label by its position: outside or inside its value end, centred, or inside its base. Unset,
    /// DeckCraft's place (above a column, after a bar).
    mutating func barLabel(
        _ s: ChartSeries, _ si: Int, _ i: Int, _ text: String, _ r: ChartRect, _ horiz: Bool, _ negative: Bool, _ base: Double, _ col: ChartColor
    ) {
        let size = base * 0.9
        let o = c.labelOptions(s)
        var pos = o.position(for: c.seriesKind(s), threeD: c.threeD) ?? (o.callout ? .outsideEnd : nil)
        if pos == .outsideEnd && !negative && !o.callout { pos = nil }
        let (tw, th) = Self.labelExtent(text, size)
        let lift = o.callout ? size * 0.9 : 0
        if horiz {
            // The value end is on the right (the left for a negative bar).
            let (endX, baseX) = negative ? (r.x0, r.x1) : (r.x1, r.x0)
            let out = negative ? -1.0 : 1.0
            let target = ChartPoint(endX, r.center.y)
            switch pos {
            case .center?: dataLabel(s, si, i, text, r, .center, .middle, size, col, nil, col)
            case .insideEnd?:
                dataLabel(s, si, i, text, ChartRect(endX - out * (tw + size * 2), r.y0, endX - out * 2, r.y1).abs, negative ? .left : .right, .middle, size, col, nil, col)
            case .insideBase?:
                dataLabel(s, si, i, text, ChartRect(baseX + out * 2, r.y0, baseX + out * (tw + size * 2), r.y1).abs, negative ? .right : .left, .middle, size, col, nil, col)
            case .outsideEnd?:
                dataLabel(s, si, i, text, ChartRect(endX + out * (2 + lift), r.y0, endX + out * (tw + size * 2 + lift), r.y1).abs, negative ? .right : .left, .middle, size, col, target, col)
            default: dataLabel(s, si, i, text, ChartRect(r.x1 + 2, r.y0, r.x1 + 40, r.y1), .left, .middle, size, col, nil, col)
            }
        } else {
            let (endY, baseY) = negative ? (r.y1, r.y0) : (r.y0, r.y1)
            let out = negative ? 1.0 : -1.0
            let target = ChartPoint(r.center.x, endY)
            let wide = ChartRect(r.center.x - tw / 2 - size * 2, 0, r.center.x + tw / 2 + size * 2, 0)
            switch pos {
            case .center?: dataLabel(s, si, i, text, r, .center, .middle, size, col, nil, col)
            case .insideEnd?:
                dataLabel(s, si, i, text, ChartRect(wide.x0, endY, wide.x1, endY - out * (th + 2)).abs, .center, negative ? .bottom : .top, size, col, nil, col)
            case .insideBase?:
                dataLabel(s, si, i, text, ChartRect(wide.x0, baseY, wide.x1, baseY + out * (th + 2)).abs, .center, negative ? .top : .bottom, size, col, nil, col)
            case .outsideEnd?:
                dataLabel(s, si, i, text, ChartRect(wide.x0, endY + out * (2 + lift), wide.x1, endY + out * (th + 2 + lift)).abs, .center, negative ? .top : .bottom, size, col, target, col)
            default: dataLabel(s, si, i, text, ChartRect(r.x0 - 10, r.y0 - base * 1.4, r.x1 + 10, r.y0), .center, .bottom, size, col, nil, col)
            }
        }
    }

    /// A line point's data label by its position: centred on it, left, right, above or below; PowerPoint's default is
    /// to the right.
    mutating func pointLabel(_ s: ChartSeries, _ si: Int, _ i: Int, _ text: String, _ q: ChartPoint, _ gapR: Double, _ size: Double, _ col: ChartColor) {
        let o = c.labelOptions(s)
        let (tw, th) = Self.labelExtent(text, size)
        let g = gapR + size * 0.3 + (o.callout ? size * 0.6 : 0)
        let w = tw + size * 2
        switch o.position(for: c.seriesKind(s), threeD: c.threeD) ?? (o.callout ? .above : .right) {
        case .center: dataLabel(s, si, i, text, ChartRect(q.x - w, q.y - th, q.x + w, q.y + th), .center, .middle, size, col, nil, col)
        case .left: dataLabel(s, si, i, text, ChartRect(q.x - g - w, q.y - th, q.x - g, q.y + th), .right, .middle, size, col, q, col)
        case .above: dataLabel(s, si, i, text, ChartRect(q.x - w, q.y - g - th, q.x + w, q.y - g), .center, .bottom, size, col, q, col)
        case .below: dataLabel(s, si, i, text, ChartRect(q.x - w, q.y + g, q.x + w, q.y + g + th), .center, .top, size, col, q, col)
        default: dataLabel(s, si, i, text, ChartRect(q.x + g, q.y - th, q.x + g + w, q.y + th), .left, .middle, size, col, q, col)
        }
    }
}


/// A bubble chart's sizing (ECMA-376 §21.2.2.22 `c:bubbleScale`, §21.2.2.200 `c:sizeRepresents`): the largest size over
/// the chart's series gets a bubble a quarter as wide as the plot's shorter side at 100 %, as PowerPoint draws it;
/// others scale by area (or by width). Zero, negative and missing sizes draw nothing; a series with no sizes at all
/// draws every bubble at the largest size. From DeckCraftNative's DCRender/Chart.swift (its own addition there).
struct BubbleScale {
    let maxSize: Double
    let maxRadius: Double
    let byWidth: Bool

    init(_ c: ChartSpec, _ plot: ChartRect) {
        var top = 0.0
        if c.kind == .bubble {
            for s in c.series {
                if s.sizes.isEmpty { top = top.rustMax(1) }
                for v in s.sizes.compactMap({ $0 }) where v.isFinite && v > 0 { top = top.rustMax(v) }
            }
        }
        maxSize = top
        let scale = (c.bubbleScale.flatMap { $0.isFinite ? $0 : nil } ?? 100).clamped(0, 300) / 100
        maxRadius = top > 0 ? plot.width.rustMin(plot.height).rustMax(0) * 0.125 * scale : 0
        byWidth = c.bubbleSizeWidth
    }

    /// Point `i`'s radius, or nil when it draws no bubble.
    func radius(_ s: ChartSeries, _ i: Int) -> Double? {
        let v: Double? = s.sizes.isEmpty ? 1 : (s.sizes.at(i) ?? nil)
        guard let v, v.isFinite, v > 0, maxSize > 0, maxRadius > 0 else { return nil }
        let f = (v / maxSize).rustMin(1)
        return maxRadius * (byWidth ? f : f.squareRoot())
    }

    /// The x axis' room for the largest bubble: its radius as a fraction of `width`.
    func padding(_ width: Double) -> Double { width > 0 && maxRadius > 0 ? maxRadius / width : 0 }
}

extension ChartSpec {
    /// A data table goes under a flat chart with a category axis along the bottom: column, line and area charts and
    /// their combos, as PowerPoint offers it (not on a pie, doughnut, scatter, bubble, horizontal bar or 3-D chart).
    public var takesDataTable: Bool {
        guard !threeD, !series.isEmpty else { return false }
        return series.allSatisfy { s in
            [.column, .stackedColumn, .percentColumn, .line, .lineMarkers, .stackedLine, .percentLine, .area, .stackedArea, .percentArea, .stock]
                .contains(seriesKind(s))
        }
    }
}

/// A data table under the plot, as PowerPoint draws `c:dTable`: a header row of category names under the plot's
/// bands, then a row per series with its key and name left of the plot and its values under their categories, in grey
/// lines (the outline, and the rows' and columns' borders when the table shows them).
struct DataTableLayout {
    let table: ChartDataTableStyle
    let rowHeight: Double
    let rows: Int
    let nameWidth: Double
    let base: Double

    init(_ c: ChartSpec, _ t: ChartDataTableStyle, _ base: Double) {
        table = t
        self.base = base
        rowHeight = base * 1.45
        rows = 1 + Swift.min(c.series.count, 64)
        let widest = Double(c.series.prefix(64).map { $0.name.unicodeScalars.count }.max() ?? 0)
        nameWidth = widest * base * 0.55 + base * (t.keys ? 2.2 : 0.8)
    }

    var height: Double { rowHeight * Double(rows) + base * 0.3 }

    func draw(_ l: inout Layout, _ plot: ChartRect, _ band: Double, _ slot: (Int) -> Double, _ ncat: Int, _ gutter: Double, _ textCol: ChartColor) {
        let c = l.c
        let top = plot.y1
        let left = plot.x0 - nameWidth.rustMin(gutter)
        func y(_ r: Int) -> Double { top + rowHeight * Double(r) }
        let bottom = y(rows)
        let size = base * 0.85
        // The header: each category's name under its band.
        for i in 0 ..< ncat {
            guard let name = c.categories.at(i) else { continue }
            let x = plot.x0 + band * slot(i)
            l.label(name, ChartRect(x, y(0), x + band, y(1)), size, .center, .middle, textCol, false)
        }
        for (si, s) in c.series.prefix(rows - 1).enumerated() {
            let r = si + 1
            var nameX = left + base * 0.3
            if table.keys {
                // Bars and areas a filled key, lines a short line, as PowerPoint draws them.
                let k = c.seriesKind(s)
                let key = base * 0.55
                let ky = (y(r) + y(r + 1) - key) / 2
                if k.isBarLike || k.isArea {
                    let paint: BarPaint = k.isBarLike ? l.paintOf(s.fill, l.seriesColor(si)) : .color(l.seriesFill(si, s))
                    l.fillWith(paint, ChartRect(nameX, ky, nameX + key, ky + key))
                    nameX += key + base * 0.35
                } else {
                    // `BarPaint.line` runs from 0.4 of the key's width before it to its end.
                    let w = base * 1.1 / 1.4
                    l.fillWith(.line(l.seriesLine(si, s), []), ChartRect(nameX + w * 0.4, ky, nameX + w * 1.4, ky + key))
                    nameX += base * 1.1 + base * 0.35
                }
            }
            l.label(s.name, ChartRect(nameX, y(r), plot.x0 - base * 0.2, y(r + 1)), size, .left, .middle, textCol, false)
            for i in 0 ..< ncat {
                guard let v = s.values.at(i) ?? nil else { continue }
                let x = plot.x0 + band * slot(i)
                l.label(c.dataLabel(s, v), ChartRect(x, y(r), x + band, y(r + 1)), size, .center, .middle, textCol, false)
            }
        }
        var lines = ChartPath()
        if table.horizontal {
            for r in 1 ..< rows {
                lines.move(to: ChartPoint(left, y(r)))
                lines.line(to: ChartPoint(plot.x1, y(r)))
            }
        }
        if table.vertical {
            // Between the categories (from the plot's bottom), and the name column's edge (from the series rows).
            for i in 1 ..< Swift.max(ncat, 1) {
                let x = plot.x0 + band * Double(i)
                lines.move(to: ChartPoint(x, top))
                lines.line(to: ChartPoint(x, bottom))
            }
            lines.move(to: ChartPoint(plot.x0, top))
            lines.line(to: ChartPoint(plot.x0, bottom))
        }
        if table.outline {
            lines.move(to: ChartPoint(plot.x0, top))
            lines.line(to: ChartPoint(plot.x1, top))
            lines.line(to: ChartPoint(plot.x1, bottom))
            lines.line(to: ChartPoint(left, bottom))
            lines.line(to: ChartPoint(left, y(1)))
            lines.line(to: ChartPoint(plot.x0, y(1)))
            lines.line(to: ChartPoint(plot.x0, top))
        }
        l.stroke(lines, ChartStroke(.rgb(0xD9, 0xD9, 0xD9), width: 0.75))
    }
}
