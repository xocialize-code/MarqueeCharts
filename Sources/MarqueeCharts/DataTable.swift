// MarqueeCharts — a chart's data as a table: reading what a spreadsheet puts on the clipboard (tab-separated from
// Excel and Numbers, or CSV), reading its numbers as people write them (grouping, a decimal comma, percentages,
// currency, negatives in parentheses), and turning the table into categories and series.
import Foundation

public enum ChartDataTable {
    /// The most rows and columns read from pasted text; past them the rest is left out.
    public static let maxRows = 10_000
    public static let maxColumns = 1_000

    // MARK: Text to cells

    /// The cells of delimited text: tab-separated (what Excel and Numbers copy) when it has tabs, else CSV (comma or,
    /// when the first line has more of them, semicolon). Quoted fields may hold the delimiter, quotes (`""`) and line
    /// breaks. Rows are padded to the widest; trailing empty rows are left out.
    public static func cells(_ text: String) -> [[String]] {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = text.contains("\t") ? "\t"
            : firstLine.filter({ $0 == ";" }).count > firstLine.filter({ $0 == "," }).count ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var atFieldStart = true
        var it = Array(text).makeIterator()
        var pending: Character?
        func next() -> Character? {
            if let p = pending {
                pending = nil
                return p
            }
            return it.next()
        }
        func endField() {
            if row.count < maxColumns { row.append(field) }
            field = ""
            atFieldStart = true
        }
        func endRow() {
            endField()
            if rows.count < maxRows { rows.append(row) }
            row = []
        }
        while let ch = next() {
            if quoted {
                if ch == "\"" {
                    if let n = next() {
                        if n == "\"" { field.append("\"") } else {
                            quoted = false
                            pending = n
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"" where atFieldStart:
                quoted = true
                atFieldStart = false
            case delimiter: endField()
            case "\r\n", "\n", "\r": endRow()
            default:
                field.append(ch)
                atFieldStart = false
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        while let last = rows.last, last.allSatisfy({ rustTrim($0).isEmpty }) { rows.removeLast() }
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// `rows` as tab-separated text (what a spreadsheet reads from the clipboard).
    public static func text(_ rows: [[String]]) -> String {
        rows.map { r in
            r.map { c in c.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\"" }) ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c }
                .joined(separator: "\t")
        }.joined(separator: "\n")
    }

    // MARK: Numbers

    /// A cell's number as a person or a spreadsheet writes it, in `language` (`de-DE` writes `1.234,5`), or nil when it
    /// isn't one. Takes grouping (commas, dots, spaces, apostrophes as the language uses them), a leading or trailing
    /// currency symbol, a trailing `%` (a fraction: `12%` is 0.12), negatives with `-`, `−` or in parentheses, and
    /// exponents (`1.5E+3`). An empty cell is nil.
    public static func number(_ cell: String, language: String? = nil) -> Double? {
        var s = String(rustTrim(cell))
        if s.isEmpty { return nil }
        let (sep, dec) = NumberFormat.marks(language)
        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")"), s.count > 2 {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        var percent = false
        if s.hasSuffix("%") {
            percent = true
            s = String(s.dropLast())
        }
        // A currency symbol before or after the number; whitespace inside it (a space or no-break space groups).
        let symbol: (Character) -> Bool = { $0.unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol } }
        s = String(s.drop(while: { symbol($0) || $0.isWhitespace }))
        while let l = s.last, symbol(l) || l.isWhitespace { s.removeLast() }
        if s.hasPrefix("-") {
            negative.toggle()
            s = String(s.dropFirst())
        } else if s.hasPrefix("+") {
            s = String(s.dropFirst())
        }
        s = String(s.filter { !$0.isWhitespace && $0 != "'" })
        // The decimal mark: the language's, unless the text only makes sense the other way (`1,234.5` in German is
        // still an English number; one mark used several times is grouping).
        let other: Character = dec == "," ? "." : ","
        var d = dec
        if let lastDec = s.lastIndex(of: dec), let lastOther = s.lastIndex(of: other), lastOther > lastDec { d = other }
        // One other mark not followed by exactly three digits can't be grouping: `2.5` in German is two and a half.
        if !s.contains(d), let i = s.firstIndex(of: other), s.filter({ $0 == other }).count == 1, s[s.index(after: i)...].count != 3 { d = other }
        if s.filter({ $0 == d }).count > 1 { d = d == "." ? "," : "." }
        let group: Character = d == "." ? "," : "."
        s = String(s.filter { $0 != group && ($0 != sep || sep == d) })
        if d == "," { s = s.replacingOccurrences(of: ",", with: ".") }
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || ".eE+-".contains($0)) }), var v = Double(s), v.isFinite else { return nil }
        if percent { v /= 100 }
        return negative ? -v : v
    }

    // MARK: Cells to data

    /// The categories and series in `rows`. With `seriesInRows`, each row is a series; otherwise each column is (as in
    /// PowerPoint's data sheet). The first row holds the series names, and the first column the category names, when
    /// they aren't numbers; missing names are `Series n` and `Category n`. Cells that aren't numbers are gaps.
    public static func data(_ rows: [[String]], language: String? = nil, seriesInRows: Bool = false) -> (categories: [String], series: [(name: String, values: [Double?])]) {
        let grid = seriesInRows ? transposed(rows) : rows
        guard let first = grid.first, !first.isEmpty else { return ([], []) }
        let isNum = { (s: String) in number(s, language: language) != nil }
        // A label column: a cell below the first row that's text, not a number.
        let labelColumn = grid.dropFirst().contains { r in r.first.map { !rustTrim($0).isEmpty && !isNum($0) } ?? false }
            || (grid.count == 1 && !first.isEmpty && !isNum(first[0]))
        let firstData = labelColumn ? 1 : 0
        // A header row: text where values go.
        let header = grid.count > 1 && first.dropFirst(firstData).contains { !rustTrim($0).isEmpty && !isNum($0) }
            || (grid.count > 1 && labelColumn && rustTrim(first[0]).isEmpty)
        let body = header ? Array(grid.dropFirst()) : grid
        let width = grid.map(\.count).max() ?? 0
        guard width > firstData else { return (body.indices.map { "Category \($0 + 1)" }, []) }
        let categories = body.enumerated().map { i, r in
            let name = labelColumn ? String(rustTrim(r.first ?? "")) : ""
            return name.isEmpty ? "Category \(i + 1)" : name
        }
        let series = (firstData ..< width).map { c -> (name: String, values: [Double?]) in
            let n = header ? String(rustTrim(first.at(c) ?? "")) : ""
            return (n.isEmpty ? "Series \(c - firstData + 1)" : n, body.map { number($0.at(c) ?? "", language: language) })
        }
        return (categories, series)
    }

    /// `rows` with rows and columns swapped (short rows padded).
    public static func transposed(_ rows: [[String]]) -> [[String]] {
        let w = rows.map(\.count).max() ?? 0
        return (0 ..< w).map { c in rows.map { $0.at(c) ?? "" } }
    }

    /// `chart`'s data as a sheet: the series names across the top, the categories down the side.
    public static func rows(_ chart: ChartSpec) -> [[String]] {
        var out: [[String]] = [[""] + chart.series.map(\.name)]
        for i in 0 ..< chart.pointCount {
            out.append([chart.categories.at(i) ?? ""] + chart.series.map { s in
                (s.values.at(i) ?? nil).map { NumberFormat.format("General", $0, chart.language) } ?? ""
            })
        }
        return out
    }
}

extension ChartSpec {
    /// The chart with new data, each series keeping the look of the one at its position.
    public func withData(categories: [String], series: [(name: String, values: [Double?])]) -> ChartSpec {
        var c = self
        c.categories = categories
        c.series = series.enumerated().map { i, n in
            var s = self.series.at(i) ?? ChartSeries(name: "", values: [])
            s.name = n.name
            s.values = n.values
            return s
        }
        return c
    }

    /// The chart with the data in pasted `text` (`ChartDataTable.data`).
    public func pasting(_ text: String, seriesInRows: Bool = false) -> ChartSpec {
        let d = ChartDataTable.data(ChartDataTable.cells(text), language: language, seriesInRows: seriesInRows)
        return withData(categories: d.categories, series: d.series)
    }
}
