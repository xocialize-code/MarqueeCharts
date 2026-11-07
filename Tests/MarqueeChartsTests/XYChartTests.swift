// MarqueeCharts — scatter and bubble charts (Marquee Charts C6a): points placed by their x values, bubbles sized by
// area or width, scatter lines only where a series has one, and bubbles growing from their centre.
import Foundation
@testable import MarqueeCharts
import Testing

@Suite struct XYChartTests {
    func centres(_ d: ChartDrawing, role match: (ChartMark.Role) -> Bool) -> [ChartPart: ChartPoint] {
        var out: [ChartPart: ChartPoint] = [:]
        for m in d.marks where match(m.role) {
            if case .fill(let p, _, _) = m.kind, let b = p.bounds { out[m.part] = b.center }
        }
        return out
    }

    @Test func scatterPointsGoWhereTheirXValuesSay() {
        var c = ChartSpec.sample(.scatter)
        c.series = [ChartSeries(name: "A", values: [1, 2, 3, 4], xValues: [0, 10, 5, 20])]
        let d = ChartLayout.draw(c, theme: .standard, width: 600, height: 400)
        let m = centres(d) { $0 == .marker }
        let xs = (0 ..< 4).map { m[.point(series: 0, category: $0)]?.x ?? .nan }
        #expect(xs[0] < xs[2] && xs[2] < xs[1] && xs[1] < xs[3], "\(xs)")
        // x = 5 is a quarter of the way to 20 from 0.
        #expect(abs((xs[2] - xs[0]) / (xs[3] - xs[0]) - 0.25) < 1e-6)
        // The x axis' tick labels replace the category names.
        let texts = d.marks.compactMap { if case .text(let t) = $0.kind { t.string } else { nil } }
        #expect(!texts.contains("Q1") && texts.contains("20"))
        // No line without one of its own.
        #expect(!d.marks.contains { if case .segment = $0.role { true } else { false } })
        c.series[0].line = ChartLine(color: .rgb(0, 0, 0), width: 1)
        let lined = ChartLayout.draw(c, theme: .standard, width: 600, height: 400)
        #expect(lined.marks.filter { if case .segment = $0.role { true } else { false } }.count == 3)
    }

    @Test func aPointWithoutAnXValueIsLeftOut() {
        var c = ChartSpec.sample(.scatter)
        c.series = [ChartSeries(name: "A", values: [1, 2, 3], xValues: [1, nil, 3])]
        let d = ChartLayout.draw(c, theme: .standard, width: 600, height: 400)
        #expect(centres(d) { $0 == .marker }.count == 2)
        // With no x values at all, points are numbered 1, 2, 3.
        c.series[0].xValues = []
        #expect(centres(ChartLayout.draw(c, theme: .standard, width: 600, height: 400)) { $0 == .marker }.count == 3)
    }

    func radii(_ c: ChartSpec) -> [Double] {
        let d = ChartLayout.draw(c, theme: .standard, width: 600, height: 400)
        return (0 ..< c.pointCount).compactMap { i in
            d.marks.compactMap { m -> Double? in
                if m.part == .point(series: 0, category: i), case .bubble(_, let r) = m.role { r } else { nil }
            }.first
        }
    }

    @Test func bubblesAreSizedByAreaOrWidth() {
        var c = ChartSpec.sample(.bubble)
        c.series = [ChartSeries(name: "A", values: [1, 2, 3, 4], xValues: [1, 2, 3, 4], sizes: [1, 4, 0, nil])]
        let r = radii(c)
        #expect(r.count == 2, "zero and missing sizes draw no bubble")
        #expect(abs(r[1] / r[0] - 2) < 1e-9, "by area: four times the size, twice the radius")
        c.bubbleSizeWidth = true
        let w = radii(c)
        #expect(abs(w[1] / w[0] - 4) < 1e-9)
        c.bubbleScale = 50
        #expect(abs(radii(c)[1] / w[1] - 0.5) < 1e-9)
    }

    @Test func aBubbleGrowsFromItsCentre() throws {
        let c = ChartSpec.sample(.bubble)
        let d = ChartLayout.draw(c, theme: .standard, width: 600, height: 400)
        let m = try #require(d.marks.first { if case .bubble = $0.role { true } else { false } })
        guard case .bubble(let centre, let r) = m.role, case .fill(let full, _, _) = m.kind else { return }
        let half = try #require(m.grown(0.5, alongSeries: false))
        guard case .fill(let p, _, _) = half.mark.kind, let b = p.bounds, let fb = full.bounds else { return }
        #expect(abs(b.center.x - centre.x) < 1e-6 && abs(b.center.y - centre.y) < 1e-6)
        #expect(abs(b.width - fb.width / 2) < 1e-6 && abs(fb.width - 2 * r) < 0.01)
    }

    @Test func xyFieldsRoundTrip() throws {
        var c = ChartSpec.sample(.bubble)
        c.bubbleScale = 150
        c.bubbleSizeWidth = true
        let back = try JSONDecoder().decode(ChartSpec.self, from: try JSONEncoder().encode(c))
        #expect(back == c)
        #expect(back.series[0].sizes == c.series[0].sizes && !back.series[0].xValues.isEmpty)
    }

    @Test func hostileXYNumbersDontTrap() {
        for kind in [ChartKind.scatter, .bubble] {
            var c = ChartSpec.sample(kind)
            c.series[0].xValues = [.nan, .infinity, -1e308, 1e308]
            c.series[0].sizes = [.nan, -.infinity, 1e308, 0]
            c.bubbleScale = .nan
            _ = ChartLayout.draw(c, theme: .standard, width: 300, height: 200)
            c.bubbleScale = -1e9
            _ = ChartLayout.draw(c, theme: .standard, width: 0, height: 0)
        }
    }
}
