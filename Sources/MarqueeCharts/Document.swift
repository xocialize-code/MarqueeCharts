// MarqueeCharts — a chart document (`.marqueechart`): a chart as a file, everything needed to draw it again (its spec, the
// theme it was drawn in, and the size it was laid out at). A show that plays a chart from its baked renders keeps the
// document beside them, so the chart stays editable and can be drawn again when its data changes.
import Foundation

public struct ChartDocument: Hashable, Sendable, Codable {
    /// `marquee-chart`.
    public var format: String
    /// The document's version: 1. A reader refuses a later major version.
    public var version: Int
    /// The size the chart is laid out at, in points.
    public var width: Double
    public var height: Double
    public var theme: ChartTheme
    public var chart: ChartSpec

    public static let formatName = "marquee-chart"
    public static let currentVersion = 1
    /// The file's extension, and its media type.
    public static let fileExtension = "marqueechart"
    public static let contentType = "application/vnd.marquee.chart+json"

    public init(chart: ChartSpec, theme: ChartTheme, width: Double, height: Double) {
        format = Self.formatName
        version = Self.currentVersion
        self.width = width
        self.height = height
        self.theme = theme
        self.chart = chart
    }

    public enum ReadError: Error, Equatable, CustomStringConvertible {
        case notAChart
        case newerVersion(Int)

        public var description: String {
            switch self {
            case .notAChart: "not a Marquee chart document"
            case .newerVersion(let v): "a chart document of version \(v), newer than this reader's \(ChartDocument.currentVersion)"
            }
        }
    }

    /// A document from its JSON. Fields a reader doesn't know are ignored; a missing field takes its default.
    public static func read(_ data: Data) throws -> ChartDocument {
        let d = try JSONDecoder().decode(ChartDocument.self, from: data)
        guard d.format == formatName else { throw ReadError.notAChart }
        guard d.version <= currentVersion else { throw ReadError.newerVersion(d.version) }
        return d
    }

    /// The document as JSON: keys sorted, so the same chart is the same bytes (assets are named by their content).
    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    /// The chart laid out at the document's size.
    public func drawing() -> ChartDrawing { ChartLayout.draw(chart, theme: theme, width: width, height: height) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 960
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 540
        theme = try c.decodeIfPresent(ChartTheme.self, forKey: .theme) ?? .standard
        chart = try c.decode(ChartSpec.self, forKey: .chart)
    }
}
