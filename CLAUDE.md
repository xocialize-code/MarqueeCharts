# MarqueeCharts — working notes

The chart engine lifted out of a DeckCraftNative-based renderer (2026-11-07). The repo is
`xocialize-code/MarqueeCharts`, and it is **PUBLIC**. Its plan and its consumers are private and stay out of this repo.

## Rules

- **Public and generic.** Nothing about any client, event, show or brand goes in this repo: no names, styles or fonts,
  no private repository names or paths, no infrastructure URLs. What a product does with the charts (compiling them
  into its own formats, playing them) stays in that product. The default theme is Office's default palette.
- **Code that came from DeckCraftNative or DeckCraft** names its source file and licence in its header. MIT OR
  Apache-2.0; NOTICE, and `LICENSES/deckcraft/`.
- **Never crash.** No force unwraps, traps or unchecked indices on input. Numbers from a spec are hostile:
  `ChartTests.hostileNumbersDontTrap`.
- **Layout needs no fonts.** Text widths are estimated from character counts, as DeckCraft does. This is what lets
  a host draw the text with its own engine and still get the same layout. The `MarqueeChartsGraphics` renderer uses
  CoreText.
- **Parts:**
  - A mark belongs to the background or to one point.
  - A bar, a slice and a marker each belong to their own point.
  - A line's segment belongs to the point it runs to.
  - An area belongs to its first point.
  - A data label belongs to its point.
  - Keep this true: hosts' chart builds depend on it.

## Hosts

A DeckCraftNative-based host draws the charts this package takes:

- It turns its own chart model into a `ChartSpec` in the slide's theme.
- It draws the marks on its own canvas, with its own text.
- It leaves the other types and options to its own renderer until they move here.

That host keeps a parity test comparing the two renderers on a fixture corpus. A change to the layout here should run
it before a release.

## Deliberate differences from DeckCraft

- **Doughnuts:** a doughnut's slices are rings, so the hole shows what is behind the chart. Its default labels sit
  across the ring.
- **Stacked areas:** a stacked area fills the band between its line and the one below, opaque. DeckCraft fills every
  area down to the axis, so the areas overlap.
- **Smooth lines in a build:** a smooth line keeps its curve while it builds point by point.

## Layout

| What | Where |
|---|---|
| Spec, theme, palette | `Sources/MarqueeCharts/Spec.swift` |
| Layout (from DCRender `Chart.swift`) | `Sources/MarqueeCharts/Layout.swift` |
| Marks, parts, drawings | `Sources/MarqueeCharts/Drawing.swift` |
| Builds and part states | `Sources/MarqueeCharts/Build.swift` |
| Axis scale and labels | `Sources/MarqueeCharts/Scale.swift` |
| Number formats | `Sources/MarqueeCharts/NumberFormat.swift` |
| Colours | `Sources/MarqueeCharts/Color.swift` |
| Patterns | `Sources/MarqueeCharts/Patterns.swift` |
| Rust semantics | `Sources/MarqueeCharts/Support.swift` |
| CoreGraphics renderer | `Sources/MarqueeChartsGraphics/Renderer.swift` |
| The lab | `Sources/ChartLab/` |
| The lab as an app bundle | `Tools/make-app.sh` (AppProbe needs a bundle) |
