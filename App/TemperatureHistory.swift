import SwiftUI
import Charts
import TemPadCore

/// Period-based review of corrected pad temperatures, separate from the live monitor.
struct TemperatureHistoryView: View {
    var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    @State private var stream: HistoryStream = .pointB
    @State private var period: HistoryPeriod = .day
    @State private var anchor = Date()
    @State private var selectedDate: Date?
    @State private var selectedEvent: MonitorEvent?
    @State private var snapshot = HistorySnapshot()
    @State private var eventsExpanded = false
    @State private var readingsExpanded = false

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ko_KR")
        value.timeZone = .current
        return value
    }
    private var interval: DateInterval { interval(containing: anchor) }
    private var point: ThermalPoint { ThermalGrid.overviewPoints[stream.index] }
    private var streamTitle: String { ThermalGrid.trackingName(for: point) }
    private var records: [HistoryReading] { snapshot.readings }
    private var sampleRevision: HistoryRevision {
        .init(count: store.samples.count, first: store.samples.first, last: store.samples.last)
    }
    private var relevantEvents: [MonitorEvent] {
        store.events.filter { $0.date >= interval.start && $0.date < interval.end }
    }
    private var earliest: Date { snapshot.earliest ?? snapshot.updatedAt }
    private var canGoBack: Bool { interval(containing: shiftedAnchor(-1)).end > earliest }
    private var canGoForward: Bool { interval(containing: shiftedAnchor(1)).start <= snapshot.updatedAt }
    private var isCurrent: Bool { interval.start <= snapshot.updatedAt && interval.end > snapshot.updatedAt }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    historyControls
                    VStack(alignment: .leading, spacing: 24) {
                        dateNavigation
                        historyChart
                    }
                    .padding(24)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line.opacity(0.6), lineWidth: 1))
                    VStack(spacing: 8) {
                        eventsSection
                        readingsSection
                    }
                }.padding(24)
            }
            .background(Palette.cream)
            .navigationTitle("온도 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }.accessibilityIdentifier("closeHistory")
                }
            }
            .sheet(item: $selectedEvent) { event in EventDetail(store: store, event: event) }
        }
        .tint(Palette.wine)
        .foregroundStyle(Palette.ink)
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .onAppear { anchor = store.now; refreshSnapshot() }
        .onChange(of: period) { _, _ in selectedDate = nil; refreshSnapshot() }
        .onChange(of: stream) { _, _ in selectedDate = nil; refreshSnapshot() }
        .onChange(of: anchor) { _, _ in selectedDate = nil; refreshSnapshot() }
        .onChange(of: sampleRevision) { _, _ in refreshSnapshot() }
    }

    private var historyControls: some View {
        HStack(spacing: 16) {
            Menu {
                Picker("관찰 영역", selection: $stream) {
                    ForEach(HistoryStream.allCases) { item in
                        Text(ThermalGrid.trackingName(for: ThermalGrid.overviewPoints[item.index])).tag(item)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(streamTitle).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("관찰 영역, \(streamTitle)")
            .accessibilityIdentifier("historyStream")
            Spacer(minLength: 0)
            Picker("기록 기간", selection: $period) {
                ForEach(HistoryPeriod.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .accessibilityIdentifier("historyPeriod")
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            Button { anchor = shiftedAnchor(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 48, height: 48)
            }.disabled(!canGoBack).opacity(canGoBack ? 1:0.25).accessibilityLabel("이전 기간").accessibilityIdentifier("historyPrevious")
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(rangeTitle).font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.85)
                if !isCurrent {
                    Button("현재 기간으로") { anchor = store.now }.font(.system(size: 11, weight: .medium))
                }
            }
            Spacer(minLength: 0)
            Button { anchor = shiftedAnchor(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).frame(width: 48, height: 48)
            }.disabled(!canGoForward).opacity(canGoForward ? 1:0.25).accessibilityLabel("다음 기간").accessibilityIdentifier("historyNext")
        }
    }

    private var historyChart: some View {
        let data = records
        let buckets = snapshot.buckets
        let average = snapshot.average
        let minimum = snapshot.minimum
        let maximum = snapshot.maximum
        let chosen = selectedDate.flatMap(selectedBucket)
        let hasSelection = selectedDate != nil
        let summaryValue = hasSelection ? chosen?.mean : average
        let summaryTitle = hasSelection ? (chosen == nil ? (period == .week ? "이 날짜의 기록 없음" : "이 시각의 기록 없음") : period == .week ? "선택일 평균" : "선택 구간 평균") : "평균"
        let lower = min(36.0, (minimum ?? 36) - 0.2)
        let upper = max(38.0, (maximum ?? 38) + 0.2)
        return VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summaryTitle)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(temperatureString(summaryValue))
                            .font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("historySummaryValue")
                        Text("°C").font(.system(size: 18)).foregroundStyle(Palette.muted)
                    }
                    Text(selectionCaption(chosen))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                if hasSelection {
                    Button("선택 해제") { selectedDate = nil }
                        .font(.system(size: 12, weight: .medium)).frame(minHeight: 48)
                }
            }
            if data.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 28, weight: .light))
                    Text("이 기간에는 온도 기록이 없어요").font(.system(size: 14, weight: .medium))
                    Text("다른 날짜를 선택해 주세요").font(.system(size: 12))
                }
                .foregroundStyle(Palette.muted).frame(maxWidth: .infinity).frame(height: 192)
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        if period == .week {
                            BarMark(x: .value("날짜", bucket.date, unit: .day), yStart: .value("최저", bucket.minimum), yEnd: .value("최고", bucket.maximum), width: .ratio(0.24))
                                .foregroundStyle(Palette.wine.opacity(selectedDate == nil || chosen?.id == bucket.id ? 0.55 : 0.16))
                                .cornerRadius(8)
                            PointMark(x: .value("날짜", bucket.date, unit: .day), y: .value("평균", bucket.mean))
                                .foregroundStyle(Palette.wine).symbolSize(24)
                        } else {
                            AreaMark(x: .value("시각", bucket.date), yStart: .value("최저", bucket.minimum), yEnd: .value("최고", bucket.maximum), series: .value("연결 구간", bucket.segment))
                                .foregroundStyle(Palette.wine.opacity(0.10))
                            LineMark(x: .value("시각", bucket.date), y: .value("온도", bucket.mean), series: .value("연결 구간", bucket.segment))
                                .foregroundStyle(Palette.wine).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            if snapshot.isolatedSegments.contains(bucket.segment) {
                                PointMark(x: .value("시각", bucket.date), y: .value("온도", bucket.mean))
                                    .foregroundStyle(Palette.wine).symbolSize(24)
                            }
                        }
                    }
                    if period != .week {
                        ForEach(relevantEvents) { event in
                            RuleMark(x: .value("알림 시각", event.date))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                                .foregroundStyle(Palette.wine.opacity(0.18))
                        }
                    }
                    if let chosen {
                        let selectionTime = period == .week ? calendar.date(byAdding: .hour, value: 12, to: chosen.date) ?? chosen.date : chosen.date
                        RuleMark(x: .value("선택 시각", selectionTime)).foregroundStyle(Palette.muted.opacity(0.4))
                        PointMark(x: .value("선택 시각", selectionTime), y: .value("선택 온도", chosen.mean))
                            .foregroundStyle(Palette.wine).symbolSize(48)
                    }
                }
                .chartXScale(domain: interval.start...interval.end)
                .chartYScale(domain: lower...upper)
                .chartXAxis {
                    if period == .week {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR")))
                                .foregroundStyle(Palette.muted)
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) { Text(clockTime(date)).foregroundStyle(Palette.muted) }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(Palette.line)
                        AxisValueLabel().foregroundStyle(Palette.muted)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance:0).onChanged { value in
                                guard let anchor=proxy.plotFrame else { return }
                                let frame=geometry[anchor]
                                let x=min(max(value.location.x-frame.minX,0),frame.width)
                                selectedDate=proxy.value(atX:x,as:Date.self)
                            })
                    }
                }
                .frame(height: 192)
                .accessibilityIdentifier("historyChart")
                .accessibilityLabel("\(streamTitle), \(rangeTitle), 보정 온도 기록")
                .accessibilityValue("평균 \(temperatureString(average))도, 최저 \(temperatureString(minimum))도, 최고 \(temperatureString(maximum))도")
                if period == .week {
                    HStack(spacing: 8) {
                        Capsule().fill(Palette.wine.opacity(0.55)).frame(width: 4, height: 16)
                        Text("최저–최고").font(.system(size: 11))
                        Circle().fill(Palette.wine).frame(width: 4, height: 4).padding(.leading, 8)
                        Text("평균").font(.system(size: 11))
                    }.foregroundStyle(Palette.muted)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("5분 평균 · 옅은 영역은 최저–최고")
                        if !relevantEvents.isEmpty { Text("세로 점선은 알림이 발생한 시각이에요") }
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            HStack(spacing: 24) {
                statistic("최저", value: hasSelection ? chosen?.minimum : minimum)
                Rectangle().fill(Palette.line).frame(width: 1, height: 40)
                statistic("최고", value: hasSelection ? chosen?.maximum : maximum)
            }
        }
    }

    @ViewBuilder private var eventsSection: some View {
        if !relevantEvents.isEmpty {
            DisclosureGroup(isExpanded: $eventsExpanded) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(relevantEvents.enumerated()), id: \.element.id) { index, event in
                        Button { selectedEvent = event } label: {
                            HStack(alignment: .center, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(event.kind.label).font(.system(size: 13, weight: .medium))
                                    Text(readingDate(event.date)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 16).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if index < relevantEvents.count - 1 { Divider() }
                    }
                }.padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Text("알림").font(.system(size: 13, weight: .medium))
                    Text("\(relevantEvents.count)건").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.foregroundStyle(Palette.ink)
            }
            .padding(16)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("historyEventsDisclosure")
        }
    }

    private var readingsSection: some View {
        let recent = Array(records.suffix(8).reversed())
        return Group {
            if !recent.isEmpty {
                DisclosureGroup(isExpanded: $readingsExpanded) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, reading in
                            HStack(spacing: 16) {
                                Text(readingDate(reading.date)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                Spacer(minLength: 0)
                                Text("\(temperatureString(reading.value)) °C")
                                    .font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                            }.padding(.vertical, 16)
                            if index < recent.count - 1 { Divider() }
                        }
                    }.padding(.top, 8)
                } label: {
                    Text("최근 측정값 보기").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                }
                .padding(16)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("historyReadingsDisclosure")
            }
        }
    }

    private func statistic(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text("\(temperatureString(value)) °C").font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var rangeTitle: String {
        switch period {
        case .day:
            return interval.start.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR")))
        case .week:
            return readingDate(interval.start, includeTime: false) + " – " + readingDate(interval.end.addingTimeInterval(-1), includeTime: false)
        }
    }
    private func clockTime(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    private func readingDate(_ date: Date, includeTime: Bool = true) -> String {
        let style: Date.FormatStyle = includeTime ? .dateTime.month().day().hour().minute() : .dateTime.month().day()
        return date.formatted(style.locale(Locale(identifier: "ko_KR")))
    }
    private func selectionCaption(_ bucket: HistoryBucket?) -> String {
        guard let selectedDate else { return streamTitle }
        guard let bucket else { return readingDate(selectedDate, includeTime: period != .week) }
        if period == .day {
            return clockTime(bucket.start) + "–" + clockTime(bucket.end) + " · " + streamTitle
        }
        return readingDate(bucket.date, includeTime: period != .week)
    }
    private func selectedBucket(at date: Date) -> HistoryBucket? {
        if period == .week {
            return snapshot.buckets.first { calendar.isDate($0.date, inSameDayAs: date) }
        }
        // A touch in an unrecorded interval must not select a distant observation.
        guard let coverage = snapshot.coverage.first(where: { date >= $0.start && date <= $0.end }) else { return nil }
        return snapshot.buckets.filter { $0.segment == coverage.segment }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
    private func shiftedAnchor(_ direction: Int) -> Date {
        switch period {
        case .day: return calendar.date(byAdding: .day, value: direction, to: anchor) ?? anchor
        case .week: return calendar.date(byAdding: .day, value: direction * 7, to: anchor) ?? anchor
        }
    }
    private func interval(containing date: Date) -> DateInterval {
        switch period {
        case .day:
            let start = calendar.startOfDay(for: date)
            return .init(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
        case .week:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
            return .init(start: calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-604800), end: end)
        }
    }
    private func refreshSnapshot() {
        let now = store.now
        let window = interval
        let samples = store.samples.filter { $0.date >= window.start && $0.date < window.end && $0.date <= now }
            .sorted { $0.date < $1.date }
        var readings: [HistoryReading] = []
        readings.reserveCapacity(samples.count)
        var segment = 0
        var interrupted = false
        for sample in samples {
            guard let value = point.temperature(in: sample) else { interrupted = true; continue }
            if let previous = readings.last, interrupted || sample.date.timeIntervalSince(previous.date) > 75 { segment += 1 }
            readings.append(.init(date: sample.date, value: value, segment: segment))
            interrupted = false
        }
        let groups = Dictionary(grouping: readings, by: \.segment)
        let coverage = groups.map { segment, group in
            let tolerance = group.count == 1 ? 2.5 : 0
            return HistoryCoverage(start: group.first!.date.addingTimeInterval(-tolerance), end: group.last!.date.addingTimeInterval(tolerance), segment: segment)
        }.sorted { $0.start < $1.start }
        snapshot = .init(readings: readings, buckets: makeBuckets(from: readings), coverage: coverage,
                         earliest: store.samples.first?.date, updatedAt: now)
    }
    private func makeBuckets(from readings: [HistoryReading]) -> [HistoryBucket] {
        guard !readings.isEmpty else { return [] }
        // Five-minute summaries keep a full day's plot readable while preserving its
        // extrema. Segment keys prevent aggregation across an interrupted reading.
        let windowStart = interval.start
        let groups = Dictionary(grouping: readings) { reading in
            let date: Date
            if period == .week {
                date = calendar.startOfDay(for: reading.date)
            } else {
                let offset = floor(reading.date.timeIntervalSince(windowStart) / 300) * 300
                date = windowStart.addingTimeInterval(offset)
            }
            return HistoryBucketKey(date: date, segment: period == .week ? 0 : reading.segment)
        }
        return groups.map { key, group in
            let date = period == .week ? key.date : group.first!.date.addingTimeInterval(group.last!.date.timeIntervalSince(group.first!.date) / 2)
            return HistoryBucket(readings: group, date: date, segment: key.segment)
        }.sorted { $0.date < $1.date }
    }
}

private enum HistoryStream: Int, CaseIterable, Identifiable {
    case pointA, pointB
    var id: Self { self }
    var index: Int { rawValue }
}
private enum HistoryPeriod: CaseIterable, Identifiable {
    case day, week
    var id: Self { self }
    var title: String { switch self { case .day: return "하루"; case .week: return "일주일" } }
}
private struct HistoryReading: Identifiable {
    let date: Date
    let value: Double
    let segment: Int
    var id: Date { date }
}
private struct HistoryBucket: Identifiable {
    let date: Date
    let start: Date
    let end: Date
    let minimum: Double
    let maximum: Double
    let mean: Double
    let segment: Int
    var id: HistoryBucketKey { .init(date: date, segment: segment) }

    init(readings: [HistoryReading], date: Date, segment: Int) {
        self.date = date
        self.start = readings.first!.date
        self.end = readings.last!.date
        self.minimum = readings.map(\.value).min()!
        self.maximum = readings.map(\.value).max()!
        self.mean = HistoryAverage.value(in: readings)!
        self.segment = segment
    }
}
private struct HistoryBucketKey: Hashable {
    let date: Date
    let segment: Int
}
private struct HistoryCoverage {
    let start: Date
    let end: Date
    let segment: Int
}
private struct HistoryRevision: Equatable {
    let count: Int
    let first: TemperatureSample?
    let last: TemperatureSample?
}
private struct HistorySnapshot {
    var readings: [HistoryReading] = []
    var buckets: [HistoryBucket] = []
    var coverage: [HistoryCoverage] = []
    var earliest: Date?
    var updatedAt = Date()
    let average: Double?
    let minimum: Double?
    let maximum: Double?
    let isolatedSegments: Set<Int>

    init(readings: [HistoryReading] = [], buckets: [HistoryBucket] = [], coverage: [HistoryCoverage] = [], earliest: Date? = nil, updatedAt: Date = Date()) {
        self.readings = readings
        self.buckets = buckets
        self.coverage = coverage
        self.earliest = earliest
        self.updatedAt = updatedAt
        self.average = HistoryAverage.value(in: readings)
        self.minimum = readings.map(\.value).min()
        self.maximum = readings.map(\.value).max()
        self.isolatedSegments = Set(Dictionary(grouping: buckets, by: \.segment).filter { $0.value.count == 1 }.map(\.key))
    }
}
private enum HistoryAverage {
    static func value(in readings: [HistoryReading]) -> Double? {
        guard !readings.isEmpty else { return nil }
        // Give recorded minutes equal weight, so a five-second stream does not
        // overwhelm older minute-level records. Missing minutes remain absent.
        var minutes: [Int: (sum: Double, count: Int)] = [:]
        for reading in readings {
            let minute = Int(floor(reading.date.timeIntervalSince1970 / 60))
            let previous = minutes[minute] ?? (sum: 0, count: 0)
            minutes[minute] = (sum: previous.sum + reading.value, count: previous.count + 1)
        }
        return minutes.values.reduce(0) { $0 + $1.sum / Double($1.count) } / Double(minutes.count)
    }
}
