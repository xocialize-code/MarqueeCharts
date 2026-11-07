// ChartLab — an app for trying MarqueeCharts: pick a type, edit its data and options, scrub or play its build, and
// export frames, parts and the spec. `swift run ChartLab`.
import AppKit
import MarqueeCharts
import MarqueeChartsLottie
import SwiftUI
import UniformTypeIdentifiers

@main
struct ChartLabApp: App {
    @NSApplicationDelegateAdaptor(LabDelegate.self) var delegate
    @State private var model = LabModel()

    var body: some Scene {
        WindowGroup("Chart Lab") {
            LabView(model: model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Spec…") { openSpec(model) }.keyboardShortcut("o")
                Button("Save Spec…") { saveSpec(model) }.keyboardShortcut("s")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Data") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ChartDataTable.text(ChartDataTable.rows(model.spec)), forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste Data") { pasteData(model, seriesInRows: false) }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Paste Data, Series in Rows") { pasteData(model, seriesInRows: true) }
            }
            CommandMenu("Export") {
                Button("Frame as PNG…") { exportFrame(model) }.keyboardShortcut("e")
                Button("Build Frames…") { exportFolder(model, frames: true) }
                Button("Parts…") { exportFolder(model, frames: false) }
                Button("Lottie Animation…") { exportLottie(model) }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

/// Run unbundled (`swift run`), the app still takes the menu bar and comes forward.
final class LabDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The clipboard's table (from a spreadsheet, or CSV text) as the chart's data.
@MainActor func pasteData(_ model: LabModel, seriesInRows: Bool) {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    model.spec = model.spec.pasting(text, seriesInRows: seriesInRows)
}

@MainActor func openSpec(_ model: LabModel) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try model.load(Data(contentsOf: url)) } catch { NSAlert(error: error).runModal() }
}

@MainActor func saveSpec(_ model: LabModel) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "\(model.spec.kind.rawValue).json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try model.specJSON().write(to: url) } catch { NSAlert(error: error).runModal() }
}

@MainActor func exportFrame(_ model: LabModel) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "\(model.spec.kind.rawValue).png"
    guard panel.runModal() == .OK, let url = panel.url, let png = model.framePNG() else { return }
    do { try png.write(to: url) } catch { NSAlert(error: error).runModal() }
}

/// The build's frames (`frame-0000.png`…, 30 per second) or each part alone (`<part>.png`, with `parts.json` naming
/// them in drawing order), with the spec beside them, into a folder.
@MainActor func exportFolder(_ model: LabModel, frames: Bool) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Export"
    guard panel.runModal() == .OK, let dir = panel.url else { return }
    do {
        try model.specJSON().write(to: dir.appendingPathComponent("spec.json"))
        if frames {
            for (k, png) in model.buildFrames().enumerated() {
                try png.write(to: dir.appendingPathComponent(String(format: "frame-%04d.png", k)))
            }
        } else {
            let parts = model.partImages()
            for (name, png) in parts { try png.write(to: dir.appendingPathComponent("\(name).png")) }
            try JSONEncoder().encode(parts.map(\.0)).write(to: dir.appendingPathComponent("parts.json"))
        }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    } catch {
        NSAlert(error: error).runModal()
    }
}

/// The chart and its build as a Lottie animation (`.json`), text as outlines, the finished chart held a second.
@MainActor func exportLottie(_ model: LabModel) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "\(model.spec.kind.rawValue)-\(model.build.effect.rawValue).json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let (w, h) = model.canvas.size
    let doc = ChartDocument(chart: model.spec, theme: model.themeChoice.theme, width: w, height: h)
    let data = ChartLottie.animation(doc, build: model.build, options: .init(fps: 30, scale: 2, background: model.themeChoice.background, hold: 1))
    do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
}
