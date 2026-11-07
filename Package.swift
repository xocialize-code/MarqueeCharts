// swift-tools-version: 6.2
// MarqueeCharts — charts drawn part by part, from their data: a chart spec (type, data, axes, labels, legend), the
// theme it is drawn in, and a layout that turns them into marks, each tagged with the part of the chart it belongs to
// (the background, or one point), so any part can animate on its own. The chart model, its layout and its number
// formats come from DeckCraftNative and DeckCraft (MIT OR Apache-2.0; NOTICE).
//
// - MarqueeCharts: the spec, the theme, number formats, axis scales, the layout and chart builds. Foundation only.
// - MarqueeChartsGraphics: draws a chart into a CGContext or an image (CoreGraphics and CoreText).
// - MarqueeChartsLottie: a chart and its build as a Lottie animation, text as glyph outlines.
// - ChartLab: an app for trying charts: pick a type, edit its data, scrub its build, export frames and specs.
import PackageDescription

let package = Package(
    name: "MarqueeCharts",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MarqueeCharts", targets: ["MarqueeCharts"]),
        .library(name: "MarqueeChartsGraphics", targets: ["MarqueeChartsGraphics"]),
        .library(name: "MarqueeChartsLottie", targets: ["MarqueeChartsLottie"]),
        .executable(name: "ChartLab", targets: ["ChartLab"]),
    ],
    targets: [
        .target(name: "MarqueeCharts"),
        .target(name: "MarqueeChartsGraphics", dependencies: ["MarqueeCharts"]),
        .target(name: "MarqueeChartsLottie", dependencies: ["MarqueeCharts", "MarqueeChartsGraphics"]),
        .executableTarget(name: "ChartLab", dependencies: ["MarqueeCharts", "MarqueeChartsGraphics", "MarqueeChartsLottie"]),
        .testTarget(name: "MarqueeChartsTests", dependencies: ["MarqueeCharts", "MarqueeChartsGraphics", "MarqueeChartsLottie"]),
    ]
)
