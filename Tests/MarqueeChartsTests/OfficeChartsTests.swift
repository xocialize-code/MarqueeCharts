// MarqueeCharts — Office 2016's charts (Marquee Charts C6d): waterfall, histogram, Pareto, box and whisker, funnel,
// treemap and sunburst.
import Foundation
@testable import MarqueeCharts
import Testing

@Suite struct OfficeChartsTests {
    func draw(_ c: ChartSpec) -> ChartDrawing { ChartLayout.draw(c, theme: .standard, width: 640, height: 400) }
    func texts(_ d: ChartDrawing) -> [String] { d.marks.compactMap { if case .text(let t) = $0.kind { t.string } else { nil } } }
    func fills(_ d: ChartDrawing, _ part: ChartPart) -> [(ChartRect, ChartColor)] {
        d.marks.compactMap { m in
            if m.part == part, case .fill(let p, .color(let c, _), _) = m.kind, let b = p.bounds { (b, c) } else { nil }
        }
    }

    @Test func aWaterfallFloatsFromTheRunningTotal() throws {
        let c = ChartSpec.sample(.waterfall)
        let want: [(Double, Double)] = [(0, 4.2), (4.2, 2.8), (2.8, 4.9), (0, 4.9)]
        #expect(zip(c.waterfallBars(), want).allSatisfy { abs($0.0 - $1.0) < 1e-9 && abs($0.1 - $1.1) < 1e-9 })
        let d = draw(c)
        let first = try #require(fills(d, .point(series: 0, category: 0)).first)
        let second = try #require(fills(d, .point(series: 0, category: 1)).first)
        let total = try #require(fills(d, .point(series: 0, category: 3)).first)
        #expect(abs(second.0.y0 - first.0.y0) < 1e-6, "the decrease hangs from the first bar's top")
        #expect(abs(total.0.y1 - first.0.y1) < 1e-6, "the total stands on zero")
        let t = ChartTheme.standard
        #expect(first.1 == t.accents[0] && second.1 == t.accents[1] && total.1 == t.accents[2])
        #expect(texts(d).contains("Increase") && texts(d).contains("Total"))
    }

    @Test func aHistogramCountsItsBins() {
        var c = ChartSpec.sample(.histogram)
        #expect(c.histogramBins().reduce(0) { $0 + $1.count } == 16)
        c.binCount = 4
        let bins = c.histogramBins()
        #expect(bins.count == 4 && bins.map(\.count).reduce(0, +) == 16)
        #expect(texts(draw(c)).contains("[12, 21]"))
        c.binSize = 10
        #expect(c.histogramBins().count == 4)
        var p = ChartSpec.sample(.pareto)
        p.binCount = 4
        let v = p.histogramView()
        #expect(v.series.count == 2 && v.series[1].secondaryAxis && v.series[1].values.last == 1)
        #expect(v.series[0].values == v.series[0].values.sorted { ($0 ?? 0) > ($1 ?? 0) })
        #expect(texts(draw(p)).contains("100%"))
    }

    @Test func boxStatsUseExcelsQuartiles() throws {
        let pts = (1 ... 8).map(Double.init)
        let exc = try #require(ChartSpec.boxStats(pts, inclusive: false))
        #expect(exc.q1 == 2.25 && exc.median == 4.5 && exc.q3 == 6.75 && exc.mean == 4.5)
        let inc = try #require(ChartSpec.boxStats(pts, inclusive: true))
        #expect(inc.q1 == 2.75 && inc.q3 == 6.25)
        let out = try #require(ChartSpec.boxStats(pts + [100], inclusive: false))
        #expect(out.outliers == [100] && out.high == 8)
        // Two series in two groups: four boxes.
        let d = draw(ChartSpec.sample(.boxWhisker))
        #expect(Set(d.parts.filter { $0 != .background }).count == 4)
        #expect(texts(d).contains("Group A") && texts(d).contains("Group B"))
        var withTable = ChartSpec.sample(.boxWhisker)
        withTable.dataTable = ChartDataTableStyle()
        #expect(!texts(draw(withTable)).contains("Series 1") || texts(draw(withTable)).filter { $0 == "Series 1" }.count == texts(d).filter { $0 == "Series 1" }.count,
                "a box chart takes no data table")
    }

    @Test func aFunnelIsCentredAndAsWideAsItsValues() throws {
        let c = ChartSpec.sample(.funnel)
        let d = draw(c)
        let a = try #require(fills(d, .point(series: 0, category: 0)).first?.0)
        let b = try #require(fills(d, .point(series: 0, category: 1)).first?.0)
        #expect(abs(a.center.x - b.center.x) < 1e-6)
        #expect(abs(b.width / a.width - 2.8 / 4.7) < 1e-6 || abs(b.width / a.width - 2.8 / 4.2) < 1e-6)
        // A bar grows out from the middle.
        let m = try #require(d.marks.first { $0.part == .point(series: 0, category: 0) && { if case .bar = $0.role { true } else { false } }($0) })
        guard case .fill(let gp, _, _) = m.grown(0.5, alongSeries: false)?.mark.kind, let g = gp.bounds else { return }
        #expect(abs(g.center.x - a.center.x) < 1e-6 && abs(g.width - a.width / 2) < 1e-6)
    }

    @Test func aTreemapsTilesAreSizedByValue() {
        var c = ChartSpec.sample(.treemap)
        c.categoryLevels = []
        let d = draw(c)
        let areas = (0 ..< 8).compactMap { i in fills(d, .point(series: 0, category: i)).first.map { $0.0.width * $0.0.height } }
        #expect(areas.count == 8)
        let vals = [4.2, 2.8, 3.6, 4.7, 2.6, 4.1, 1.9, 3.0]
        for i in 1 ..< 8 { #expect(abs(areas[i] / areas[0] - vals[i] / vals[0]) < 1e-6) }
        // With its quarters: their banners, and each group with its first month.
        let tree = ChartSpec.sample(.treemap)
        #expect(tree.categoryTree().map(\.name) == ["Q1", "Q2", "Q3"])
        #expect(tree.categoryTree().map(\.firstLeaf) == [0, 3, 6])
        let t = texts(draw(tree))
        #expect(t.contains("Q2") && t.contains { $0.hasPrefix("May") })
    }

    @Test func aSunburstsRingsSweepByValue() throws {
        let d = draw(ChartSpec.sample(.sunburst))
        let slices = d.marks.compactMap { m -> (Double, Double)? in
            if case .slice(_, let inner, _, _, let sweep) = m.role, case .fill = m.kind { (inner, sweep) } else { nil }
        }
        #expect(slices.count == 11, "three quarters and eight months")
        let inner = slices.filter { $0.0 == slices.map(\.0).min() }
        #expect(abs(inner.map(\.1).reduce(0, +) - 2 * .pi) < 1e-9)
    }

    @Test func buildsStepOverBinsAndGroups() {
        var p = ChartSpec.sample(.pareto)
        p.binCount = 5
        #expect(ChartBuild(kind: .bySeries).steps(p) == [.background, .series(0), .series(1)], "the bins, then the cumulative line")
        #expect(ChartBuild(kind: .byCategory, animateBackground: false).steps(p).count == 5)
        #expect(ChartBuild(kind: .byCategory, animateBackground: false).steps(ChartSpec.sample(.boxWhisker)).count == 2, "two groups")
    }

    @Test func officeRoundTripAndHostileInput() throws {
        var c = ChartSpec.sample(.treemap)
        c.subtotals = [1, 3]
        c.inclusiveQuartiles = true
        c.binCount = 7
        c.binSize = 2.5
        #expect(try JSONDecoder().decode(ChartSpec.self, from: try JSONEncoder().encode(c)) == c)
        for kind in [ChartKind.waterfall, .funnel, .treemap, .sunburst, .boxWhisker, .histogram, .pareto] {
            var h = ChartSpec.sample(kind)
            h.series[0].values += [.nan, .infinity, -1e308, 1e308]
            h.binSize = 1e-300
            h.binCount = Int.max
            h.subtotals = [-1, Int.max]
            h.categoryLevels = (0 ..< 40).map { d in (0 ..< 20).map { "L\(d)-\($0 % 3)" } }
            h.categories = (0 ..< 2000).map { "C\($0 % 7)" }
            _ = draw(h)
            _ = ChartLayout.draw(h, theme: .standard, width: 0, height: .nan)
        }
    }
}
