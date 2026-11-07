# MarqueeCharts

Charts drawn part by part, from their data. You give it a chart spec (its type, data, axes, labels, legend and fills)
and a theme. It lays the chart out as marks (fills, strokes and text), and tags each mark with the part of the chart it
belongs to: the background, or one data point. Drawing every mark draws the chart. Drawing some parts, each in its
own state, plays a chart build (by series, by category, or by element) one part at a time. Once every part has played,
the chart looks exactly like the finished one.

The chart model, its layout and its number formats come from
[DeckCraftNative](https://github.com/xocialize/DeckCraftNative), a native port of
[DeckCraft](https://github.com/storytold/deckcraft). That is why charts look close to PowerPoint's and number formats
follow Excel's codes. See NOTICE.

## Chart types

| Group | Types |
|---|---|
| Columns | Clustered, Stacked, 100% Stacked |
| Bars | Clustered, Stacked, 100% Stacked |
| Lines | Line, Line with Markers, Stacked, 100% Stacked |
| Areas | Area, Stacked, 100% Stacked |
| Circles | Pie, Doughnut |

Every type supports:

- **Titles:** the chart's and the axes'.
- **Legend:** five positions, or drawn over the plot.
- **Data labels:**
  - positions as PowerPoint offers them;
  - series name, category name and percentage;
  - legend keys and callouts.
- **Value axis:**
  - fixed bounds and major unit;
  - an Excel number format in the chart's language;
  - hidden.
- **Gridlines:** major and minor.
- **Category order:** reversed categories.
- **Fills:** solid, gradient, pattern or none.
- **Lines and outlines.**
- **Point fills.**
- **Colours:** vary colours by point, and monochrome palettes.
- **Line styles:** smooth lines and markers.
- **Bars and doughnuts:** gap width, overlap and hole size.

## Products

| Product | What it is |
|---|---|
| `MarqueeCharts` | The pieces of a chart, Foundation only:<ul><li>the spec (`ChartSpec`, Codable as JSON) and the theme (`ChartTheme`);</li><li>number formats (`NumberFormat`) and the value axis' scale;</li><li>the layout (`ChartLayout.draw` → `ChartDrawing`);</li><li>builds (`ChartBuild`: steps, timing, and each part's state at a moment).</li></ul> |
| `ChartDataTable` (in `MarqueeCharts`) | A chart's data as a table: reading what a spreadsheet copies (tab-separated from Excel and Numbers, or CSV), numbers as people write them in the chart's language (`1.234,5`, `12%`, `$3.00`, `(200)`), and turning the table into categories and series. `ChartSpec.pasting(_:)` applies a pasted table. |
| `MarqueeChartsGraphics` | `ChartRenderer`: draws a `ChartDrawing` into a `CGContext` or an image, with each part in its build state (shown, faded or wiped), using CoreGraphics and CoreText. |
| `ChartLab` | A Mac app for trying charts. Pick a type, edit its data (or paste it from a spreadsheet: Edit › Paste Data, ⇧⌘V) and options, and play or scrub its build. Export a frame, the build's frames, each part alone, or the spec. |

```swift
import MarqueeCharts
import MarqueeChartsGraphics

var chart = ChartSpec.sample(.column)
chart.dataLabels = true
let drawing = ChartLayout.draw(chart, theme: .standard, width: 960, height: 540)

// The finished chart.
let image = ChartRenderer.image(drawing, theme: .standard, scale: 2)

// 1.2 s into a build that wipes each series in from the bottom.
let build = ChartBuild(kind: .bySeries, effect: .wipe, direction: .fromBottom)
let frame = ChartRenderer.image(drawing, theme: .standard, states: build.states(chart, parts: drawing.parts, at: 1.2))
```

A host can draw the marks itself instead. Each mark is a path with a paint, a stroke, or a text in a box. A host
might do this to use its own text engine, or to turn each part into a separate layer.

## Build, test, run

```bash
swift build
swift test                                   # MARQUEE_CHARTS_OUT=<dir> also writes every type and a build as PNGs
swift run ChartLab                           # or Tools/make-app.sh → .build/ChartLab.app
```

macOS 14 or later (iOS 17 for the libraries).

## Licence

MIT OR Apache-2.0, at your option (LICENSE-MIT, LICENSE-APACHE). DeckCraft's notices are in `LICENSES/deckcraft/`.
