// MarqueeCharts — the Rust semantics the layout and number formats were written in (DeckCraft is Rust): float min,
// max and clamping that ignore NaN, saturating casts, fixed-point formatting and string trimming. Port of the parts
// of DeckCraftNative's CNCore (CraftNativeKit, MIT OR Apache-2.0) that these files use.
import Foundation

extension Double {
    /// Rust's `f64::max`: a NaN operand is ignored, and +0 is above −0.
    @inlinable
    func rustMax(_ other: Double) -> Double {
        if isNaN { return other }
        if other.isNaN { return self }
        if self == other { return sign == .minus ? other : self }
        return self > other ? self : other
    }

    /// Rust's `f64::min`: a NaN operand is ignored, and −0 is below +0.
    @inlinable
    func rustMin(_ other: Double) -> Double {
        if isNaN { return other }
        if other.isNaN { return self }
        if self == other { return sign == .minus ? self : other }
        return self < other ? self : other
    }

    /// Kept within `lo...hi` without trapping: `hi` wins when `lo > hi`.
    @inlinable
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        var x = self
        if x < lo { x = lo }
        if x > hi { x = hi }
        return x
    }
}

extension FixedWidthInteger {
    /// Rust's `value as Self`: truncates toward zero, saturates at the bounds, NaN → 0.
    @inlinable
    init(rustCast value: Double) {
        if value.isNaN {
            self = 0
        } else if value <= Double(Self.min) {
            self = Self.min
        } else if value >= Double(Self.max) {
            self = Self.max
        } else {
            self = Self(value.rounded(.towardZero))
        }
    }
}

extension Array {
    /// The element at `i`, or nil when `i` is out of range.
    @inlinable
    func at(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Rust's `format!("{:.N}", v)`.
func rustFixed(_ v: Double, places: Int) -> String {
    if v.isNaN { return "NaN" }
    if v.isInfinite { return v < 0 ? "-inf" : "inf" }
    return String(format: "%.\(Swift.max(Swift.min(places, 40), 0))f", v)
}

private func isWhitespace(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy(\.properties.isWhitespace) }

/// Rust's `str::trim`.
func rustTrim(_ s: some StringProtocol) -> Substring {
    let s = Substring(s)
    guard let start = s.firstIndex(where: { !isWhitespace($0) }), let end = s.lastIndex(where: { !isWhitespace($0) }) else { return "" }
    return s[start ... end]
}

func trimStart(_ s: String) -> String { String(s.drop(while: isWhitespace)) }

func trimEnd(_ s: String) -> String {
    var s = Substring(s)
    while let l = s.last, isWhitespace(l) { s.removeLast() }
    return String(s)
}

/// Rust's `to_ascii_lowercase`: only A–Z change.
func rustASCIILowercase(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { $0.value >= 65 && $0.value <= 90 ? Unicode.Scalar($0.value + 32) ?? $0 : $0 }))
}

/// Rust's `str::lines`.
func rustLines(_ s: String) -> [String] {
    var lines = s.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { piece -> String in
        var v = String.UnicodeScalarView(piece)
        if v.last == "\r" { v.removeLast() }
        return String(v)
    }
    if s.unicodeScalars.last == "\n" || s.isEmpty { lines.removeLast() }
    return lines
}

/// Rust's `f64::powi`: repeated squaring, so results match DeckCraft's to the bit where `pow` would round differently.
func rsPowi(_ x: Double, _ n: Int32) -> Double {
    var a = x
    var b = n
    var r = 1.0
    while true {
        if b & 1 != 0 { r *= a }
        b /= 2
        if b == 0 { break }
        a *= a
    }
    return n < 0 ? 1.0 / r : r
}

/// Rust's `format!("{v:.Ne}")` / `{v:.NE}`.
func rsExp(_ v: Double, _ places: Int, upper: Bool) -> String {
    if v.isNaN { return "NaN" }
    if v.isInfinite { return v < 0 ? "-inf" : "inf" }
    let c = String(format: "%.\(places)e", v)
    guard let e = c.firstIndex(of: "e") else { return c }
    let exp = Int(c[c.index(after: e)...]) ?? 0
    return String(c[..<e]) + (upper ? "E" : "e") + String(exp)
}
