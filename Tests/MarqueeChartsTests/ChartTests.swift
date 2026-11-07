import CoreGraphics
import Foundation
import Testing
@testable import MarqueeCharts
@testable import MarqueeChartsGraphics

@Suite struct ChartTests {
    // MARK: Spec

    @Test func specRoundTripsThroughJSON() throws {
        var c = ChartSpec.sample(.column)
        c.series[0].fill = .pattern(ChartPattern(preset: "dkDnDiag", foreground: .rgb(1, 2, 3), background: .white))
        c.series[1].fill = .gradient(ChartGradient(stops: [.init(0, .black), .init(1, .white)], shape: .linear(angle: 90, scaled: true)))
        c.series[2].fill = .solid(ChartColor(r: 10, g: 20, b: 30, a: 128))
        c.series[2].values[1] = nil
        c.labelOptions = LabelOptions(position: .insideEnd, percent: true)
        c.valueAxis = ValueAxis(min: 0, max: 10, format: "0.0")
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(ChartSpec.self, from: data) == c)
    }

    @Test func minimalJSONTakesDefaults() throws {
        let json = #"{"kind":"pie","categories":["A","B"],"series":[{"name":"S","values":[1,null]}]}"#
        let c = try JSONDecoder().decode(ChartSpec.self, from: Data(json.utf8))
        #expect(c.kind == .pie)
        #expect(c.series[0].values == [1, nil])
        #expect(c.legend == nil)
        #expect(c.gridlines)
        #expect(c.gapWidth == ChartSpec().gapWidth)
    }

    @Test func paletteRounds() {
        let t = ChartTheme.standard
        #expect(t.seriesColor(0) == ChartColor(hex: "4472C4"))
        #expect(t.seriesColor(6) == t.seriesColor(0).shade(0.6))
        #expect(t.seriesColor(13) == t.seriesColor(1).tint(0.6))
        #expect(t.seriesColor(3, monochrome: true) == t.seriesColor(0).lumMod(1 - 3 * 0.12))
    }

    // MARK: Axis

    @Test func axisScale() {
        let c = ChartSpec.sample(.column)
        let s = c.axisScale(6)
        #expect(s.min == 0)
        #expect(s.max == 6)
        #expect(s.step == 1)
        let stacked = ChartSpec.sample(.stackedColumn)
        #expect(stacked.axisScale(6) == (0, 15, 5))
        let pct = ChartSpec.sample(.percentColumn)
        #expect(pct.axisScale(6) == (0, 1, 0.2))
        #expect(pct.axisLabel(0.4) == "40%")
    }

    // MARK: Layout

    @Test func everyPointIsAPart() {
        for kind in ChartKind.allCases {
            let c = ChartSpec.sample(kind)
            let d = ChartLayout.draw(c, theme: .standard, width: 480, height: 270)
            var want: Set<ChartPart> = [.background]
            for s in c.series.indices {
                for i in 0 ..< c.pointCount where c.series[s].values.at(i) != nil {
                    // A line's first point has no segment (no marker, no label): nothing to draw.
                    if [.line, .stackedLine, .percentLine].contains(kind) && i == 0 { continue }
                    if kind.isArea && i > 0 { continue }
                    want.insert(.point(series: s, category: i))
                }
            }
            #expect(Set(d.parts) == want, "\(kind)")
            #expect(d.parts.first == .background, "\(kind)")
        }
    }

    @Test func barsStandOnTheAxisInOrder() {
        let c = ChartSpec.sample(.column)
        let d = ChartLayout.draw(c, theme: .standard, width: 480, height: 270)
        // Category 0's three bars go left to right, the tallest being series 1's 4.2.
        let boxes = (0 ..< 3).compactMap { d.bounds(of: .point(series: $0, category: 0)) }
        #expect(boxes.count == 3)
        #expect(boxes[0].x1 <= boxes[1].x0 + 1e-9)
        #expect(boxes[1].x1 <= boxes[2].x0 + 1e-9)
        #expect(boxes[0].height > boxes[1].height)
        #expect(Swift.abs(boxes[0].y1 - boxes[1].y1) < 1e-9)
    }

    @Test func dataLabelsGoWithTheirPoint() {
        var c = ChartSpec.sample(.column)
        c.dataLabels = true
        let d = ChartLayout.draw(c, theme: .standard, width: 480, height: 270)
        let texts = d.marks.compactMap { m -> (ChartPart, String)? in if case .text(let t) = m.kind { (m.part, t.string) } else { nil } }
        #expect(texts.contains { $0.0 == .point(series: 0, category: 0) && $0.1 == "4.2" })
        #expect(texts.contains { $0.0 == .point(series: 2, category: 3) && $0.1 == "5.1" })
    }

    @Test func doughnutHoleIsEmpty() throws {
        let c = ChartSpec.sample(.doughnut)
        let d = ChartLayout.draw(c, theme: .standard, width: 400, height: 400)
        let img = try #require(ChartRenderer.image(d, theme: .standard, scale: 1, background: nil))
        let px = pixels(img)
        // The middle of the ring is transparent; a slice's middle isn't.
        #expect(px(200, 228).3 == 0)
        let b = try #require(d.bounds(of: .point(series: 0, category: 0)))
        #expect(px(Int(b.center.x), Int(b.center.y)).3 == 255 || px(Int(b.x1 - 10), Int(b.y0 + 30)).3 == 255)
    }

    @Test func hostileNumbersDontTrap() {
        var c = ChartSpec.sample(.stackedBar)
        c.series[0].values = [.infinity, -.infinity, .nan, 1e308]
        c.valueAxis = ValueAxis(min: .nan, max: -.infinity, majorUnit: 0)
        c.gapWidth = .nan
        c.holeSize = .infinity
        for kind in ChartKind.allCases {
            c.kind = kind
            _ = ChartLayout.draw(c, theme: .standard, width: 300, height: 200)
            _ = ChartLayout.draw(c, theme: .standard, width: 0, height: 0)
            _ = ChartLayout.draw(c, theme: .standard, width: .nan, height: 1e9)
        }
        _ = ChartLayout.draw(ChartSpec(), theme: .standard, width: 300, height: 200)
    }

    // MARK: Builds

    @Test func buildSteps() {
        let c = ChartSpec.sample(.column)
        #expect(ChartBuild(kind: .bySeries).steps(c) == [.background, .series(0), .series(1), .series(2)])
        #expect(ChartBuild(kind: .byCategory, animateBackground: false).steps(c).count == 4)
        let el = ChartBuild(kind: .byCategoryElement).steps(c)
        #expect(el.count == 13)
        #expect(el.at(1) == .point(series: 0, category: 0))
        #expect(el.at(2) == .point(series: 1, category: 0))
        #expect(ChartBuild(kind: .asOneObject).steps(c) == [.all])
    }

    @Test func buildStates() {
        let c = ChartSpec.sample(.column)
        let parts = ChartLayout.draw(c, theme: .standard, width: 480, height: 270).parts
        let b = ChartBuild(kind: .bySeries, effect: .wipe, duration: 1)
        let mid = b.states(c, parts: parts, at: 1.5)
        #expect(mid[.background]?.isFinished == true)
        #expect(mid[.point(series: 0, category: 2)]?.reveal == 0.5)
        #expect(mid[.point(series: 1, category: 0)]?.visible == false)
        #expect(b.length(c) == 4)
        let end = b.states(c, parts: parts, at: 4)
        #expect(end.values.allSatisfy { $0.isFinished })
        let fade = ChartBuild(kind: .byCategory, effect: .fade, animateBackground: false, duration: 2)
        #expect(fade.states(c, parts: parts, at: 1)[.point(series: 2, category: 0)]?.opacity == 0.5)
        #expect(fade.states(c, parts: parts, at: 0)[.background]?.isFinished == true)
    }

    // MARK: Rendering

    /// A finished build draws exactly as the chart does.
    @Test func finishedBuildDrawsTheChart() throws {
        for kind in [ChartKind.column, .line, .pie, .stackedArea] {
            let c = ChartSpec.sample(kind)
            let d = ChartLayout.draw(c, theme: .standard, width: 320, height: 180)
            let b = ChartBuild(kind: .bySeriesElement, effect: .fade)
            let all = try #require(ChartRenderer.image(d, theme: .standard, scale: 1))
            let done = try #require(ChartRenderer.image(d, theme: .standard, scale: 1, states: b.states(c, parts: d.parts, at: b.length(c))))
            #expect(ChartRenderer.png(all) == ChartRenderer.png(done), "\(kind)")
        }
    }

    @Test func wipeRevealsFromItsSide() throws {
        let c = ChartSpec.sample(.column)
        let d = ChartLayout.draw(c, theme: .standard, width: 480, height: 270)
        let p = ChartPart.point(series: 0, category: 0)
        let b = try #require(d.bounds(of: p))
        let half = ChartPartState(reveal: 0.5, direction: .fromBottom)
        let img = try #require(ChartRenderer.image(d, theme: .standard, scale: 1, states: [p: half]))
        let px = pixels(img)
        let cx = Int(b.center.x)
        #expect(px(cx, Int(b.y1 - b.height * 0.25)) == (0x44, 0x72, 0xC4, 255))
        #expect(px(cx, Int(b.y0 + b.height * 0.25)) != (0x44, 0x72, 0xC4, 255))
    }

    /// Writes every sample type, and one build's frames, as PNGs to `MARQUEE_CHARTS_OUT` (for looking at them).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARQUEE_CHARTS_OUT"] != nil))
    func writeSamples() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MARQUEE_CHARTS_OUT"] ?? "")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for kind in ChartKind.allCases {
            var c = ChartSpec.sample(kind)
            c.dataLabels = kind.isPie || kind == .column
            let d = ChartLayout.draw(c, theme: .standard, width: 480, height: 270)
            let img = try #require(ChartRenderer.image(d, theme: .standard, scale: 2))
            try ChartRenderer.png(img)?.write(to: out.appendingPathComponent("\(kind.rawValue).png"))
        }
        let c = ChartSpec.sample(.column)
        let d = ChartLayout.draw(c, theme: .standard, width: 480, height: 270)
        let b = ChartBuild(kind: .bySeries, effect: .wipe)
        for (k, t) in stride(from: 0.0, through: b.length(c), by: 0.25).enumerated() {
            let img = try #require(ChartRenderer.image(d, theme: .standard, scale: 1, states: b.states(c, parts: d.parts, at: t)))
            try ChartRenderer.png(img)?.write(to: out.appendingPathComponent(String(format: "build-%02d.png", k)))
        }
    }
}

/// A reader of `img`'s pixels (r, g, b, a), un-premultiplied for opaque pixels.
func pixels(_ img: CGImage) -> (Int, Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let w = img.width, h = img.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    {
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return { x, y in
        guard x >= 0, y >= 0, x < w, y < h else { return (0, 0, 0, 0) }
        let o = (y * w + x) * 4
        return (data[o], data[o + 1], data[o + 2], data[o + 3])
    }
}

@Suite struct DataTableTests {
    @Test func excelClipboard() {
        let t = "\tSales\tCosts\r\nQ1\t1,234.5\t(200)\r\nQ2\t12%\t\r\n\"Q3, late\"\t$3.00\t-4\r\n"
        let rows = ChartDataTable.cells(t)
        #expect(rows.count == 4)
        #expect(rows[3][0] == "Q3, late")
        let d = ChartDataTable.data(rows)
        #expect(d.categories == ["Q1", "Q2", "Q3, late"])
        #expect(d.series.map(\.name) == ["Sales", "Costs"])
        #expect(d.series[0].values == [1234.5, 0.12, 3])
        #expect(d.series[1].values == [-200, nil, -4])
    }

    @Test func csvWithQuotesAndSemicolons() {
        #expect(ChartDataTable.cells("a,\"b \"\"x\"\"\nc\",d\n1,2,3") == [["a", "b \"x\"\nc", "d"], ["1", "2", "3"]])
        #expect(ChartDataTable.cells("a;b;c\n1,5;2;3") == [["a", "b", "c"], ["1,5", "2", "3"]])
        #expect(ChartDataTable.cells("") == [])
        #expect(ChartDataTable.cells("1\t2\n3") == [["1", "2"], ["3", ""]])
    }

    @Test func numbersByLanguage() {
        let n = { (s: String, l: String?) in ChartDataTable.number(s, language: l) }
        #expect(n("1,234.5", nil) == 1234.5)
        #expect(n("1.234,5", "de-DE") == 1234.5)
        #expect(n("1,234.5", "de-DE") == 1234.5)
        #expect(n("2,5", "de-DE") == 2.5)
        #expect(n("2.5", "de-DE") == 2.5)
        #expect(n("1.234", "de-DE") == 1234)
        #expect(n("1,234", nil) == 1234)
        #expect(n("1 234,5", "fr-FR") == 1234.5)
        #expect(n("1\u{a0}234,5 ₽", "ru-RU") == 1234.5)
        #expect(n("1.234.567", nil) == 1_234_567)
        #expect(n("−3", nil) == -3)
        #expect(n("1.5E+3", nil) == 1500)
        #expect(n("Q1", nil) == nil)
        #expect(n("Event", nil) == nil)
        #expect(n("", nil) == nil)
        #expect(n("inf", nil) == nil)
    }

    @Test func headersAndLabelsAreFound() {
        // Numbers only: generated names.
        let plain = ChartDataTable.data([["1", "2"], ["3", "4"]])
        #expect(plain.categories == ["Category 1", "Category 2"])
        #expect(plain.series.map(\.name) == ["Series 1", "Series 2"])
        #expect(plain.series[1].values == [2, 4])
        // Series in rows.
        let rows = ChartDataTable.data([["", "Q1", "Q2"], ["North", "1", "2"], ["South", "3", "4"]], seriesInRows: true)
        #expect(rows.categories == ["Q1", "Q2"])
        #expect(rows.series.map(\.name) == ["North", "South"])
        #expect(rows.series[1].values == [3, 4])
        // A round trip through the sheet.
        let c = ChartSpec.sample(.column)
        let back = c.pasting(ChartDataTable.text(ChartDataTable.rows(c)))
        #expect(back == c)
    }
}

@Suite struct ChartDocumentTests {
    @Test func roundTripAndStableBytes() throws {
        var theme = ChartTheme.dark
        theme.fontFamily = "Inter"
        let doc = ChartDocument(chart: .sample(.doughnut), theme: theme, width: 480, height: 360)
        let a = try doc.json(), b = try doc.json()
        #expect(a == b)
        #expect(try ChartDocument.read(a) == doc)
        let text = String(decoding: a, as: UTF8.self)
        #expect(text.hasPrefix(#"{"chart":"#))
        #expect(text.contains(#""format":"marquee-chart""#))
        #expect(doc.drawing().width == 480)
    }

    @Test func readersAreTolerantAndStrict() throws {
        let minimal = #"{"format":"marquee-chart","chart":{"kind":"line","series":[{"name":"A","values":[1,2]}]},"later":true}"#
        let d = try ChartDocument.read(Data(minimal.utf8))
        #expect(d.version == 1 && d.theme == .standard && d.width == 960)
        #expect(throws: ChartDocument.ReadError.notAChart) { try ChartDocument.read(Data(#"{"format":"x","chart":{}}"#.utf8)) }
        #expect(throws: ChartDocument.ReadError.newerVersion(2)) {
            try ChartDocument.read(Data(#"{"format":"marquee-chart","version":2,"chart":{}}"#.utf8))
        }
    }
}
