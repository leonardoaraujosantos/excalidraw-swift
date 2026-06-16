import SwiftUI

/// On-screen CPU-vs-GPU renderer benchmark. Runs `RendererBenchmark` off the
/// main thread and shows the per-scene frame times + Metal phase breakdown in a
/// table, so the numbers are readable on the device without the Xcode console.
public struct RendererBenchmarkView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case live = "Live"
        case table = "Table"
        var id: String {
            rawValue
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .live
    @State private var rows: [RendererBenchmark.Row] = []
    @State private var running = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.top, 8)
                .accessibilityIdentifier("benchmark-mode")
                Divider().padding(.top, 8)
                switch mode {
                case .live:
                    LiveBenchmarkView()
                case .table:
                    tableContent
                }
            }
            .navigationTitle("Renderer Benchmark")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("benchmark-done")
                    }
                    if mode == .table {
                        ToolbarItem(placement: .primaryAction) {
                            Button(running ? "Running…" : "Run") { run() }
                                .disabled(running)
                                .accessibilityIdentifier("benchmark-run")
                        }
                    }
                }
        }
    }

    private var tableContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rows.isEmpty, !running {
                placeholder
            } else {
                resultsTable
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ms/frame at 1200×800. Metal = read-back, Direct = GPU-only, "
                + "Hybrid = editor (GPU + CG text). “all” = every component type.")
                .font(.footnote).foregroundStyle(.secondary)
            if !RendererBenchmark.metalAvailable {
                Label("Metal unavailable on this device — showing CPU only", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("No results yet", systemImage: "gauge.with.dots.needle.bottom.50percent")
        } description: {
            Text("Tap Run to render synthetic scenes with both backends and compare.")
        }
        .frame(maxHeight: .infinity)
    }

    private var resultsTable: some View {
        ScrollView {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    cell("Scene", bold: true, align: .leading)
                    cell("N", bold: true)
                    cell("CPU", bold: true)
                    cell("Metal", bold: true)
                    cell("Direct", bold: true)
                    cell("Hybrid", bold: true)
                    cell("vs CPU", bold: true)
                }
                Divider().gridCellColumns(7)
                ForEach(rows) { row in
                    GridRow {
                        cell(row.label, align: .leading)
                        cell("\(row.count)")
                        cell(ms(row.cpuMs))
                        cell(row.metalMs.map(ms) ?? "—")
                        cell(row.metalDirectMs.map(ms) ?? "—")
                        cell(row.hybridMs.map(ms) ?? "—")
                        ratioCell(row.hybridRatio)
                    }
                    .accessibilityIdentifier("benchmark-row-\(row.label)-\(row.count)")
                }
            }
            .padding(12)
            if running {
                ProgressView("Measuring…").padding()
            }
        }
    }

    private func cell(
        _ text: String,
        bold: Bool = false,
        mono: Bool = false,
        align: Alignment = .trailing
    ) -> some View {
        Text(text)
            .font(.system(.subheadline, design: mono ? .monospaced : .default))
            .fontWeight(bold ? .semibold : .regular)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: align)
    }

    private func ratioCell(_ ratio: Double?) -> some View {
        // >1 means Metal is faster (green); <1 means CPU is faster (orange).
        let text = ratio.map { String(format: "%.2f×", $0) } ?? "—"
        let color: Color = ratio == nil ? .secondary : (ratio! >= 1 ? .green : .orange)
        return Text(text)
            .font(.subheadline).monospacedDigit().foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func ms(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func run() {
        running = true
        rows = []
        Task.detached(priority: .userInitiated) {
            let results = RendererBenchmark.run()
            await MainActor.run {
                rows = results
                running = false
            }
        }
    }
}
