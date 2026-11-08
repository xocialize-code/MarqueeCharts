// MarqueeCharts — the data behind Office 2016's charts: a waterfall's floating bars, a histogram's bins (and a Pareto's
// order and running share), box and whisker summaries, and the category hierarchy of a treemap or sunburst. From
// DeckCraftNative's DCModel/Chart.swift, a port of deckcraft crates/model/src/chart.rs and chartex.rs (MIT OR
// Apache-2.0, © ArtCraft Team and the DeckCraft contributors).
import Foundation

/// One histogram bin: its range, (lo, hi] (the first also holding its lo), and how many observations fall in it.
public struct ChartBin: Hashable, Sendable {
    public var lo: Double
    public var hi: Double
    public var count: Int
}

/// A box and whisker summary of one group: quartiles, whiskers at the furthest points within 1.5 IQR of the box, the
/// mean, and the points beyond the whiskers.
public struct BoxStats: Hashable, Sendable {
    public var low: Double
    public var q1: Double
    public var median: Double
    public var q3: Double
    public var high: Double
    public var mean: Double
    public var outliers: [Double]
}

/// A node of a treemap or sunburst hierarchy: its label, the total of the leaves under it, and its children (none for
/// a leaf, which names its category).
public struct ChartTreeNode: Hashable, Sendable {
    public var name: String
    public var value: Double
    public var leaf: Int?
    public var children: [ChartTreeNode]

    /// The first category under this node: the part a group's marks come with.
    public var firstLeaf: Int? { leaf ?? children.lazy.compactMap(\.firstLeaf).first }
}

extension ChartSpec {
    /// Bins a histogram has at most (a hostile bin size can't make millions).
    public static let maxBins = 1000
    /// Levels of hierarchy a chart may have.
    public static let maxLevels = 16

    /// A waterfall's bars as (from, to) on the value axis: each point floats from the running total; a total point
    /// stands on zero and sets it.
    public func waterfallBars() -> [(Double, Double)] {
        guard let s = series.first else { return [] }
        var run = 0.0
        return s.values.enumerated().map { i, v in
            let v = v.flatMap { $0.isFinite ? $0 : nil } ?? 0.0
            if subtotals.contains(i) {
                run = v
                return (0.0, v)
            }
            let from = run
            run += v
            return (from, run)
        }
    }

    /// The first series' finite observations.
    func observations() -> [Double] { series.first.map { $0.values.compactMap { $0 }.filter(\.isFinite) } ?? [] }

    /// The histogram's bins over the first series: by `binSize`, else `binCount`, else Scott's rule (3.49·σ·n^(-1/3)).
    /// Empty without observations.
    public func histogramBins() -> [ChartBin] {
        let v = rsStableSorted(observations(), by: rsTotalLess)
        guard let lo = v.first, let hi = v.last else { return [] }
        let span = hi - lo
        let n = Double(v.count)
        let validSize = binSize.flatMap { $0.isFinite && $0 > 0.0 ? $0 : nil }
        let validCount = binCount.flatMap { $0 > 0 ? $0 : nil }
        var width: Double
        if let w = validSize {
            width = w
        } else if let k = validCount {
            width = span / Double(k)
        } else {
            let mean = rsSum(v) / n
            let sd = (rsSum(v.map { ($0 - mean) * ($0 - mean) }) / (n - 1.0).rustMax(1.0)).squareRoot()
            width = 3.49 * sd / cbrt(n)
        }
        let fixed = validSize == nil ? validCount : nil
        let count: Int
        if span <= 0.0 || !width.isFinite || width <= 0.0 {
            count = 1
        } else if let k = fixed {
            count = Swift.min(Swift.max(k, 1), Self.maxBins)
        } else {
            count = Swift.min(Swift.max(Int(rustCast: (span / width).rounded(.up)), 1), Self.maxBins)
        }
        if count == 1 && (span <= 0.0 || !width.isFinite || width <= 0.0) {
            width = span.rustMax(1.0)
        } else {
            width = width.rustMax(span / Double(Self.maxBins))
        }
        var bins = (0 ..< count).map { i in ChartBin(lo: lo + width * Double(i), hi: lo + width * Double(i + 1), count: 0) }
        for x in v {
            // (lo, hi] bins, the first one also holding the minimum.
            let raw = Int(rustCast: ((x - lo) / width).rounded(.up))
            var i = Swift.min(Swift.max(raw - 1, 0), count - 1)
            // The division can round across an edge: settle on the bin whose stored bounds hold x.
            while i > 0 && x <= bins[i - 1].hi { i -= 1 }
            while i + 1 < count && x > bins[i].hi { i += 1 }
            if bins.indices.contains(i) { bins[i].count += 1 }
        }
        return bins
    }

    /// A histogram (or Pareto) as the chart that draws it: a column chart of the bin counts with touching columns,
    /// labelled by bin range. A Pareto sorts the bins by count and adds the cumulative percentage as a line on a 0–100 %
    /// secondary axis.
    public func histogramView() -> ChartSpec {
        var bins = histogramBins()
        let pareto = kind == .pareto
        if pareto { bins = rsStableSorted(bins) { $0.count > $1.count } }
        func fmt(_ v: Double) -> String {
            let r = (v * 100.0).rounded() / 100.0
            if Swift.abs(r - r.rounded()) < 1e-9 { return String(Int64(rustCast: r.rounded())) }
            return rsDisplay(r)
        }
        let firstLo = bins.reduce(Double.infinity) { $0.rustMin($1.lo) }
        var v = self
        v.kind = pareto ? .combo : .column
        v.categories = bins.map { b in b.lo <= firstLo ? "[\(fmt(b.lo)), \(fmt(b.hi))]" : "(\(fmt(b.lo)), \(fmt(b.hi))]" }
        v.gapWidth = 0.0
        v.subtotals = []
        var s = series.first ?? ChartSeries(name: "", values: [])
        s.values = bins.map { Double($0.count) }
        s.kind = pareto ? .column : nil
        s.numberFormat = nil
        v.series = [s]
        if pareto {
            let total = Double(Swift.max(bins.reduce(0) { $0 + $1.count }, 1))
            var run = 0.0
            v.series.append(ChartSeries(
                name: "Cumulative %",
                values: bins.map { b in
                    run += Double(b.count)
                    return run / total
                },
                kind: .line, secondaryAxis: true
            ))
            v.secondaryAxis = ValueAxis(min: 0, max: 1, majorUnit: 0.2, format: "0%")
        }
        v.varyColors = false
        return v
    }

    /// The box chart's groups (distinct category labels in order of appearance; one unnamed group without categories)
    /// and, per series, each group's summary (nil when it has no points).
    public func boxGroups() -> (groups: [String], stats: [[BoxStats?]]) {
        var groups: [String] = []
        for c in categories.prefix(10_000) where !groups.contains(c) { groups.append(c) }
        if groups.isEmpty { groups.append("") }
        let stats = series.map { s in
            groups.map { g in
                let pts = s.values.enumerated().filter { i, _ in
                    categories.at(i).map { $0 == g } ?? (g.isEmpty || categories.isEmpty)
                }.compactMap(\.element).filter(\.isFinite)
                return Self.boxStats(pts, inclusive: inclusiveQuartiles)
            }
        }
        return (groups, stats)
    }

    /// Excel's QUARTILE.EXC position `p·(n+1)` (1-based) on sorted data, clamped to the ends.
    static func quantileExc(_ v: [Double], _ p: Double) -> Double {
        let n = v.count
        let pos = (p * (Double(n) + 1.0)).clamped(1.0, Double(n))
        let i = Int(rustCast: pos.rounded(.down))
        let frac = pos - Double(i)
        let a = v.at(Swift.min(Swift.max(i - 1, 0), n - 1)) ?? 0
        let b = v.at(Swift.min(i, n - 1)) ?? 0
        return a + (b - a) * frac
    }

    /// Excel's QUARTILE.INC position `p·(n-1)` (0-based) on sorted data.
    static func quantileInc(_ v: [Double], _ p: Double) -> Double {
        let n = v.count
        let pos = (p * (Double(n) - 1.0)).clamped(0.0, Double(n - 1))
        let i = Int(rustCast: pos.rounded(.down))
        let a = v.at(Swift.min(i, n - 1)) ?? 0
        let b = v.at(Swift.min(i + 1, n - 1)) ?? 0
        return a + (b - a) * (pos - Double(i))
    }

    /// The summary of one group's points; `inclusive` picks QUARTILE.INC over QUARTILE.EXC.
    public static func boxStats(_ pts: [Double], inclusive: Bool) -> BoxStats? {
        if pts.isEmpty { return nil }
        let pts = rsStableSorted(pts, by: rsTotalLess)
        func q(_ p: Double) -> Double { inclusive ? quantileInc(pts, p) : quantileExc(pts, p) }
        let (q1, median, q3) = (q(0.25), q(0.5), q(0.75))
        let iqr = q3 - q1
        let (loFence, hiFence) = (q1 - 1.5 * iqr, q3 + 1.5 * iqr)
        let inside = pts.filter { $0 >= loFence && $0 <= hiFence }
        let low = (inside.first ?? q1).rustMin(q1)
        let high = (inside.last ?? q3).rustMax(q3)
        let mean = rsSum(pts) / Double(pts.count)
        let outliers = pts.filter { $0 < loFence || $0 > hiFence }
        return BoxStats(low: low, q1: q1, median: median, q3: q3, high: high, mean: mean, outliers: outliers)
    }

    /// A box and whisker chart as the frame the bar layout draws (value axis, gridlines, one category per group,
    /// legend by series), and the boxes to draw in it. The frame's values are each group's extremes, so the value axis
    /// covers every whisker and outlier.
    func boxView() -> (ChartSpec, [[BoxStats?]]) {
        let (groups, stats) = boxGroups()
        var v = self
        v.kind = .column
        v.categories = groups
        func ext(_ b: BoxStats, _ hi: Bool) -> Double {
            hi ? b.outliers.reduce(b.high) { $0.rustMax($1) } : b.outliers.reduce(b.low) { $0.rustMin($1) }
        }
        let lowest = stats.joined().compactMap { $0 }.map { ext($0, false) }.reduce(Double.infinity) { $0.rustMin($1) }
        for (si, st) in zip(v.series.indices, stats) {
            v.series[si].values = st.map { $0.map { ext($0, true) } }
        }
        if lowest.isFinite && lowest < 0 && v.valueAxis.min == nil {
            // The frame's values are the highs; below zero the axis must reach the lowest point too.
            let mag = pow(10, Foundation.log10(Swift.abs(lowest)).rounded(.down))
            v.valueAxis.min = (lowest / mag).rounded(.down) * mag
        }
        return (v, stats)
    }

    /// The first series as a hierarchy: top-level nodes, each holding the consecutive categories that share its label,
    /// down to the leaves. Without outer levels every category is a top-level leaf. Negative and missing values count
    /// as zero.
    public func categoryTree() -> [ChartTreeNode] {
        guard let s = series.first else { return [] }
        let n = Swift.min(Swift.max(categories.count, s.values.count), 100_000)
        let levels = Array(categoryLevels.prefix(Self.maxLevels))
        // Each leaf's path from the top level down, blanks filled from the row above.
        var last = Array(repeating: "", count: levels.count)
        let paths: [[String]] = (0 ..< n).map { i in
            var path: [String] = []
            path.reserveCapacity(levels.count + 1)
            for (d, lv) in levels.enumerated().reversed() {
                let l = lv.at(i).map { String(rustTrim($0)) } ?? ""
                if !l.isEmpty {
                    last[d] = l
                    // A new outer label starts fresh inner groups.
                    for inner in 0 ..< d { last[inner] = "" }
                }
                path.append(last[d])
            }
            path.append(categories.at(i) ?? "")
            return path
        }
        func value(_ i: Int) -> Double {
            guard let v = s.values.at(i) ?? nil, v.isFinite else { return 0.0 }
            return v.rustMax(0.0)
        }
        func build(_ rows: [(Int, ArraySlice<String>)]) -> [ChartTreeNode] {
            var out: [ChartTreeNode] = []
            var i = 0
            while i < rows.count {
                let (idx, path) = rows[i]
                guard path.count > 1, let head = path.first else {
                    out.append(ChartTreeNode(name: path.first ?? "", value: value(idx), leaf: idx, children: []))
                    i += 1
                    continue
                }
                var j = i
                while j < rows.count && rows[j].1.count > 1 && rows[j].1.first == head { j += 1 }
                let children = build(rows[i ..< j].map { ($0.0, $0.1.dropFirst()) })
                out.append(ChartTreeNode(name: head, value: rsSum(children.map(\.value)), leaf: nil, children: children))
                i = j
            }
            return out
        }
        return build(paths.enumerated().map { ($0.offset, $0.element[...]) })
    }
}

/// Rust's `f64::total_cmp` as a strict order.
func rsTotalLess(_ a: Double, _ b: Double) -> Bool { a.isTotallyOrdered(belowOrEqualTo: b) && !b.isTotallyOrdered(belowOrEqualTo: a) }

/// Rust's `format!("{}", v)` for `f64`: the shortest digits that read back, laid out without an exponent.
func rsDisplay(_ v: Double) -> String {
    if v.isNaN { return "NaN" }
    if v.isInfinite { return v < 0 ? "-inf" : "inf" }
    let negative = v.sign == .minus
    let desc = v.magnitude.description
    var mantissa = Substring(desc)
    var exponent = 0
    if let e = desc.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        mantissa = desc[..<e]
        exponent = Int(desc[desc.index(after: e)...]) ?? 0
    }
    var digits: [Character] = []
    var afterPoint = 0
    var seenPoint = false
    for c in mantissa {
        if c == "." {
            seenPoint = true
        } else if c.isASCII, c.isNumber {
            digits.append(c)
            if seenPoint { afterPoint += 1 }
        }
    }
    var k = exponent - afterPoint
    while let f = digits.first, f == "0" { digits.removeFirst() }
    while let l = digits.last, l == "0" {
        digits.removeLast()
        k += 1
    }
    var s = negative ? "-" : ""
    if digits.isEmpty { return s + "0" }
    if k >= 0 {
        s += String(digits) + String(repeating: "0", count: Swift.min(k, 400))
    } else if -k < digits.count {
        let point = digits.count + k
        s += String(digits[..<point]) + "." + String(digits[point...])
    } else {
        s += "0." + String(repeating: "0", count: Swift.min(-k - digits.count, 400)) + String(digits)
    }
    return s
}
