// ChartLab — the lab's state: the chart being tried, its theme and size, its build and the moment shown.
import CoreGraphics
import Foundation
import MarqueeCharts
import MarqueeChartsGraphics
import Observation

/// A canvas size to lay the chart out at.
enum CanvasSize: String, CaseIterable, Identifiable {
    case wide = "16:9", standard = "4:3", square = "1:1", portrait = "2:3", tallPortrait = "9:16"

    var id: String { rawValue }

    /// Points.
    var size: (Double, Double) {
        switch self {
        case .wide: (960, 540)
        case .standard: (800, 600)
        case .square: (640, 640)
        case .portrait: (540, 810)
        case .tallPortrait: (540, 960)
        }
    }
}

enum LabTheme: String, CaseIterable, Identifiable {
    case light = "Light", dark = "Dark"

    var id: String { rawValue }
    var theme: ChartTheme { self == .light ? .standard : .dark }
    var background: ChartColor { self == .light ? .white : .rgb(0x1E, 0x1E, 0x1E) }
}

@MainActor @Observable
final class LabModel {
    var spec = ChartSpec.sample(.column) { didSet { redraw() } }
    var themeChoice = LabTheme.light { didSet { redraw() } }
    var canvas = CanvasSize.wide { didSet { redraw() } }
    var build = ChartBuild() { didSet { redraw() } }
    /// Seconds into the build; nil: the finished chart.
    var time: Double? { didSet { redraw() } }
    var playing = false
    /// Draw each part's box over the chart.
    var showParts = false { didSet { redraw() } }

    private(set) var image: CGImage?
    private(set) var drawing = ChartDrawing(width: 0, height: 0)
    private var timer: Timer?

    init() { redraw() }

    var length: Double { build.length(spec) }
    var steps: [ChartBuildStep] { build.steps(spec) }

    var currentStep: Int? { time.flatMap { build.step(at: $0, spec) } }

    func redraw() {
        let (w, h) = canvas.size
        let d = ChartLayout.draw(spec, theme: themeChoice.theme, width: w, height: h)
        drawing = d
        let states = time.map { build.states(spec, parts: d.parts, at: $0) }
        image = ChartRenderer.image(d, theme: themeChoice.theme, scale: 2, background: themeChoice.background, states: states)
        if showParts, let img = image { image = overlayParts(img, d) }
    }

    /// The image with every part's box outlined.
    private func overlayParts(_ img: CGImage, _ d: ChartDrawing) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return img }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let k = Double(img.width) / Swift.max(d.width, 1)
        ctx.setLineWidth(1)
        for p in d.parts where p != .background {
            guard let b = d.bounds(of: p) else { continue }
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 0.8))
            ctx.stroke(CGRect(x: b.x0 * k, y: Double(img.height) - b.y1 * k, width: b.width * k, height: b.height * k))
        }
        return ctx.makeImage()
    }

    // MARK: Playing the build

    func play() {
        if (time ?? length) >= length { time = 0 }
        playing = true
        timer?.invalidate()
        let start = Date().addingTimeInterval(-(time ?? 0))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Date().timeIntervalSince(start)
                if t >= self.length {
                    self.time = self.length
                    self.stop()
                } else {
                    self.time = t
                }
            }
        }
    }

    func stop() {
        playing = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: Data

    func setKind(_ k: ChartKind) {
        var s = spec
        s.kind = k
        // A pie shows one series.
        if k.isPie && s.series.count > 1 { s.varyColors = true }
        spec = s
    }

    func addCategory() {
        var s = spec
        s.categories.append("Q\(s.categories.count + 1)")
        for i in s.series.indices { s.series[i].values.append(Double(Int.random(in: 10 ... 50)) / 10) }
        spec = s
    }

    func removeCategory() {
        guard spec.categories.count > 1 else { return }
        var s = spec
        s.categories.removeLast()
        for i in s.series.indices where s.series[i].values.count > s.categories.count { s.series[i].values.removeLast() }
        spec = s
    }

    func addSeries() {
        var s = spec
        s.series.append(ChartSeries(name: "Series \(s.series.count + 1)", values: s.categories.map { _ in Double(Int.random(in: 10 ... 50)) / 10 }))
        spec = s
    }

    func removeSeries() {
        guard spec.series.count > 1 else { return }
        spec.series.removeLast()
    }

    func value(_ s: Int, _ i: Int) -> String {
        guard let v = spec.series.at(s)?.values.at(i) ?? nil else { return "" }
        return NumberFormat.format("General", v, nil)
    }

    func setValue(_ s: Int, _ i: Int, _ text: String) {
        guard spec.series.indices.contains(s) else { return }
        var sp = spec
        while sp.series[s].values.count <= i { sp.series[s].values.append(nil) }
        let t = text.trimmingCharacters(in: .whitespaces)
        sp.series[s].values[i] = t.isEmpty ? nil : Double(t.replacingOccurrences(of: ",", with: "."))
        spec = sp
    }

    // MARK: Files

    func specJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(spec)
    }

    func load(_ data: Data) throws {
        spec = try JSONDecoder().decode(ChartSpec.self, from: data)
        time = nil
    }

    /// The current frame as PNG.
    func framePNG() -> Data? { image.flatMap(ChartRenderer.png) }

    /// Every frame of the build at `fps`, as PNGs.
    func buildFrames(fps: Double = 30) -> [Data] {
        let (w, h) = canvas.size
        let d = ChartLayout.draw(spec, theme: themeChoice.theme, width: w, height: h)
        let n = Int((length * fps).rounded(.up))
        return (0 ... n).compactMap { k in
            let states = build.states(spec, parts: d.parts, at: Double(k) / fps)
            return ChartRenderer.image(d, theme: themeChoice.theme, scale: 2, background: themeChoice.background, states: states).flatMap(ChartRenderer.png)
        }
    }

    /// Each part alone on a transparent canvas, as PNGs by part name.
    func partImages() -> [(String, Data)] {
        drawing.parts.compactMap { p in
            let one = ChartDrawing(width: drawing.width, height: drawing.height, marks: drawing.marks(of: [p]))
            return ChartRenderer.image(one, theme: themeChoice.theme, scale: 2, background: nil).flatMap(ChartRenderer.png).map { (p.name, $0) }
        }
    }
}

extension Array {
    func at(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
