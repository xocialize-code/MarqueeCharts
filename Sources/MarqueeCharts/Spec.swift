// MarqueeCharts — the chart spec: what a chart is (its type, data, axes, labels, legend and fills), free of any
// document model, and written as JSON. The fields and their meaning come from DeckCraftNative's chart model
// (DCModel, from deckcraft crates/model/src/chart.rs; MIT OR Apache-2.0, © ArtCraft Team and the DeckCraft
// contributors), which follows PowerPoint's (ECMA-376 DrawingML charts).
import Foundation

/// A chart's type. The first types: columns, bars, lines and areas (clustered, stacked and 100 %), pie and doughnut.
public enum ChartKind: String, Codable, CaseIterable, Sendable {
    case column, stackedColumn, percentColumn
    case bar, stackedBar, percentBar
    case line, lineMarkers, stackedLine, percentLine
    case area, stackedArea, percentArea
    case pie, doughnut
    /// Points placed by an x value and a y value (`xValues` and `values`); with a line when a series has one.
    case scatter
    /// A scatter chart whose points are circles sized by `sizes`.
    case bubble

    public var label: String {
        switch self {
        case .column: "Clustered Column"
        case .stackedColumn: "Stacked Column"
        case .percentColumn: "100% Stacked Column"
        case .bar: "Clustered Bar"
        case .stackedBar: "Stacked Bar"
        case .percentBar: "100% Stacked Bar"
        case .line: "Line"
        case .lineMarkers: "Line with Markers"
        case .stackedLine: "Stacked Line"
        case .percentLine: "100% Stacked Line"
        case .area: "Area"
        case .stackedArea: "Stacked Area"
        case .percentArea: "100% Stacked Area"
        case .pie: "Pie"
        case .doughnut: "Doughnut"
        case .scatter: "Scatter"
        case .bubble: "Bubble"
        }
    }

    public var isBarLike: Bool { [.column, .stackedColumn, .percentColumn, .bar, .stackedBar, .percentBar].contains(self) }
    /// Bars run across, the categories down the left.
    public var horizontal: Bool { [.bar, .stackedBar, .percentBar].contains(self) }
    public var stacked: Bool {
        [.stackedColumn, .stackedBar, .stackedLine, .stackedArea, .percentColumn, .percentBar, .percentLine, .percentArea].contains(self)
    }
    public var percent: Bool { [.percentColumn, .percentBar, .percentLine, .percentArea].contains(self) }
    public var isArea: Bool { [.area, .stackedArea, .percentArea].contains(self) }
    public var isPie: Bool { self == .pie || self == .doughnut }
    /// Both axes are value axes: points go where their x values say.
    public var isXY: Bool { self == .scatter || self == .bubble }
}

/// A gradient: its stops and its shape.
public struct ChartGradient: Hashable, Sendable, Codable {
    public struct Stop: Hashable, Sendable, Codable {
        /// 0–1.
        public var position: Double
        public var color: ChartColor

        public init(_ position: Double, _ color: ChartColor) {
            self.position = position
            self.color = color
        }
    }

    public enum Shape: Hashable, Sendable, Codable {
        /// Along `angle` degrees clockwise from left → right; `scaled` turns the angle with the box's aspect.
        case linear(angle: Double, scaled: Bool)
        /// From the middle out: `circle`, `rect` or `shape`, with the fill-to box as fractions (left, top, right, bottom).
        case path(String, focus: [Double])
    }

    public var stops: [Stop]
    public var shape: Shape
    public var rotateWithShape: Bool

    public init(stops: [Stop], shape: Shape = .linear(angle: 90, scaled: false), rotateWithShape: Bool = true) {
        self.stops = stops
        self.shape = shape
        self.rotateWithShape = rotateWithShape
    }
}

/// A preset two-colour pattern (`dkDnDiag`, `pct50`, …, as DrawingML names them).
public struct ChartPattern: Hashable, Sendable, Codable {
    public var preset: String
    public var foreground: ChartColor
    public var background: ChartColor

    public init(preset: String, foreground: ChartColor, background: ChartColor) {
        self.preset = preset
        self.foreground = foreground
        self.background = background
    }
}

/// How an area is filled.
public enum ChartFill: Hashable, Sendable {
    case solid(ChartColor)
    case gradient(ChartGradient)
    case pattern(ChartPattern)
    /// Nothing: only the outline, if any, shows.
    case none
}

extension ChartFill: Codable {
    private enum Key: String, CodingKey { case solid, gradient, pattern, none }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            if s == "none" {
                self = .none
                return
            }
            if let c = ChartColor(hex: s) {
                self = .solid(c)
                return
            }
        }
        let c = try decoder.container(keyedBy: Key.self)
        if let v = try c.decodeIfPresent(ChartColor.self, forKey: .solid) {
            self = .solid(v)
        } else if let v = try c.decodeIfPresent(ChartGradient.self, forKey: .gradient) {
            self = .gradient(v)
        } else if let v = try c.decodeIfPresent(ChartPattern.self, forKey: .pattern) {
            self = .pattern(v)
        } else {
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .solid(let v):
            var c = encoder.singleValueContainer()
            try c.encode(v.hex)
        case .none:
            var c = encoder.singleValueContainer()
            try c.encode("none")
        case .gradient(let v):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(v, forKey: .gradient)
        case .pattern(let v):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(v, forKey: .pattern)
        }
    }
}

/// A series' line, or a bar's outline: its colour (nil: none given) and width in points.
public struct ChartLine: Hashable, Sendable, Codable {
    public var color: ChartColor?
    public var width: Double?

    public init(color: ChartColor? = nil, width: Double? = nil) {
        self.color = color
        self.width = width
    }
}

/// Where a data label goes (DrawingML `c:dLblPos`).
public enum LabelPosition: String, Codable, CaseIterable, Sendable {
    case center = "ctr", insideEnd = "inEnd", insideBase = "inBase", outsideEnd = "outEnd", bestFit
    case left = "l", right = "r", above = "t", below = "b"

    /// The positions a series of `kind` takes, as PowerPoint offers them: clustered bars Center, Inside End, Inside
    /// Base, Outside End; stacked bars the first three; lines Center, Left, Right, Above, Below; a pie Center, Inside
    /// End, Outside End, Best Fit. A doughnut, an area or any 3-D chart takes none.
    public static func positions(_ kind: ChartKind, threeD: Bool = false) -> [LabelPosition] {
        if threeD { return [] }
        switch kind {
        case .column, .bar: return [.center, .insideEnd, .insideBase, .outsideEnd]
        case .stackedColumn, .percentColumn, .stackedBar, .percentBar: return [.center, .insideEnd, .insideBase]
        case .line, .lineMarkers, .stackedLine, .percentLine, .scatter, .bubble: return [.center, .left, .right, .above, .below]
        case .pie: return [.center, .insideEnd, .outsideEnd, .bestFit]
        default: return []
        }
    }
}

/// What data labels show and where.
public struct LabelOptions: Hashable, Sendable, Codable {
    public var position: LabelPosition?
    public var seriesName: Bool
    public var categoryName: Bool
    /// The value is left out while the labels show something else.
    public var hideValue: Bool
    /// A pie's share of the total.
    public var percent: Bool
    /// The series' legend key beside the label.
    public var legendKey: Bool
    /// Between the contents; unset is ", ".
    public var separator: String?
    /// In a callout box pointing at its point.
    public var callout: Bool

    public init(
        position: LabelPosition? = nil, seriesName: Bool = false, categoryName: Bool = false, hideValue: Bool = false, percent: Bool = false,
        legendKey: Bool = false, separator: String? = nil, callout: Bool = false
    ) {
        self.position = position
        self.seriesName = seriesName
        self.categoryName = categoryName
        self.hideValue = hideValue
        self.percent = percent
        self.legendKey = legendKey
        self.separator = separator
        self.callout = callout
    }

    /// The position as given, when series of `kind` take it.
    public func position(for kind: ChartKind, threeD: Bool = false) -> LabelPosition? {
        position.flatMap { p in LabelPosition.positions(kind, threeD: threeD).first { $0 == p } }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            position: try c.decodeIfPresent(LabelPosition.self, forKey: .position),
            seriesName: try c.decodeIfPresent(Bool.self, forKey: .seriesName) ?? false,
            categoryName: try c.decodeIfPresent(Bool.self, forKey: .categoryName) ?? false,
            hideValue: try c.decodeIfPresent(Bool.self, forKey: .hideValue) ?? false,
            percent: try c.decodeIfPresent(Bool.self, forKey: .percent) ?? false,
            legendKey: try c.decodeIfPresent(Bool.self, forKey: .legendKey) ?? false,
            separator: try c.decodeIfPresent(String.self, forKey: .separator),
            callout: try c.decodeIfPresent(Bool.self, forKey: .callout) ?? false
        )
    }
}

/// Where the legend goes.
public enum LegendPosition: String, Codable, CaseIterable, Sendable {
    case right = "r", left = "l", top = "t", bottom = "b", topRight = "tr"

    public var label: String {
        switch self {
        case .right: "Right"
        case .left: "Left"
        case .top: "Top"
        case .bottom: "Bottom"
        case .topRight: "Top Right"
        }
    }
}

/// One series: its name, its values by category, and how it is drawn.
public struct ChartSeries: Hashable, Sendable, Codable {
    public struct PointFill: Hashable, Sendable, Codable {
        public var index: Int
        public var fill: ChartFill

        public init(index: Int, fill: ChartFill) {
            self.index = index
            self.fill = fill
        }
    }

    public var name: String
    /// One per category; nil is a gap.
    public var values: [Double?]
    public var fill: ChartFill?
    public var line: ChartLine?
    /// Fills of single points (a pie's slices, one bar).
    public var pointFills: [PointFill]
    /// Shows its data labels (nil: as the chart says).
    public var dataLabels: Bool?
    /// A line through its points as a smooth curve.
    public var smooth: Bool
    /// Its points carry markers.
    public var marker: Bool
    /// Its labels' number format (an Excel code); nil: the value axis'.
    public var numberFormat: String?
    /// Its labels' options where they differ from the chart's.
    public var labelOptions: LabelOptions?
    /// A scatter or bubble chart's x value of each point (nil: the point isn't drawn). With none at all, the points
    /// are numbered 1, 2, 3…
    public var xValues: [Double?]
    /// A bubble chart's bubble sizes (nil, zero or negative: no bubble). With none at all, every bubble is the largest.
    public var sizes: [Double?]

    public init(
        name: String, values: [Double?], fill: ChartFill? = nil, line: ChartLine? = nil, pointFills: [PointFill] = [], dataLabels: Bool? = nil,
        smooth: Bool = false, marker: Bool = false, numberFormat: String? = nil, labelOptions: LabelOptions? = nil, xValues: [Double?] = [],
        sizes: [Double?] = []
    ) {
        self.name = name
        self.values = values
        self.fill = fill
        self.line = line
        self.pointFills = pointFills
        self.dataLabels = dataLabels
        self.smooth = smooth
        self.marker = marker
        self.numberFormat = numberFormat
        self.labelOptions = labelOptions
        self.xValues = xValues
        self.sizes = sizes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            values: try c.decodeIfPresent([Double?].self, forKey: .values) ?? [],
            fill: try c.decodeIfPresent(ChartFill.self, forKey: .fill),
            line: try c.decodeIfPresent(ChartLine.self, forKey: .line),
            pointFills: try c.decodeIfPresent([PointFill].self, forKey: .pointFills) ?? [],
            dataLabels: try c.decodeIfPresent(Bool.self, forKey: .dataLabels),
            smooth: try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? false,
            marker: try c.decodeIfPresent(Bool.self, forKey: .marker) ?? false,
            numberFormat: try c.decodeIfPresent(String.self, forKey: .numberFormat),
            labelOptions: try c.decodeIfPresent(LabelOptions.self, forKey: .labelOptions),
            xValues: try c.decodeIfPresent([Double?].self, forKey: .xValues) ?? [],
            sizes: try c.decodeIfPresent([Double?].self, forKey: .sizes) ?? []
        )
    }
}

/// The value axis: fixed bounds and unit (nil: automatic), its labels' number format, and whether it is hidden.
public struct ValueAxis: Hashable, Sendable, Codable {
    public var min: Double?
    public var max: Double?
    public var majorUnit: Double?
    /// An Excel number format code (`#,##0`, `0.0%`); nil: General (a 100 % chart's axis counts in percent).
    public var format: String?
    /// No labels (the gridlines may stay).
    public var hidden: Bool

    public init(min: Double? = nil, max: Double? = nil, majorUnit: Double? = nil, format: String? = nil, hidden: Bool = false) {
        self.min = min
        self.max = max
        self.majorUnit = majorUnit
        self.format = format
        self.hidden = hidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            min: try c.decodeIfPresent(Double.self, forKey: .min), max: try c.decodeIfPresent(Double.self, forKey: .max),
            majorUnit: try c.decodeIfPresent(Double.self, forKey: .majorUnit), format: try c.decodeIfPresent(String.self, forKey: .format),
            hidden: try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        )
    }
}

/// A chart: its type, data and options.
public struct ChartSpec: Hashable, Sendable, Codable {
    public var kind: ChartKind
    public var title: String?
    public var categories: [String]
    public var series: [ChartSeries]
    /// nil: no legend.
    public var legend: LegendPosition?
    /// The legend is drawn over the plot instead of taking room from it.
    public var legendOverlay: Bool
    /// Axis labels' and legend's text size in points; nil: one that suits the chart's size.
    public var textSize: Double?
    /// The title's text size in points; nil: 1.4 × the text size.
    public var titleSize: Double?
    /// Every series shows its data labels (a series may say otherwise).
    public var dataLabels: Bool
    public var gridlines: Bool
    /// Five to a major unit, between the major ones.
    public var minorGridlines: Bool
    public var categoryAxisTitle: String?
    public var valueAxisTitle: String?
    /// Every series in shades of the first accent.
    public var monochrome: Bool
    public var plotFill: ChartFill?
    public var chartFill: ChartFill?
    /// The text's colour; nil: the theme's.
    public var textColor: ChartColor?
    /// A doughnut's hole as a fraction of its radius (0.1–0.9).
    public var holeSize: Double
    /// The gap between categories' bars, as a fraction of one bar's width (0–5).
    public var gapWidth: Double
    /// How far neighbouring bars overlap, as a fraction of one bar (−1–1).
    public var overlap: Double
    /// One colour per point when there is a single series.
    public var varyColors: Bool
    public var valueAxis: ValueAxis
    /// The categories run backwards (right to left; on a bar chart top to bottom).
    public var categoriesReversed: Bool
    /// The language numbers are written in (`en-US`, `de-DE`, `ru-RU`): digit grouping and decimal mark.
    public var language: String?
    /// The data labels' options, for every series that has none of its own.
    public var labelOptions: LabelOptions?
    /// Drawn flat, but laid out as a 3-D chart is (its data labels take no position).
    public var threeD: Bool
    /// A bubble chart's bubbles as a percentage of their default size (0–300; nil: 100).
    public var bubbleScale: Double?
    /// A bubble's size sets its width, not its area.
    public var bubbleSizeWidth: Bool

    public init(
        kind: ChartKind = .column, title: String? = nil, categories: [String] = [], series: [ChartSeries] = [], legend: LegendPosition? = .bottom,
        legendOverlay: Bool = false, textSize: Double? = nil, titleSize: Double? = nil, dataLabels: Bool = false, gridlines: Bool = true,
        minorGridlines: Bool = false, categoryAxisTitle: String? = nil, valueAxisTitle: String? = nil, monochrome: Bool = false,
        plotFill: ChartFill? = nil, chartFill: ChartFill? = nil, textColor: ChartColor? = nil, holeSize: Double = 0.5, gapWidth: Double = 2.19,
        overlap: Double = -0.27, varyColors: Bool = false, valueAxis: ValueAxis = ValueAxis(), categoriesReversed: Bool = false,
        language: String? = nil, labelOptions: LabelOptions? = nil, threeD: Bool = false, bubbleScale: Double? = nil,
        bubbleSizeWidth: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.categories = categories
        self.series = series
        self.legend = legend
        self.legendOverlay = legendOverlay
        self.textSize = textSize
        self.titleSize = titleSize
        self.dataLabels = dataLabels
        self.gridlines = gridlines
        self.minorGridlines = minorGridlines
        self.categoryAxisTitle = categoryAxisTitle
        self.valueAxisTitle = valueAxisTitle
        self.monochrome = monochrome
        self.plotFill = plotFill
        self.chartFill = chartFill
        self.textColor = textColor
        self.holeSize = holeSize
        self.gapWidth = gapWidth
        self.overlap = overlap
        self.varyColors = varyColors
        self.valueAxis = valueAxis
        self.categoriesReversed = categoriesReversed
        self.language = language
        self.labelOptions = labelOptions
        self.threeD = threeD
        self.bubbleScale = bubbleScale
        self.bubbleSizeWidth = bubbleSizeWidth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChartSpec()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) throws -> T { try c.decodeIfPresent(T.self, forKey: k) ?? def }
        self.init(
            kind: try v(.kind, d.kind), title: try c.decodeIfPresent(String.self, forKey: .title), categories: try v(.categories, []),
            series: try v(.series, []), legend: try c.decodeIfPresent(LegendPosition.self, forKey: .legend),
            legendOverlay: try v(.legendOverlay, false), textSize: try c.decodeIfPresent(Double.self, forKey: .textSize),
            titleSize: try c.decodeIfPresent(Double.self, forKey: .titleSize), dataLabels: try v(.dataLabels, false),
            gridlines: try v(.gridlines, d.gridlines), minorGridlines: try v(.minorGridlines, false),
            categoryAxisTitle: try c.decodeIfPresent(String.self, forKey: .categoryAxisTitle),
            valueAxisTitle: try c.decodeIfPresent(String.self, forKey: .valueAxisTitle), monochrome: try v(.monochrome, false),
            plotFill: try c.decodeIfPresent(ChartFill.self, forKey: .plotFill), chartFill: try c.decodeIfPresent(ChartFill.self, forKey: .chartFill),
            textColor: try c.decodeIfPresent(ChartColor.self, forKey: .textColor), holeSize: try v(.holeSize, d.holeSize),
            gapWidth: try v(.gapWidth, d.gapWidth), overlap: try v(.overlap, d.overlap), varyColors: try v(.varyColors, false),
            valueAxis: try v(.valueAxis, ValueAxis()), categoriesReversed: try v(.categoriesReversed, false),
            language: try c.decodeIfPresent(String.self, forKey: .language), labelOptions: try c.decodeIfPresent(LabelOptions.self, forKey: .labelOptions),
            threeD: try v(.threeD, false), bubbleScale: try c.decodeIfPresent(Double.self, forKey: .bubbleScale),
            bubbleSizeWidth: try v(.bubbleSizeWidth, false)
        )
    }

    /// Series `s`'s data label options: its own, else the chart's, else the value alone.
    public func labelOptions(_ s: ChartSeries) -> LabelOptions { s.labelOptions ?? labelOptions ?? LabelOptions() }

    /// Does series `s` show data labels? Its own setting wins over the chart's.
    public func showsDataLabels(_ s: ChartSeries) -> Bool { s.dataLabels ?? dataLabels }

    /// Points per series: the categories, or the longest series when it is longer.
    public var pointCount: Int { Swift.max(categories.count, series.map(\.values.count).max() ?? 0) }

    /// The data a new chart of `kind` starts with (DeckCraft's sample numbers).
    public static func sample(_ kind: ChartKind) -> ChartSpec {
        let data: [[Double]] = [[4.2, 2.6, 2.1], [2.8, 4.1, 2.4], [3.6, 1.9, 3.3], [4.7, 3.0, 5.1]]
        let n = kind.isPie ? 1 : 3
        return ChartSpec(
            kind: kind, title: "Chart Title", categories: ["Q1", "Q2", "Q3", "Q4"],
            series: (0 ..< n).map { s in
                ChartSeries(
                    name: "Series \(s + 1)", values: data.map { $0.at(s) }, xValues: kind.isXY ? (1 ... 4).map { Double($0) } : [],
                    sizes: kind == .bubble ? [3, 5, 2, 4].map { Double($0 + s) } : []
                )
            },
            varyColors: n == 1
        )
    }
}

/// What a chart is drawn in: six accent colours for its series, its text colour, a typeface, and the colour
/// separating a pie's slices.
public struct ChartTheme: Hashable, Sendable, Codable {
    public var accents: [ChartColor]
    /// Text without a colour of its own.
    public var text: ChartColor
    /// The typeface's family name; nil: the system's.
    public var fontFamily: String?
    /// Between a pie's slices and behind a callout's text.
    public var separator: ChartColor

    public init(accents: [ChartColor], text: ChartColor, fontFamily: String? = nil, separator: ChartColor = .white) {
        self.accents = accents
        self.text = text
        self.fontFamily = fontFamily
        self.separator = separator
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChartTheme.standard
        self.init(
            accents: try c.decodeIfPresent([ChartColor].self, forKey: .accents) ?? d.accents,
            text: try c.decodeIfPresent(ChartColor.self, forKey: .text) ?? d.text,
            fontFamily: try c.decodeIfPresent(String.self, forKey: .fontFamily),
            separator: try c.decodeIfPresent(ChartColor.self, forKey: .separator) ?? .white
        )
    }

    /// Office's default palette (2013 and later) and its chart text grey.
    public static let standard = ChartTheme(
        accents: ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47"].compactMap { ChartColor(hex: $0) },
        text: .rgb(0x59, 0x59, 0x59)
    )

    /// The same palette for a dark background: light text, dark separators.
    public static let dark = ChartTheme(
        accents: ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47"].compactMap { ChartColor(hex: $0) },
        text: .rgb(0xD9, 0xD9, 0xD9), separator: .rgb(0x1E, 0x1E, 0x1E)
    )

    /// The colour of series (or point) `i`: the accents, then darker and lighter rounds of them; in a monochrome chart,
    /// shades of the first accent.
    public func seriesColor(_ i: Int, monochrome: Bool = false) -> ChartColor {
        let base = (monochrome ? accents.first : accents.at(i % Swift.max(accents.count, 1))) ?? .rgb(0x44, 0x72, 0xC4)
        let round = monochrome ? i : i / 6
        switch round {
        case 0: return base
        case 1: return base.shade(0.6)
        case 2: return base.tint(0.6)
        default: return base.lumMod(1.0 - Double(round % 5) * 0.12)
        }
    }
}
