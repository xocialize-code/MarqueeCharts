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
  - A bar, a slice, a bubble and a marker each belong to their own point.
  - A line's segment belongs to the point it runs to.
  - An area belongs to its first point.
  - A data label belongs to its point.
  - Keep this true: hosts' chart builds depend on it.

- **Roles:** every mark says what it draws (`ChartMark.Role`: bar, slice, segment, area, bubble, marker, label), and Grow
  moves each by its role (`Grow.swift`). A new kind of mark needs a role, or it fades in under Grow.
- **One geometry, every output:** the CoreGraphics renderer and the Lottie writer draw the same `ChartMark.grown`
  geometry. Check a change with ThorVG: a scratch package rendering both, with `ChartRenderer.image(..., outlines: true)`
  so text is compared like for like (50–60 dB expected).
- **Lottie order:** Lottie draws a composition's first layer, and a layer's first shape, on top. The writer reverses
  drawing order at both levels.
- **Text spacing is PowerPoint's:** lines are 1.2 × size, the baseline where the font's ascent and descent split it.
  That's what keeps text where a PowerPoint-faithful host puts it.

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
- **Scatter lines:** a scatter series with a line of its own draws it, as PowerPoint does. DeckCraft draws a scatter
  chart's markers alone.
- **Bubble colours:** a bubble takes its point's own fill, and a single series that varies colours by point uses one
  accent per bubble, as PowerPoint does. DeckCraft paints every bubble in its series' colour.

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
