// MarqueeCharts — combo charts, the secondary axis, trendlines, error bars, logarithmic axes, up/down bars and data
// tables (Marquee Charts C6b).
import Foundation
@testable import MarqueeCharts
import Testing

@Suite struct OptionsTests {
    func draw(_ c: ChartSpec) -> ChartDrawing { ChartLayout.draw(c, theme: .standard, width: 640, height: 400) }
    func texts(_ d: ChartDrawing) -> [String] { d.marks.compactMap { if case .text(let t) = $0.kind { t.string } else { nil } } }
    func roleCount(_ d: ChartDrawing, _ f: (ChartMark.Role) -> Bool) -> Int { d.marks.filter { f($0.role) }.count }

    @Test func aComboDrawsEachSeriesInItsOwnType() {
        var c = ChartSpec.sample(.combo)
        c.series[0].kind = .column
        c.series[1].kind = .column
        c.series[2].kind = .line
        let d = draw(c)
        #expect(roleCount(d) { if case .bar = $0 { true } else { false } } == 8, "two column series of four")
        #expect(roleCount(d) { if case .segment = $0 { true } else { false } } == 3, "one line of four points")
        #expect(c.seriesKind(ChartSeries(name: "x", values: [])) == .column, "a series with no type of its own is columns")
    }

    @Test func aSecondarySeriesHasAnAxisOfItsOwn() throws {
        var c = ChartSpec.sample(.combo)
        c.series[2].kind = .line
        c.series[2].secondaryAxis = true
        c.series[2].values = [100, 400, 250, 300]
        c.secondaryAxis.format = "#,##0"
        let d = draw(c)
        // Its labels on the right count to 400 or more; the primary axis stays near the columns' values.
        #expect(texts(d).contains("400") || texts(d).contains("450") || texts(d).contains("500"))
        let p = try #require(c.axisScale(secondary: false, 8))
        #expect(p.max < 10)
        // The columns keep their height: on one axis with 400, they would shrink to nothing.
        func tallest(_ d: ChartDrawing) -> Double {
            d.marks.compactMap { m -> Double? in if case .bar = m.role, case .fill(let path, _, _) = m.kind { path.bounds?.height } else { nil } }.max() ?? 0
        }
        var one = c
        one.series[2].secondaryAxis = false
        #expect(tallest(d) > tallest(draw(one)) * 10)
    }

    @Test func aTrendlineFitsItsSeriesAndJoinsTheLegend() {
        var c = ChartSpec.sample(.line)
        c.series = [ChartSeries(name: "North", values: [1, 2, 3, 4], trendlines: [ChartTrendline(showEquation: true, showRSquared: true)])]
        c.legend = .right
        let d = draw(c)
        let t = texts(d)
        #expect(t.contains("Linear (North)"))
        #expect(t.contains { $0.contains("y = x") && $0.contains("R² = 1") }, "\(t)")
        // Dashed, and with the series' last point.
        let dashed = d.marks.filter { if case .stroke(_, let s) = $0.kind { !s.dashes.isEmpty && $0.part != .background } else { false } }
        #expect(dashed.count == 1 && dashed[0].part == .point(series: 0, category: 3))
        // A forecast makes room past the data: the last point moves left.
        var f = c
        f.series[0].trendlines[0].forward = 2
        func lastX(_ d: ChartDrawing) -> Double {
            d.marks.compactMap { m -> Double? in if case .segment = m.role, case .stroke(let p, _) = m.kind { p.bounds?.x1 } else { nil } }.max() ?? 0
        }
        #expect(lastX(draw(f)) < lastX(d) - 20)
    }

    @Test func trendlineFits() throws {
        let xs = [1.0, 2, 3, 4, 5]
        let lin = try #require(ChartTrendline(kind: .linear).fit(xs, xs.map { 2 * $0 + 1 }))
        #expect(abs((lin.y(10) ?? 0) - 21) < 1e-9)
        let ex = try #require(ChartTrendline(kind: .exp).fit(xs, xs.map { 3 * exp(0.5 * $0) }))
        #expect(abs((ex.y(2) ?? 0) - 3 * exp(1)) < 1e-6)
        let poly = try #require(ChartTrendline(kind: .poly, order: 2).fit(xs, xs.map { $0 * $0 - 1 }))
        #expect(abs((poly.y(6) ?? 0) - 35) < 1e-6)
        #expect(ChartTrendline(kind: .movingAvg, period: 2).fit(xs, xs)?.samples(0, 10).count == 4)
        #expect(ChartTrendline(kind: .linear).fit([1], [1]) == nil)
    }

    @Test func errorBarsSpanTheirAmount() throws {
        var c = ChartSpec.sample(.column)
        c.series = [ChartSeries(name: "A", values: [2, 4], errorBars: ChartErrorBars(amount: .fixed, value: 1, endCap: false))]
        c.categories = ["Q1", "Q2"]
        c.valueAxis = ValueAxis(min: 0, max: 6, majorUnit: 1)
        let d = draw(c)
        let bars = d.marks.filter { m in
            if m.part != .background, case .stroke(let p, let s) = m.kind, s.dashes.isEmpty, p.bounds.map({ $0.width < 0.01 }) == true { true } else { false }
        }
        #expect(bars.count == 2)
        // Value 4 ± 1: from 3 to 5 on a 0–6 axis, a third of the axis long.
        let b = try #require(bars.first { $0.part == .point(series: 0, category: 1) }.flatMap { if case .stroke(let p, _) = $0.kind { p.bounds } else { nil } })
        func isBar(_ m: ChartMark) -> Bool { if case .bar = m.role { true } else { false } }
        let barTop = try #require(d.marks.first { $0.part == .point(series: 0, category: 1) && isBar($0) }
            .flatMap { m -> ChartRect? in if case .fill(let p, _, _) = m.kind { p.bounds } else { nil } })
        // The bar's height is 4 units: the error bar, 2 units, is half of it.
        #expect(abs(b.height - barTop.height / 2) < 0.5, "\(b.height) vs \(barTop.height)")
        let stats = SeriesStats.of([2, 4, 6])
        #expect(ChartErrorBars(amount: .standardDeviation).range(stats, 0, 2).map { $0.0 == 2 && $0.1 == 6 } == true)
        #expect(ChartErrorBars(direction: .plus, amount: .percentage, value: 50).range(stats, 0, 4).map { $0.0 == 4 && $0.1 == 6 } == true)
    }

    @Test func aLogAxisCountsInPowers() {
        var c = ChartSpec.sample(.column)
        c.series = [ChartSeries(name: "A", values: [3, 40, 700, 9000])]
        c.valueAxis.logBase = 10
        let t = texts(draw(c))
        for label in ["1", "10", "100", "1,000", "10,000"] where !t.contains(label) {
            #expect(t.contains(label.replacingOccurrences(of: ",", with: "")), "\(label) in \(t)")
        }
    }

    @Test func upDownBarsAndADataTable() {
        var c = ChartSpec.sample(.line)
        c.upDownBars = true
        let d = draw(c)
        #expect(d.marks.filter { $0.part == .point(series: 2, category: 1) && { if case .fill = $0.kind { true } else { false } }($0) }.count >= 1)
        var t = ChartSpec.sample(.column)
        t.dataTable = ChartDataTableStyle()
        let texts = self.texts(draw(t))
        #expect(texts.contains("Series 1") && texts.contains("4.2") && texts.contains("Q3"))
        t.kind = .bar
        #expect(!self.texts(draw(t)).contains("4.2"), "a horizontal bar chart takes no data table")
    }

    @Test func optionsRoundTrip() throws {
        var c = ChartSpec.sample(.combo)
        c.series[0].trendlines = [ChartTrendline(kind: .poly, order: 4, forward: 1, showEquation: true)]
        c.series[1].errorBars = ChartErrorBars(direction: .minus, amount: .custom, plus: [1, nil], minus: [nil, 2], endCap: false)
        c.series[2].kind = .lineMarkers
        c.series[2].secondaryAxis = true
        c.secondaryAxis = ValueAxis(min: 0, max: 500, format: "0")
        c.valueAxis.logBase = 2
        c.upDownBars = true
        c.dataTable = ChartDataTableStyle(horizontal: false, keys: false)
        let back = try JSONDecoder().decode(ChartSpec.self, from: try JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func hostileOptionsDontTrap() {
        for kind in [ChartKind.combo, .line, .column, .scatter] {
            var c = ChartSpec.sample(kind)
            c.series[0].trendlines = [
                ChartTrendline(kind: .poly, order: Int.max, forward: .infinity, backward: -.nan, intercept: .nan, showEquation: true, showRSquared: true),
                ChartTrendline(kind: .movingAvg, period: Int.min), ChartTrendline(kind: .exp, intercept: -1e308), ChartTrendline(kind: .power),
            ]
            c.series[0].values = [1e308, -1e308, .nan, 0]
            c.series[1].errorBars = ChartErrorBars(amount: .custom, value: .nan, plus: [.infinity], minus: [-.infinity], endCap: true)
            c.series[1].secondaryAxis = true
            c.series[1].kind = .combo
            c.secondaryAxis = ValueAxis(min: .nan, max: -.infinity, majorUnit: 0)
            c.valueAxis.logBase = .nan
            c.upDownBars = true
            c.dataTable = ChartDataTableStyle()
            c.series += (0 ..< 200).map { ChartSeries(name: "S\($0)", values: [Double($0)]) }
            _ = draw(c)
            c.valueAxis.logBase = 1
            _ = ChartLayout.draw(c, theme: .standard, width: 0, height: 0)
        }
    }
}
