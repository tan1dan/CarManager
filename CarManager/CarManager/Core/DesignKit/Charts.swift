import SwiftUI
import Charts

// Chart components drawn to the Figma specs. They take plain numbers and labels — never
// domain types — so a formatter decides what is shown and a chart only decides how.

/// Rounded vertical bars; the highlighted one gets the accent gradient. `nil` values are
/// future periods and render as a short faint stub.
struct BarSeriesChart: View {
    let values: [Double?]
    var labels: [String] = []
    var highlight: Int?
    var color: Color = DS.Colors.accent
    var spacing: CGFloat = 8
    var cornerRadius: CGFloat = 6
    /// A small value tag over the highlighted bar ("€268").
    var highlightTag: String?

    var body: some View {
        let maxValue = max(values.compactMap { $0 }.max() ?? 0, 0.0001)
        let hi = highlight ?? values.lastIndex(where: { $0 != nil })
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let tagSpace: CGFloat = highlightTag == nil ? 0 : 26
                let plot = proxy.size.height - tagSpace
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(values.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            if i == hi, let highlightTag {
                                Text(highlightTag)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x0A121F))
                                    .padding(.horizontal, 6)
                                    .frame(height: 20)
                                    .background(Capsule().fill(.white))
                                    .fixedSize()
                            }
                            bar(index: i, highlighted: i == hi, plot: plot, maxValue: maxValue)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            if !labels.isEmpty {
                HStack(spacing: spacing) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i])
                            .font(.system(size: 10, weight: i == hi ? .semibold : .regular))
                            .foregroundStyle(i == hi ? .white : DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func bar(index i: Int, highlighted: Bool, plot: CGFloat, maxValue: Double) -> some View {
        if let value = values[i] {
            let height = max(6, CGFloat(value / maxValue) * plot)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(highlighted ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(color.opacity(0.28)))
                .frame(height: height)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(height: 6)
        }
    }

    private var accessibilitySummary: String {
        zip(labels.isEmpty ? values.indices.map { "\($0 + 1)" } : labels, values)
            .map { "\($0): \($1.map { String(format: "%.0f", $0) } ?? "no data")" }
            .joined(separator: ", ")
    }
}

/// A smooth line with a gradient area and a glowing last point (Figma "Avg. consumption").
/// Gaps (`nil`) are skipped, not drawn as zero.
struct TrendLineChart: View {
    let values: [Double?]
    var labels: [String] = []
    var color: Color = DS.Colors.accent
    var showsGrid = true
    var showsAxisLabels = true
    var lineWidth: CGFloat = 2.5

    private struct Point: Identifiable { let id: Int; let value: Double }

    var body: some View {
        let points = values.enumerated().compactMap { i, v in v.map { Point(id: i, value: $0) } }
        let low = (points.map(\.value).min() ?? 0), high = (points.map(\.value).max() ?? 1)
        let pad = max((high - low) * 0.25, 0.1)
        VStack(spacing: 8) {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Index", p.id), yStart: .value("Base", low - pad), yEnd: .value("Value", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Index", p.id), y: .value("Value", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    PointMark(x: .value("Index", last.id), y: .value("Value", last.value))
                        .symbolSize(220)
                        .foregroundStyle(color.opacity(0.25))
                    PointMark(x: .value("Index", last.id), y: .value("Value", last.value))
                        .symbolSize(45)
                        .foregroundStyle(.white)
                }
            }
            .chartXScale(domain: 0...max(values.count - 1, 1))
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartXAxis(.hidden)
            .chartYAxis {
                if showsGrid {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                    }
                }
            }
            // Not clipped: the end point's glow may overhang the plot by a few points.
            .padding(.trailing, 6)
            if showsAxisLabels && !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i])
                            .font(.system(size: 10, weight: i == labels.count - 1 ? .semibold : .regular))
                            .foregroundStyle(i == labels.count - 1 ? .white : DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(values.compactMap { $0 }.map { String(format: "%.1f", $0) }.joined(separator: ", "))
    }
}

/// Donut with hairline gaps between segments.
struct DonutChart: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }
    let segments: [Segment]
    var center: String?

    var body: some View {
        Chart(segments) { segment in
            SectorMark(angle: .value("Amount", segment.value), innerRadius: .ratio(0.7), angularInset: 1.5)
                .foregroundStyle(segment.color)
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .overlay {
            if let center {
                Text(center)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .padding(20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.id) \(Int($0.value))" }.joined(separator: ", "))
    }
}

/// How much of an interval has been used up (Figma: Reminders rows).
struct ProgressRing: View {
    let fraction: Double
    var color: Color = DS.Colors.accent
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded()))% used")
    }
}

/// A slim horizontal fill bar (category shares, reminder progress).
struct ProgressBar: View {
    let fraction: Double
    var color: Color = DS.Colors.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}
