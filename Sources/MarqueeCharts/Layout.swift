// MarqueeCharts — laying a chart out: title, legend, axes, gridlines and their labels, then each series' marks, as
// marks tagged by part. From DeckCraftNative's DCRender/Chart.swift, a port of deckcraft crates/render/src/chart.rs
// (MIT OR Apache-2.0, © ArtCraft Team and the DeckCraft contributors), for the first chart types. Sizes are
// measured in points; text widths are estimated from character counts, as DeckCraft does, so a layout needs no fonts.
import Foundation

public enum ChartLayout {
    /// Lay `chart` out at `width` × `height` points in `theme`.
    public static func draw(_ chart: ChartSpec, theme: ChartTheme, width: Double, height: Double) -> ChartDrawing {
        var l = Layout(c: chart, theme: theme, w: width.isFinite ? Swift.max(width, 0) : 0, h: height.isFinite ? Swift.max(height, 0) : 0)
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
        if c.varyColors && c.series.count == 1 && s.fill == nil { return .color(seriesColor(pi)) }
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
        if pie {
            legendItems = c.categories.enumerated().map { ($1, .color(seriesColor($0)), nil) }
        } else {
            legendItems = c.series.enumerated().map { i, s in
                let k = c.kind
                if !k.isBarLike && !k.isArea { return (s.name, .color(seriesLine(i, s)), nil) }
                if k.isBarLike {
                    let paint: BarPaint = c.varyColors && c.series.count == 1 && s.fill == nil ? .color(seriesColor(i)) : paintOf(s.fill, seriesColor(i))
                    return (s.name, paint, barOutline(s))
                }
                return (s.name, .color(seriesFill(i, s)), nil)
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

    mutating func drawAxes(_ area0: ChartRect, _ base: Double, _ textCol: ChartColor, _ gridCol: ChartColor) {
        var area = area0
        let horiz = c.kind.horizontal
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
        let (min, max, step) = c.axisScale(maxIntervals)
        let ticks = Self.axisTicks((min, max, step))
        // Label gutters as wide as the longest value label.
        let labelW = Double(ticks.map { c.axisLabel($0).unicodeScalars.count }.max() ?? 1) * base * 0.55 + base * 0.6
        let gutter = horiz ? base * 4.5 : c.valueAxis.hidden ? base * 0.5 : Self.clampSoft(labelW, base * 1.5, area.width * 0.3)
        let plot = horiz
            ? ChartRect(area.x0 + gutter, area.y0, area.x1, area.y1 - base * 1.6)
            : ChartRect(area.x0 + gutter, area.y0, area.x1, area.y1 - base * 1.8)
        if let f = c.plotFill { fillWith(paintOf(f, .white), plot) }
        let span = Self.positiveSpan(max - min)
        // Values past the axis limits stop at the plot's edge.
        let toV = { (v: Double) -> Double in
            let v = v.rustMax(min).rustMin(max)
            return horiz ? plot.x0 + (v - min) / span * plot.width : plot.y1 - (v - min) / span * plot.height
        }
        // Minor gridlines, under the major ones: five to a major unit.
        if c.minorGridlines {
            let minor = step / 5
            let n = minor > 0 ? Swift.min(Swift.max(Int64(rustCast: ((max - min) / minor).rounded()), 1), 500) : 1
            var g = ChartPath()
            for k in 0 ... n where k % 5 != 0 {
                let pos = toV(min + Double(k) * minor)
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
        for v in ticks {
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
        let ncat = Swift.max(c.pointCount, 1)
        let band = horiz ? plot.height / Double(ncat) : plot.width / Double(ncat)
        // Where category `i`'s band starts along its axis: left to right, or bottom to top on a horizontal bar chart,
        // unless the axis is reversed.
        let backwards = horiz != c.categoriesReversed
        let slot = { (i: Int) -> Double in backwards ? Double(Swift.max(ncat - (i + 1), 0)) : Double(i) }
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
        let zero = toV(Self.clampSoft(0, min, max))
        if c.kind.isBarLike {
            drawBars(plot, band, slot, ncat, horiz, toV, base, textCol)
        } else {
            drawLines(plot, band, slot, ncat, toV, zero, base, textCol)
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
        _ plot: ChartRect, _ band: Double, _ slot: (Int) -> Double, _ ncat: Int, _ horiz: Bool, _ toV: (Double) -> Double, _ base: Double,
        _ textCol: ChartColor
    ) {
        let ns = Swift.max(c.series.count, 1)
        // Gap width and overlap are fractions of one bar's width: a category's band holds its bars (overlapping by
        // `overlap` of a bar between neighbours) plus one gap.
        let gap = c.gapWidth.clamped(0, 5)
        let stacked = c.kind.stacked
        let ov = stacked ? 1 : c.overlap.clamped(-1, 1)
        let n = Double(ns)
        let bar = band / (n - (n - 1) * ov + gap)
        let step = bar * (1 - ov)
        let group = bar + step * (n - 1)
        for i in 0 ..< ncat {
            var posAcc = 0.0
            var negAcc = 0.0
            let total = c.kind.percent
                ? c.series.reduce(0.0) { $0 + Swift.abs(($1.values.at(i) ?? nil) ?? 0) }.rustMax(1e-9)
                : 1.0
            for (si, s) in c.series.enumerated() {
                part = .point(series: si, category: i)
                let v = ((s.values.at(i) ?? nil) ?? 0) / total
                let start = band * slot(i) + (band - group) / 2 + (stacked ? 0 : step * Double(si))
                let (a, b): (Double, Double)
                if stacked {
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
                    : ChartRect(plot.x0 + start, toV(b), plot.x0 + start + bar, toV(a))).abs
                // A bar grows from the end nearer its stack's base (zero, or the bar under it).
                let baseValue = stacked ? (v >= 0 ? a : b) : 0
                role = .bar(horizontal: horiz, base: toV(baseValue))
                fillWith(barPaint(si, i, s), r)
                if let (oc, ow) = barOutline(s), ow > 0 { stroke(.rect(r), ChartStroke(oc, width: ow)) }
                role = .none
                if c.showsDataLabels(s), let v = s.values.at(i) ?? nil {
                    barLabel(s, si, i, c.labelText(s, i, v), r, horiz, v < 0, base, textCol)
                }
            }
        }
    }

    mutating func drawLines(
        _ plot: ChartRect, _ band: Double, _ slot: (Int) -> Double, _ ncat: Int, _ toV: (Double) -> Double, _ zero: Double, _ base: Double,
        _ textCol: ChartColor
    ) {
        let kind = c.kind
        var acc = [Double](repeating: 0, count: ncat)
        // A 100 % line or area plots each value as its share of the category's total.
        let totals: [Double] = kind.percent
            ? (0 ..< ncat).map { i in c.series.reduce(0.0) { $0 + Swift.abs(($1.values.at(i) ?? nil) ?? 0) }.rustMax(1e-9) }
            : []
        let markers = kind == .lineMarkers
        for (si, s) in c.series.enumerated() {
            let areaKind = kind.isArea
            let col = areaKind ? seriesFill(si, s) : seriesLine(si, s)
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
                pts.append(ChartPoint(plot.x0 + band * (slot(i) + 0.5), toV(v)))
                cats.append(i)
                floors.append(toV(floor))
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
            } else {
                // A line's segment comes with the point it runs to. Joined with round caps, the segments draw as the
                // whole line does with round joins.
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
            if markers {
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
                    let gap = markers || s.marker ? 3.5 : 0
                    pointLabel(s, si, cats[j], c.labelText(s, cats[j], v), q, gap, base * 0.9, textCol)
                }
            }
        }
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
        var pos = o.position(for: c.kind, threeD: c.threeD) ?? (o.callout ? .outsideEnd : nil)
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
        switch o.position(for: c.kind, threeD: c.threeD) ?? (o.callout ? .above : .right) {
        case .center: dataLabel(s, si, i, text, ChartRect(q.x - w, q.y - th, q.x + w, q.y + th), .center, .middle, size, col, nil, col)
        case .left: dataLabel(s, si, i, text, ChartRect(q.x - g - w, q.y - th, q.x - g, q.y + th), .right, .middle, size, col, q, col)
        case .above: dataLabel(s, si, i, text, ChartRect(q.x - w, q.y - g - th, q.x + w, q.y - g), .center, .bottom, size, col, q, col)
        case .below: dataLabel(s, si, i, text, ChartRect(q.x - w, q.y + g, q.x + w, q.y + g + th), .center, .top, size, col, q, col)
        default: dataLabel(s, si, i, text, ChartRect(q.x + g, q.y - th, q.x + g + w, q.y + th), .left, .middle, size, col, q, col)
        }
    }
}
