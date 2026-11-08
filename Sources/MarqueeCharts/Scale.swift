// MarqueeCharts — the value axis' scale: Office's automatic bounds and major unit over the plotted values (stacked
// series as running sums, 100 % series as 0–1), or the ones a chart fixes. From DeckCraftNative's DCModel/Chart.swift,
// a port of deckcraft crates/model/src/chart.rs (MIT OR Apache-2.0, © ArtCraft Team and the DeckCraft contributors).
import Foundation

extension ChartSpec {
    /// A series' own type: its own in a combo chart (columns when it names none), else the chart's.
    public func seriesKind(_ s: ChartSeries) -> ChartKind {
        if kind == .combo {
            if let k = s.kind, k != .combo { return k }
            return .column
        }
        return kind
    }

    /// Whether series `s` is plotted against the secondary value axis (combo charts only).
    public func onSecondary(_ s: ChartSeries) -> Bool { kind == .combo && s.secondaryAxis }

    /// The smallest and largest value plotted against one value axis: plain values as they are, stacked series as
    /// running sums from zero, 100 % series as 0–1, and the trendlines of series that aren't stacked. (0, 0) without
    /// finite values; nil when no series uses the axis.
    func plottedExtent(secondary: Bool = false) -> (Double, Double)? {
        if kind == .waterfall {
            if secondary { return nil }
            return waterfallBars().reduce((0.0, 0.0)) { r, b in (r.0.rustMin(b.0.rustMin(b.1)), r.1.rustMax(b.0.rustMax(b.1))) }
        }
        let ser = series.filter { onSecondary($0) == secondary }
        if ser.isEmpty { return !secondary && kind != .combo ? (0.0, 0.0) : nil }
        var ext = (Double.infinity, -Double.infinity)
        let hasStackedOrPercent = ser.contains { s in
            let k = seriesKind(s)
            return k.stacked || k.percent
        }
        var percent = false
        if hasStackedOrPercent {
            let n = ser.map(\.values.count).max() ?? 0
            let (product, overflow) = ser.count.multipliedReportingOverflow(by: n)
            let budget = Swift.min(overflow ? Int.max : product, 10_000_000)
            let nClamped = Swift.min(n, budget / ser.count)
            for i in 0 ..< nClamped {
                var p = 0.0
                var m = 0.0
                var stacked = false
                for s in ser {
                    let k = seriesKind(s)
                    guard let v = s.values.at(i) ?? nil, v.isFinite else { continue }
                    if k.percent {
                        percent = true
                    } else if k.stacked {
                        stacked = true
                        if v >= 0.0 { p += v } else { m += v }
                    } else {
                        widen(&ext, v)
                    }
                }
                if stacked {
                    ext.1 = ext.1.rustMax(p)
                    ext.0 = ext.0.rustMin(m)
                }
            }
        } else {
            for s in ser {
                for v in s.values.compactMap({ $0 }) where v.isFinite { widen(&ext, v) }
            }
        }
        if percent {
            ext.0 = ext.0.rustMin(0.0)
            ext.1 = ext.1.rustMax(1.0)
        } else {
            for s in ser where !seriesKind(s).stacked {
                for y in s.trendlineYs(seriesKind(s).isXY) { widen(&ext, y) }
            }
        }
        let (lo, hi) = ext
        return lo <= hi ? (lo, hi) : (0.0, 0.0)
    }

    /// The value axis' scale — (min, max, major unit) — with at most `maxIntervals` intervals: the bounds and unit
    /// the chart fixes, else Office's automatic ones.
    public func axisScale(_ maxIntervals: Int) -> (min: Double, max: Double, step: Double) {
        axisScale(secondary: false, maxIntervals) ?? { let s = MarqueeCharts.axisScale(0, 1, nil, nil, nil, maxIntervals, true); return (s.0, s.1, s.2) }()
    }

    /// One value axis' scale: the primary's, or a combo chart's secondary one; nil when no series uses that axis.
    public func axisScale(secondary: Bool, _ maxIntervals: Int) -> (min: Double, max: Double, step: Double)? {
        guard let (lo, hi) = plottedExtent(secondary: secondary) else { return nil }
        let a = secondary ? secondaryAxis : valueAxis
        let s = MarqueeCharts.axisScale(lo, hi, a.min, a.max, a.majorUnit, maxIntervals, secondary || !kind.percent)
        return (s.0, s.1, s.2)
    }

    /// A logarithmic value axis' scale in exponents — (min, max, unit), so its labels are `base^min`,
    /// `base^(min+unit)`… — over the positive values: whole powers, as PowerPoint draws them. nil when the axis isn't
    /// logarithmic or nothing is positive.
    public func logAxisScale(_ maxIntervals: Int) -> (min: Double, max: Double, step: Double)? {
        guard let b = valueAxis.logBase, b.isFinite, b >= 2.0 else { return nil }
        var range: (Double, Double)?
        for s in series where !onSecondary(s) {
            for v in s.values.compactMap({ $0 }) where v.isFinite && v > 0.0 {
                range = range.map { ($0.0.rustMin(v), $0.1.rustMax(v)) } ?? (v, v)
            }
        }
        guard let (lo0, hi0) = range else { return nil }
        func e(_ v: Double) -> Double { Foundation.log(v) / Foundation.log(b) }
        let lo = valueAxis.min.flatMap { $0 > 0.0 ? e($0) : nil } ?? e(lo0).rounded(.down)
        let hi = (valueAxis.max.flatMap { $0 > 0.0 ? e($0) : nil } ?? e(hi0).rounded(.up)).rustMax(lo + 1.0)
        let unit = ((hi - lo) / Double(Swift.max(maxIntervals, 1))).rounded(.up).rustMax(1.0)
        return (lo, lo + ((hi - lo) / unit).rounded(.up) * unit, unit)
    }

    /// A scatter or bubble chart's x axis (min, max, major unit): one scale over every series' x values, from zero when
    /// they are all positive; nil for other charts and when there are no x values. `pad`: room for the largest bubble,
    /// as a fraction of the axis added past the data.
    public func xAxisScale(_ maxIntervals: Int, pad: Double = 0) -> (min: Double, max: Double, step: Double)? {
        guard kind.isXY else { return nil }
        var range: (Double, Double)?
        for s in series {
            for v in s.xValues.compactMap({ $0 }) where v.isFinite {
                range = range.map { ($0.0.rustMin(v), $0.1.rustMax(v)) } ?? (v, v)
            }
        }
        guard let (lo, hi) = range else { return nil }
        let grow = pad > 0 && pad < 0.45 ? (hi - lo.rustMin(0)) * pad / (1 - 2 * pad) : 0
        let s = MarqueeCharts.axisScale(lo.rustMin(0), hi + grow, nil, nil, nil, maxIntervals, false)
        return (s.0, s.1, s.2)
    }

    /// An x axis tick's label: whole numbers as they are, others to one decimal.
    static func xAxisLabel(_ v: Double) -> String {
        Swift.abs(v - v.rounded()) < 1e-9 ? String(Int64(rustCast: v.rounded())) : rustFixed(v, places: 1)
    }

    /// A value axis label in the axis' number format and the chart's language.
    public func axisLabel(_ v: Double, secondary: Bool = false) -> String {
        let code = secondary ? secondaryAxis.format : valueAxis.format
        // A 100 % stacked chart's value axis counts in percent unless it says otherwise.
        let fmt = (code == nil || code == "General") && !secondary && kind.percent ? "0%" : code ?? "General"
        return NumberFormat.format(fmt, v, language)
    }

    /// A data label's number: the series' format, else the axis', in the chart's language.
    public func dataLabel(_ s: ChartSeries, _ v: Double) -> String {
        NumberFormat.format(s.numberFormat ?? (onSecondary(s) ? secondaryAxis.format : valueAxis.format) ?? "General", v, language)
    }

    /// The text of point `i`'s data label in series `s` with value `v`: the series name, category name, value and
    /// percentage it shows, joined by its separator (", " unset), as PowerPoint composes them. `share` is the point's
    /// share of a pie's total.
    public func labelText(_ s: ChartSeries, _ i: Int, _ v: Double, share: Double? = nil) -> String {
        let o = labelOptions(s)
        var parts: [String] = []
        if o.seriesName && !s.name.isEmpty { parts.append(s.name) }
        if o.categoryName, let cat = categories.at(i) { parts.append(cat) }
        if !o.hideValue { parts.append(dataLabel(s, v)) }
        if o.percent, let f = share, f.isFinite { parts.append(NumberFormat.format("0%", f, language)) }
        return parts.joined(separator: o.separator ?? ", ")
    }
}

private func widen(_ ext: inout (Double, Double), _ v: Double) {
    ext.0 = ext.0.rustMin(v)
    ext.1 = ext.1.rustMax(v)
}

/// The data range [lo, hi] an axis covers, clamped to ±1e100; (0, 1) without finite values.
private func axisDataRange(_ lo: Double, _ hi: Double) -> (Double, Double) {
    if lo.isFinite && hi.isFinite {
        return (lo.rustMin(hi).clamped(-1e100, 1e100), lo.rustMax(hi).clamped(-1e100, 1e100))
    }
    return (0.0, 1.0)
}

/// Office's automatic (min, max) of the data range [lo, hi]. "How chart axis limits are determined", as
/// Jon Peltier summarises it: 5 % of the data range past the data, and zero when the values don't sit
/// within the top sixth of their largest magnitude. A single value is measured from zero.
private func autoLimits(_ lo: Double, _ hi: Double, _ headroom: Bool) -> (Double, Double) {
    let flat = hi - lo <= 1e-12 * Swift.abs(lo).rustMax(Swift.abs(hi))
    let pad = !headroom ? 0.0 : (flat ? Swift.abs(hi) / 20.0 : (hi - lo) / 20.0)
    let autoLo = lo >= 0.0 && (flat || lo < hi * 5.0 / 6.0) ? 0.0 : lo - pad
    let autoHi = hi <= 0.0 && (flat || hi > lo * 5.0 / 6.0) ? 0.0 : hi + pad
    return (autoLo, autoHi)
}

/// The ends of a span too small to show: with one fixed limit on the far side of the data, the
/// automatic end gives way; otherwise the span is one `unit` wide.
private func flatSpanEnds(_ fmin: Double?, _ fmax: Double?, _ lo: Double, _ hi: Double, _ unit: Double) -> (Double, Double) {
    switch (fmin, fmax) {
    case (nil, .some):
        return (hi > 0.0 ? 0.0 : hi - Swift.abs(hi).rustMax(unit), hi)
    case (.some, nil) where lo < 0.0:
        return (lo, 0.0)
    default:
        return (lo, lo + unit)
    }
}

/// The major step: `major` when it gives at most 1000 intervals, else the smallest 1-2-5 step that fits
/// `n` intervals over [lo, hi].
private func axisStep(_ major: Double?, _ lo: Double, _ hi: Double, _ n: Double, _ unit: Double) -> Double {
    if let m = major, m > 0.0, (hi - lo) / m <= 1000.0 { return m }
    var step = pow(10.0, log10((hi - lo) / n).rounded(.down))
    // Subnormal spans underflow to a zero (or non-finite) step: fall back to the unit.
    if !(step > 0.0 && step.isFinite) { step = unit }
    var k = 0
    // 1, 2, 5, 10, 20… × the magnitude until the intervals fit.
    while ((hi / step).rounded(.up) - (lo / step).rounded(.down)) > n && k < 30 {
        step *= k % 3 == 1 ? 2.5 : 2.0
        k += 1
    }
    return step
}

/// The (min, max, major unit) of an axis over the data range [lo, hi]: `fmin`/`fmax`/`major` where the
/// chart fixes them; otherwise Office's automatic limits, rounded out to the smallest 1-2-5 unit giving
/// at most `maxIntervals` intervals:
///
/// - **Maximum:** `hi + (hi − lo)/20` (with `headroom`), rounded up to the unit.
/// - **Minimum:** zero when every value is ≥ 0 and `lo` is below 5/6 of `hi`; otherwise
///   `lo − (hi − lo)/20`, rounded down to the unit, so values bunched high get an axis that starts
///   near them.
/// - All-negative values mirror this: the axis ends at zero when `hi` is above 5/6 of `lo`. Mixed signs
///   get headroom at both ends.
public func axisScale(
    _ lo: Double, _ hi: Double, _ fmin: Double?, _ fmax: Double?, _ major: Double?, _ maxIntervals: Int, _ headroom: Bool
) -> (Double, Double, Double) {
    // Values past ±1e100 aren't axis values; clamping keeps the arithmetic finite.
    func fin(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0.clamped(-1e100, 1e100) : nil } }
    let (fmin, fmax) = (fin(fmin), fin(fmax))
    let (dlo, dhi) = axisDataRange(lo, hi)
    let (autoLo, autoHi) = autoLimits(dlo, dhi, headroom)
    var (lo, hi) = (fmin ?? autoLo, fmax ?? autoHi)
    let mag = Swift.abs(lo).rustMax(Swift.abs(hi))
    // Relative to the data's magnitude, so tiny values don't count as flat; all-zero falls back to 1.
    let unit = mag == 0.0 ? 1.0 : mag
    if hi - lo <= 1e-12 * mag {
        (lo, hi) = flatSpanEnds(fmin, fmax, lo, hi, unit)
    }
    let n = Double(Swift.min(Swift.max(maxIntervals, 1), 50))
    let step = axisStep(fin(major), lo, hi, n, unit)
    let min = fmin ?? ((lo / step + 1e-9).rounded(.down) * step)
    let max = (fmax ?? ((hi / step - 1e-9).rounded(.up) * step)).rustMax(min + step)
    return (min, max, step)
}

