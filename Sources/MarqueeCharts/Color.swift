// MarqueeCharts — colours: 8-bit sRGB with straight alpha, written as `#RRGGBB` or `#RRGGBBAA`, and the DrawingML
// transforms a palette's later rounds use (shade and tint in linear light, luminance in HSL). From DeckCraftNative's
// DCColor/Color.swift, a port of deckcraft crates/color (MIT OR Apache-2.0, © ArtCraft Team and the DeckCraft
// contributors).
import Foundation

public struct ChartColor: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }

    public static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> ChartColor { ChartColor(r: r, g: g, b: b) }

    public static let white = ChartColor.rgb(255, 255, 255)
    public static let black = ChartColor.rgb(0, 0, 0)

    /// `#RRGGBB` or `#RRGGBBAA` (the `#` optional); nil for anything else.
    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
        } else {
            self.init(r: UInt8((v >> 24) & 0xFF), g: UInt8((v >> 16) & 0xFF), b: UInt8((v >> 8) & 0xFF), a: UInt8(v & 0xFF))
        }
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when it isn't opaque.
    public var hex: String {
        let rgb = String(format: "#%02X%02X%02X", r, g, b)
        return a == 255 ? rgb : rgb + String(format: "%02X", a)
    }

    static func fromF64(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> ChartColor {
        func c(_ v: Double) -> UInt8 { v.isFinite ? UInt8(rustCast: (v.clamped(0.0, 1.0) * 255.0).rounded()) : 0 }
        return ChartColor(r: c(r), g: c(g), b: c(b), a: c(a))
    }

    var hsl: (h: Double, s: Double, l: Double) {
        let r = Double(self.r) / 255.0
        let g = Double(self.g) / 255.0
        let b = Double(self.b) / 255.0
        let mx = r.rustMax(g).rustMax(b)
        let mn = r.rustMin(g).rustMin(b)
        let l = (mx + mn) / 2.0
        if Swift.abs(mx - mn) < 1e-12 { return (0.0, 0.0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
        let h: Double
        if Swift.abs(mx - r) < 1e-12 {
            h = (g - b) / d + (g < b ? 6.0 : 0.0)
        } else if Swift.abs(mx - g) < 1e-12 {
            h = (b - r) / d + 2.0
        } else {
            h = (r - g) / d + 4.0
        }
        return (h * 60.0, s, l)
    }

    static func fromHSL(_ h: Double, _ s: Double, _ l: Double, _ a: UInt8) -> ChartColor {
        let h = (h.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0) / 360.0
        let s = s.clamped(0.0, 1.0)
        let l = l.clamped(0.0, 1.0)
        if s == 0.0 { return fromF64(l, l, l, Double(a) / 255.0) }
        let q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let p = 2.0 * l - q
        func f(_ t: Double) -> Double {
            let t = t < 0.0 ? t + 1.0 : (t > 1.0 ? t - 1.0 : t)
            if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
            return p
        }
        return fromF64(f(h + 1.0 / 3.0), f(h), f(h - 1.0 / 3.0), Double(a) / 255.0)
    }

    private static func toLin(_ v: UInt8) -> Double {
        let v = Double(v) / 255.0
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func fromLin(_ v: Double) -> Double {
        let v = v.clamped(0.0, 1.0)
        return v <= 0.003_130_8 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    private func mapLinear(_ f: (Double) -> Double) -> ChartColor {
        .fromF64(Self.fromLin(f(Self.toLin(r))), Self.fromLin(f(Self.toLin(g))), Self.fromLin(f(Self.toLin(b))), Double(a) / 255.0)
    }

    /// Towards black, keeping `k` (0–1) of it in linear light (DrawingML `a:shade`).
    public func shade(_ k: Double) -> ChartColor {
        let k = k.clamped(0.0, 1.0)
        return mapLinear { $0 * k }
    }

    /// Towards white, keeping `k` (0–1) of it in linear light (DrawingML `a:tint`).
    public func tint(_ k: Double) -> ChartColor {
        let k = k.clamped(0.0, 1.0)
        return mapLinear { $0 * k + (1.0 - k) }
    }

    /// Luminance times `k` (DrawingML `a:lumMod`).
    public func lumMod(_ k: Double) -> ChartColor {
        let (h, s, l) = hsl
        return .fromHSL(h, s, l * k, a)
    }

    /// Luminance plus `k` (DrawingML `a:lumOff`).
    public func lumOff(_ k: Double) -> ChartColor {
        let (h, s, l) = hsl
        return .fromHSL(h, s, l + k, a)
    }
}

extension ChartColor: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = ChartColor(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a colour: \(s)"))
        }
        self = c
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}
