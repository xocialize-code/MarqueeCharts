// MarqueeCharts — radar and stock charts (Marquee Charts C6c).
import Foundation
@testable import MarqueeCharts
import Testing

@Suite struct RadarStockTests {
    func draw(_ c: ChartSpec) -> ChartDrawing { ChartLayout.draw(c, theme: .standard, width: 600, height: 400) }

    @Test func aRadarHasASpokePerCategoryAndAPolygonPerSeries() throws {
        var c = ChartSpec.sample(.radar)
        c.categories = ["A", "B", "C", "D", "E"]
        c.series = [ChartSeries(name: "S", values: [1, 2, 3, 4, 5], marker: true)]
        c.valueAxis = ValueAxis(min: 0, max: 5, majorUnit: 1)
        let d = draw(c)
        let poly = try #require(d.marks.first { if case .radial = $0.role { true } else { false } })
        #expect(poly.part == .point(series: 0, category: 0))
        guard case .stroke(let path, _) = poly.kind, case .radial(let centre) = poly.role else { Issue.record("not a stroked polygon"); return }
        // The fifth point (value 5, the axis' max) lies a full radius out; the first (value 1) a fifth of it.
        let pts = path.elements.compactMap { e -> ChartPoint? in
            switch e {
            case .move(let p), .line(let p): p
            default: nil
            }
        }
        #expect(pts.count == 5)
        func dist(_ p: ChartPoint) -> Double { ((p.x - centre.x) * (p.x - centre.x) + (p.y - centre.y) * (p.y - centre.y)).squareRoot() }
        #expect(abs(dist(pts[0]) * 5 - dist(pts[4])) < 1e-6)
        #expect(pts[0].x == centre.x && pts[0].y < centre.y, "the first spoke points up")
        // Markers per point, labels with the categories.
        #expect(d.marks.filter { $0.role == .marker }.count == 5)
        let texts = d.marks.compactMap { if case .text(let t) = $0.kind { t.string } else { nil } }
        #expect(texts.contains("C") && texts.contains("5"))
        // Grown halfway, the polygon is half its size about the centre.
        let half = try #require(poly.grown(0.5, alongSeries: false))
        guard case .stroke(let hp, _) = half.mark.kind, let hb = hp.bounds, let fb = path.bounds else { return }
        #expect(abs(hb.width - fb.width / 2) < 1e-6)
    }

    @Test func aFilledRadarFillsAndTwoCategoriesDrawNothing() {
        var c = ChartSpec.sample(.filledRadar)
        let d = draw(c)
        #expect(d.marks.filter { if case .radial = $0.role, case .fill = $0.kind { true } else { false } }.count == c.series.count)
        c.categories = ["A", "B"]
        c.series = c.series.map { var s = $0; s.values = Array(s.values.prefix(2)); return s }
        #expect(draw(c).parts == [.background])
    }

    @Test func stockMarksSpanHighToLowWithACloseOrABox() throws {
        let hlc = ChartSpec.sample(.stock)
        let d = draw(hlc)
        // Five categories, each a high-low line and a close dash, with the close series.
        let marks = d.marks.filter { $0.part != .background }
        #expect(Set(marks.map(\.part)) == Set((0 ..< 5).map { ChartPart.point(series: 2, category: $0) }))
        #expect(marks.filter { if case .stroke(_, let s) = $0.kind { s.width == 2.5 } else { false } }.count == 5)
        // Open, high, low, close with up/down bars: a white box where it rose, a dark one where it fell.
        var ohlc = hlc
        ohlc.series.insert(ChartSeries(name: "Open", values: [30, 40, 45, 40, 40]), at: 0)
        ohlc.upDownBars = true
        let boxes = draw(ohlc).marks.compactMap { m -> ChartColor? in
            if case .fill(_, .color(let col, _), _) = m.kind, m.part != .background { col } else { nil }
        }
        #expect(boxes.count == 5)
        #expect(boxes.filter { $0 == .white }.count == 2, "Wed and Fri rose; Mon, Tue and Thu fell")
    }

    @Test func hostileRadarAndStockDontTrap() {
        for kind in [ChartKind.radar, .filledRadar, .stock] {
            var c = ChartSpec.sample(kind)
            c.categories = (0 ..< 5000).map { "C\($0)" }
            c.series[0].values = [.nan, .infinity, -1e308, 1e308]
            c.valueAxis = ValueAxis(min: .nan, max: -.infinity, majorUnit: 0)
            c.upDownBars = true
            c.dataLabels = true
            _ = draw(c)
            _ = ChartLayout.draw(c, theme: .standard, width: 0, height: 0)
        }
    }
}
