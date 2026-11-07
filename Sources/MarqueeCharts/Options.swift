// MarqueeCharts — the options that go with a chart's series and axes: a combo chart's series types and secondary axis,
// trendlines, error bars, a logarithmic value axis, up/down bars and a data table. Their meaning is DrawingML's
// (ECMA-376 Part 1 §21.2); the drawing follows DeckCraftNative's DCRender/Chart.swift (MIT OR Apache-2.0).
import Foundation

/// A trendline (`c:trendline`): a least-squares fit drawn over its series as a dashed line, with its equation and R²
/// when asked.
public struct ChartTrendline: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case linear, exp, log, poly, power, movingAvg

        public var label: String {
            switch self {
            case .linear: "Linear"
            case .exp: "Exponential"
            case .log: "Logarithmic"
            case .poly: "Polynomial"
            case .power: "Power"
            case .movingAvg: "Moving Average"
            }
        }
    }

    public var kind: Kind
    /// Its own name in the legend; nil: PowerPoint's ("Linear (Series 1)").
    public var name: String?
    /// A polynomial's order (2–6).
    public var order: Int?
    /// A moving average's period (2–255).
    public var period: Int?
    /// The forecast forward and backward, in categories (or x units on a scatter chart).
    public var forward: Double?
    public var backward: Double?
    /// The fit's value at x = 0, fixed.
    public var intercept: Double?
    public var showEquation: Bool
    public var showRSquared: Bool

    public init(
        kind: Kind = .linear, name: String? = nil, order: Int? = nil, period: Int? = nil, forward: Double? = nil, backward: Double? = nil,
        intercept: Double? = nil, showEquation: Bool = false, showRSquared: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.order = order
        self.period = period
        self.forward = forward
        self.backward = backward
        self.intercept = intercept
        self.showEquation = showEquation
        self.showRSquared = showRSquared
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .linear, name: try c.decodeIfPresent(String.self, forKey: .name),
            order: try c.decodeIfPresent(Int.self, forKey: .order), period: try c.decodeIfPresent(Int.self, forKey: .period),
            forward: try c.decodeIfPresent(Double.self, forKey: .forward), backward: try c.decodeIfPresent(Double.self, forKey: .backward),
            intercept: try c.decodeIfPresent(Double.self, forKey: .intercept),
            showEquation: try c.decodeIfPresent(Bool.self, forKey: .showEquation) ?? false,
            showRSquared: try c.decodeIfPresent(Bool.self, forKey: .showRSquared) ?? false
        )
    }

    var dispEq: Bool { showEquation }
    var dispRSqr: Bool { showRSquared }

    /// Its name in the legend: its own, else PowerPoint's ("Linear (North)").
    public func legendName(series: String) -> String {
        if let n = name, !n.isEmpty { return n }
        let k: String = switch kind {
        case .linear: "Linear"
        case .exp: "Expon."
        case .log: "Log."
        case .poly: "Poly."
        case .power: "Power"
        case .movingAvg: "\(period ?? 2) per. Mov. Avg."
        }
        return "\(k) (\(series))"
    }
}

/// Error bars on a series' values (`c:errBars`).
public struct ChartErrorBars: Hashable, Sendable, Codable {
    /// Which way they run from the value.
    public enum Direction: String, Hashable, Sendable, Codable, CaseIterable { case both, plus, minus }
    /// What their length measures.
    public enum Amount: String, Hashable, Sendable, Codable, CaseIterable {
        case fixed = "fixedVal", percentage, standardDeviation = "stdDev", standardError = "stdErr", custom = "cust"
    }

    public var direction: Direction
    public var amount: Amount
    /// The fixed value, the percentage, or how many standard deviations.
    public var value: Double
    /// A custom amount per point, above and below.
    public var plus: [Double?]
    public var minus: [Double?]
    /// Short crossbars at the ends.
    public var endCap: Bool

    public init(direction: Direction = .both, amount: Amount = .fixed, value: Double = 1, plus: [Double?] = [], minus: [Double?] = [], endCap: Bool = true) {
        self.direction = direction
        self.amount = amount
        self.value = value
        self.plus = plus
        self.minus = minus
        self.endCap = endCap
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            direction: try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .both, amount: try c.decodeIfPresent(Amount.self, forKey: .amount) ?? .fixed,
            value: try c.decodeIfPresent(Double.self, forKey: .value) ?? 1, plus: try c.decodeIfPresent([Double?].self, forKey: .plus) ?? [],
            minus: try c.decodeIfPresent([Double?].self, forKey: .minus) ?? [], endCap: try c.decodeIfPresent(Bool.self, forKey: .endCap) ?? true
        )
    }

    /// The bar's ends around value `v` of point `i`, or nil when they aren't finite.
    func range(_ stats: SeriesStats, _ i: Int, _ v: Double) -> (Double, Double)? {
        let (n, mean, sd) = (stats.n, stats.mean, stats.sd)
        let centre: Double
        let minus: Double
        let plus: Double
        switch amount {
        case .percentage: (centre, minus, plus) = (v, Swift.abs(v * value / 100.0), Swift.abs(v * value / 100.0))
        case .standardDeviation: (centre, minus, plus) = (mean, sd * value, sd * value)
        case .standardError: (centre, minus, plus) = (v, sd / n.rustMax(1.0).squareRoot(), sd / n.rustMax(1.0).squareRoot())
        case .custom: (centre, minus, plus) = (v, (self.minus.at(i) ?? nil) ?? 0.0, (self.plus.at(i) ?? nil) ?? 0.0)
        case .fixed: (centre, minus, plus) = (v, value, value)
        }
        let (lo, hi): (Double, Double) = switch direction {
        case .plus: (centre, centre + plus)
        case .minus: (centre - minus, centre)
        case .both: (centre - minus, centre + plus)
        }
        return lo.isFinite && hi.isFinite ? (lo, hi) : nil
    }
}

/// Count, mean and sample standard deviation of a series' finite values (error bars use them).
struct SeriesStats: Equatable {
    var n = 0.0
    var mean = 0.0
    var sd = 0.0

    static func of(_ values: [Double?]) -> SeriesStats {
        let vals = values.compactMap { $0 }.filter(\.isFinite)
        let n = Double(vals.count)
        let mean = rsSum(vals) / n.rustMax(1.0)
        let sd = n > 1.0 ? (rsSum(vals.map { ($0 - mean) * ($0 - mean) }) / (n - 1.0)).squareRoot() : 0.0
        return SeriesStats(n: n, mean: mean, sd: sd)
    }
}

/// A data table under the plot (`c:dTable`): which lines it draws, and whether its rows carry legend keys.
public struct ChartDataTableStyle: Hashable, Sendable, Codable {
    public var horizontal: Bool
    public var vertical: Bool
    public var outline: Bool
    public var keys: Bool

    public init(horizontal: Bool = true, vertical: Bool = true, outline: Bool = true, keys: Bool = true) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.outline = outline
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            horizontal: try c.decodeIfPresent(Bool.self, forKey: .horizontal) ?? true, vertical: try c.decodeIfPresent(Bool.self, forKey: .vertical) ?? true,
            outline: try c.decodeIfPresent(Bool.self, forKey: .outline) ?? true, keys: try c.decodeIfPresent(Bool.self, forKey: .keys) ?? true
        )
    }
}
