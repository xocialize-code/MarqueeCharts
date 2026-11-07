// ChartLab — the window: options on the left, the chart and its build in the middle, its data underneath.
import MarqueeCharts
import SwiftUI

struct LabView: View {
    @Bindable var model: LabModel

    var body: some View {
        HSplitView {
            OptionsPane(model: model)
                .frame(minWidth: 260, idealWidth: 290, maxWidth: 360)
            VSplitView {
                VStack(spacing: 0) {
                    ChartCanvas(model: model)
                    Divider()
                    BuildBar(model: model)
                }
                .frame(minHeight: 380)
                DataGrid(model: model)
                    .frame(minHeight: 160, idealHeight: 220)
            }
        }
    }
}

// MARK: The chart

struct ChartCanvas: View {
    let model: LabModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let img = model.image {
                    let (w, h) = (Double(img.width), Double(img.height))
                    let k = Swift.min((geo.size.width - 32) / w, (geo.size.height - 32) / h)
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: Swift.max(w * k, 1), height: Swift.max(h * k, 1))
                        .shadow(radius: 3)
                        .accessibilityIdentifier("chartImage")
                }
            }
        }
    }
}

struct BuildBar: View {
    @Bindable var model: LabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Build", selection: $model.build.kind) {
                    ForEach(ChartBuildKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(width: 230)
                .accessibilityIdentifier("buildKind")
                Picker("Effect", selection: $model.build.effect) {
                    ForEach(ChartEffect.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(width: 140)
                .accessibilityIdentifier("buildEffect")
                if model.build.effect == .wipe {
                    Picker("", selection: $model.build.direction) {
                        ForEach(WipeDirection.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .accessibilityIdentifier("wipeDirection")
                }
                Picker("", selection: $model.build.easing) {
                    ForEach(ChartEasing.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                .accessibilityIdentifier("buildEasing")
                Toggle("Background first", isOn: $model.build.animateBackground)
                Stepper("Step \(model.build.duration, specifier: "%.2f") s", value: $model.build.duration, in: 0.1 ... 5, step: 0.1)
                Stepper("Overlap \(Int(model.build.overlap * 100))%", value: $model.build.overlap, in: 0 ... 0.9, step: 0.1)
                Spacer()
            }
            HStack(spacing: 12) {
                Button(model.playing ? "Pause" : "Play") { model.playing ? model.stop() : model.play() }
                    .keyboardShortcut(.space, modifiers: [])
                    .frame(width: 70)
                    .accessibilityIdentifier("play")
                Slider(
                    value: Binding(get: { model.time ?? model.length }, set: { model.stop(); model.time = $0 }),
                    in: 0 ... Swift.max(model.length, 0.01)
                )
                .accessibilityIdentifier("scrub")
                Text(timeLabel).monospacedDigit().frame(width: 260, alignment: .leading)
                Button("Finished") {
                    model.stop()
                    model.time = nil
                }
                .accessibilityIdentifier("finished")
                Toggle("Part boxes", isOn: $model.showParts)
            }
        }
        .padding(10)
    }

    var timeLabel: String {
        guard let t = model.time else { return "Finished chart · \(model.steps.count) steps" }
        let steps = model.steps
        let step = model.currentStep.flatMap { steps.at($0) }.map { " · \($0.label)" } ?? ""
        return String(format: "%.2f / %.2f s", t, model.length) + step
    }
}

// MARK: Options

struct OptionsPane: View {
    @Bindable var model: LabModel

    var body: some View {
        Form {
            Section("Chart") {
                Picker("Type", selection: Binding(get: { model.spec.kind }, set: { model.setKind($0) })) {
                    ForEach(ChartKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("chartKind")
                TextField("Title", text: Binding(get: { model.spec.title ?? "" }, set: { model.spec.title = $0.isEmpty ? nil : $0 }))
                Picker("Legend", selection: $model.spec.legend) {
                    Text("None").tag(LegendPosition?.none)
                    ForEach(LegendPosition.allCases, id: \.self) { Text($0.label).tag(LegendPosition?.some($0)) }
                }
                Toggle("Legend over the plot", isOn: $model.spec.legendOverlay)
                Picker("Size", selection: $model.canvas) {
                    ForEach(CanvasSize.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Theme", selection: $model.themeChoice) {
                    ForEach(LabTheme.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Data labels") {
                Toggle("Show", isOn: $model.spec.dataLabels)
                    .accessibilityIdentifier("dataLabels")
                Picker("Position", selection: labelBinding(\.position)) {
                    Text("Automatic").tag(LabelPosition?.none)
                    ForEach(LabelPosition.positions(model.spec.kind), id: \.self) { Text(positionName($0)).tag(LabelPosition?.some($0)) }
                }
                Toggle("Series name", isOn: labelBinding(\.seriesName))
                Toggle("Category name", isOn: labelBinding(\.categoryName))
                Toggle("Percentage", isOn: labelBinding(\.percent))
                Toggle("Legend key", isOn: labelBinding(\.legendKey))
                Toggle("Callout", isOn: labelBinding(\.callout))
            }
            Section("Axes") {
                Toggle("Gridlines", isOn: $model.spec.gridlines)
                Toggle("Minor gridlines", isOn: $model.spec.minorGridlines)
                Toggle("Categories reversed", isOn: $model.spec.categoriesReversed)
                Toggle("Hide value axis", isOn: $model.spec.valueAxis.hidden)
                TextField("Number format", text: Binding(get: { model.spec.valueAxis.format ?? "" }, set: { model.spec.valueAxis.format = $0.isEmpty ? nil : $0 }))
                TextField("Category title", text: Binding(get: { model.spec.categoryAxisTitle ?? "" }, set: { model.spec.categoryAxisTitle = $0.isEmpty ? nil : $0 }))
                TextField("Value title", text: Binding(get: { model.spec.valueAxisTitle ?? "" }, set: { model.spec.valueAxisTitle = $0.isEmpty ? nil : $0 }))
            }
            Section("Series") {
                ForEach(model.spec.series.indices, id: \.self) { i in
                    SeriesOptions(model: model, index: i)
                }
            }
            Section("More") {
                Toggle("Logarithmic value axis", isOn: Binding(get: { model.spec.valueAxis.logBase != nil }, set: { model.spec.valueAxis.logBase = $0 ? 10 : nil }))
                    .accessibilityIdentifier("logAxis")
                Toggle("Up/down bars", isOn: $model.spec.upDownBars)
                    .accessibilityIdentifier("upDownBars")
                Toggle("Data table", isOn: Binding(get: { model.spec.dataTable != nil }, set: { model.spec.dataTable = $0 ? ChartDataTableStyle() : nil }))
                    .accessibilityIdentifier("dataTable")
                TextField("Secondary format", text: Binding(get: { model.spec.secondaryAxis.format ?? "" }, set: { model.spec.secondaryAxis.format = $0.isEmpty ? nil : $0 }))
            }
            Section("Style") {
                Toggle("Vary colours by point", isOn: $model.spec.varyColors)
                Toggle("Monochrome", isOn: $model.spec.monochrome)
                Toggle("Smooth lines", isOn: Binding(
                    get: { model.spec.series.contains(where: \.smooth) },
                    set: { v in for i in model.spec.series.indices { model.spec.series[i].smooth = v } }
                ))
                LabeledContent("Gap width") { Slider(value: $model.spec.gapWidth, in: 0 ... 5) }
                LabeledContent("Overlap") { Slider(value: $model.spec.overlap, in: -1 ... 1) }
                LabeledContent("Hole") { Slider(value: $model.spec.holeSize, in: 0.1 ... 0.9) }
            }
        }
        .formStyle(.grouped)
    }

    /// A binding to one of the chart's label options (made when first changed).
    func labelBinding<T>(_ kp: WritableKeyPath<LabelOptions, T>) -> Binding<T> {
        Binding(
            get: { (model.spec.labelOptions ?? LabelOptions())[keyPath: kp] },
            set: { v in
                var o = model.spec.labelOptions ?? LabelOptions()
                o[keyPath: kp] = v
                model.spec.labelOptions = o
            }
        )
    }

    func positionName(_ p: LabelPosition) -> String {
        switch p {
        case .center: "Center"
        case .insideEnd: "Inside End"
        case .insideBase: "Inside Base"
        case .outsideEnd: "Outside End"
        case .bestFit: "Best Fit"
        case .left: "Left"
        case .right: "Right"
        case .above: "Above"
        case .below: "Below"
        }
    }
}

// MARK: Data

/// Categories down, series across, as PowerPoint's data sheet.
struct DataGrid: View {
    @Bindable var model: LabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Data").font(.headline)
                Spacer()
                Button("Add Category", action: model.addCategory).accessibilityIdentifier("addCategory")
                Button("Remove Category", action: model.removeCategory)
                Button("Add Series", action: model.addSeries).accessibilityIdentifier("addSeries")
                Button("Remove Series", action: model.removeSeries)
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 120)
                        ForEach(model.spec.series.indices, id: \.self) { s in
                            ForEach(model.fields, id: \.self) { f in
                                if f == model.fields.first {
                                    TextField("Series", text: Binding(get: { model.spec.series.at(s)?.name ?? "" }, set: { model.spec.series[s].name = $0 }))
                                        .frame(width: 110)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("").frame(width: 110)
                                }
                            }
                        }
                    }
                    if model.fields.count > 1 {
                        GridRow {
                            Text("").frame(width: 120)
                            ForEach(model.spec.series.indices, id: \.self) { _ in
                                ForEach(model.fields, id: \.self) { f in Text(f.rawValue).foregroundStyle(.secondary).frame(width: 110) }
                            }
                        }
                    }
                    ForEach(model.spec.categories.indices, id: \.self) { i in
                        GridRow {
                            TextField("Category", text: Binding(get: { model.spec.categories.at(i) ?? "" }, set: { model.spec.categories[i] = $0 }))
                                .frame(width: 120)
                            ForEach(model.spec.series.indices, id: \.self) { s in
                                ForEach(model.fields, id: \.self) { f in
                                    ValueCell(text: model.value(s, i, f)) { model.setValue(s, i, $0, f) }
                                        .frame(width: 110)
                                        .accessibilityIdentifier(f == .value ? "value-\(s)-\(i)" : "\(f.rawValue.lowercased())-\(s)-\(i)")
                                }
                            }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(4)
            }
        }
        .padding(10)
    }
}

/// A value cell: edited as text, applied on Return or when it loses focus.
struct ValueCell: View {
    let text: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: text) { _, v in if !focused { draft = v } }
            .onChange(of: focused) { _, f in if !f { commit(draft) } }
            .onSubmit { commit(draft) }
    }
}


/// One series' own options: its type and axis in a combo chart, a trendline and error bars.
struct SeriesOptions: View {
    @Bindable var model: LabModel
    let index: Int

    var series: Binding<ChartSeries> {
        Binding(get: { model.spec.series.at(index) ?? ChartSeries(name: "", values: []) }, set: { if model.spec.series.indices.contains(index) { model.spec.series[index] = $0 } })
    }

    var body: some View {
        // Plain rows, not a disclosure group: accessibility can't open a SwiftUI disclosure group, and the lab is tested
        // through it.
        Text(series.wrappedValue.name.isEmpty ? "Series \(index + 1)" : series.wrappedValue.name).fontWeight(.semibold)
        Group {
            if model.spec.kind == .combo {
                Picker("Type", selection: Binding(get: { series.wrappedValue.kind ?? .column }, set: { series.wrappedValue.kind = $0 })) {
                    ForEach(ChartKind.allCases.filter { !$0.isPie && $0 != .combo && !$0.isXY }, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("seriesKind-\(index)")
                Toggle("Secondary axis", isOn: series.secondaryAxis)
                    .accessibilityIdentifier("secondary-\(index)")
            }
            Picker("Trendline", selection: Binding(
                get: { series.wrappedValue.trendlines.first?.kind },
                set: { k in series.wrappedValue.trendlines = k.map { [ChartTrendline(kind: $0, order: 2, period: 2, showRSquared: $0 != .movingAvg)] } ?? [] }
            )) {
                Text("None").tag(ChartTrendline.Kind?.none)
                ForEach(ChartTrendline.Kind.allCases, id: \.self) { Text($0.label).tag(ChartTrendline.Kind?.some($0)) }
            }
            .accessibilityIdentifier("trendline-\(index)")
            Picker("Error bars", selection: Binding(
                get: { series.wrappedValue.errorBars?.amount },
                set: { a in series.wrappedValue.errorBars = a.map { ChartErrorBars(amount: $0, value: $0 == .percentage ? 10 : $0 == .fixed ? 0.5 : 1) } }
            )) {
                Text("None").tag(ChartErrorBars.Amount?.none)
                Text("Fixed").tag(ChartErrorBars.Amount?.some(.fixed))
                Text("Percentage").tag(ChartErrorBars.Amount?.some(.percentage))
                Text("Standard deviation").tag(ChartErrorBars.Amount?.some(.standardDeviation))
                Text("Standard error").tag(ChartErrorBars.Amount?.some(.standardError))
            }
            .accessibilityIdentifier("errorBars-\(index)")
        }
    }
}
