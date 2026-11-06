import SwiftUI
import Charts
import TemPadCore

struct HomeView: View {
    var store: MonitorStore
    @State private var expanded = false
    @State private var showHistory = false
    @State private var showMeasurementInfo = false
    @State private var selectedPoint: ThermalPoint?
    private var value: Double? {
        guard store.temperatureFresh else { return nil }
        return selectedPoint.map { $0.temperature(in:store.latest) } ?? store.currentValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.firstTextBaseline) {
                    Text("모니터링").font(.system(size:28,weight:.semibold)).tracking(-0.8)
                    Spacer()
                    Text(store.now,format:.dateTime.month().day()).font(.system(size:12)).foregroundStyle(Palette.muted)
                }
                VStack(spacing:0) {
                    ZStack {
                        ThermalBackdrop()
                        ThermalView(store:store,selectedPoint:$selectedPoint)
                    }
                    .frame(height:256)
                    .overlay(alignment:.topTrailing) {
                        Button { expanded=true } label: {
                            Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:16,weight:.medium))
                                .frame(width:48,height:48).background(.white.opacity(0.72),in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain).padding(16)
                        .accessibilityLabel("모니터링 상세보기").accessibilityIdentifier("expandThermal")
                    }
                    HStack(alignment:.center,spacing:16) {
                        VStack(alignment:.leading,spacing:8) {
                            HStack(spacing:8) {
                                Text(selectedPoint == nil ? "보정 온도":"선택 지점").font(.system(size:12,weight:.medium)).foregroundStyle(Palette.muted)
                                    .accessibilityIdentifier("selectedPointTitle")
                                Button { showMeasurementInfo=true } label: {
                                    Image(systemName:"info.circle").font(.system(size:12)).foregroundStyle(Palette.muted)
                                        .frame(width:48,height:48).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("측정 방식 안내")
                            }
                            HStack(alignment:.firstTextBaseline,spacing:8) {
                                Text(temperatureString(value)).font(.system(size:40,weight:.medium,design:.rounded)).monospacedDigit().tracking(-1)
                                    .accessibilityIdentifier("currentTemperature")
                                Text("°C").font(.system(size:18)).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer(minLength:0)
                        VStack(alignment:.trailing,spacing:16) {
                            if selectedPoint == nil {
                                HStack(spacing:8) {
                                    Circle().fill(store.isWarning ? .orange:Palette.green).frame(width:8,height:8)
                                    Text(store.temperatureFresh ? (store.isWarning ? "온도 확인 필요":"설정 범위 안"):"수신 대기 중")
                                }.font(.system(size:12,weight:.medium))
                            } else {
                                Text("빈 곳을 눌러 해제").font(.system(size:11)).foregroundStyle(Palette.muted)
                            }
                            Text(store.temperatureFresh ? "\(max(0,Int(store.now.timeIntervalSince(store.latest?.date ?? store.now))))초 전 갱신":"연결을 확인해 주세요")
                                .font(.system(size:11)).foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(24).background(Palette.paper)
                }
                .clipShape(RoundedRectangle(cornerRadius:24))
                .overlay(RoundedRectangle(cornerRadius:24).strokeBorder(Palette.line.opacity(0.5),lineWidth:1))
                Button { showHistory=true } label: {
                    HStack(spacing:16) {
                        Image(systemName:"waveform.path").font(.system(size:18)).foregroundStyle(Palette.wine)
                        Text("온도 흐름 자세히 보기").font(.system(size:14,weight:.medium))
                        Spacer()
                        Image(systemName:"chevron.right").font(.system(size:14))
                    }.frame(minHeight:48)
                }.buttonStyle(.plain).accessibilityIdentifier("openTracking")
                if store.storageError { Text("기록을 저장하지 못했어요").font(.caption).foregroundStyle(.orange) }
            }.padding(24)
        }
        .scrollIndicators(.hidden)
        .background(Palette.cream)
        .safeAreaInset(edge:.top,spacing:0) { homeHeader }
        .fullScreenCover(isPresented:$expanded) { MonitoringDetail(store:store,selectedPoint:$selectedPoint).monitoringAlerts(store:store) }
        .sheet(isPresented:$showHistory) { TemperatureHistoryView(store:store).monitoringAlerts(store:store) }
        .sheet(isPresented:$showMeasurementInfo) { MeasurementInfoView().monitoringAlerts(store:store) }
    }

    private var homeHeader: some View {
        HStack(spacing:16) {
            Palette.wine
                .frame(width:112,height:32)
                .mask {
                    Image("TemPadLogo").resizable().scaledToFit()
                        .colorInvert().saturation(0).contrast(3).luminanceToAlpha()
                }
                .accessibilityLabel("TemPad")
            Spacer(minLength:16)
            ConnectionLabel(connected:store.connected)
        }
        .padding(.horizontal,24)
        .padding(.vertical,16)
        .frame(maxWidth:.infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius:24,bottomTrailingRadius:24)
                .fill(.white).ignoresSafeArea(edges:.top)
        }
        .accessibilityIdentifier("homeHeader")
    }
}

struct MonitoringDetail: View {
    var store:MonitorStore
    @Binding var selectedPoint:ThermalPoint?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {
            VStack(spacing:24) {
                HStack(spacing:16) {
                    Button { dismiss() } label: {
                        Image(systemName:"xmark").font(.system(size:16,weight:.medium)).frame(width:48,height:48)
                            .background(Palette.paper,in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain).accessibilityLabel("닫기").accessibilityIdentifier("closeExpanded")
                    Text("온도 모니터링").font(.system(size:17,weight:.semibold))
                    Spacer()
                    ConnectionLabel(connected:store.connected,compact:true)
                }
                VStack(spacing:0) {
                    ThermalView(store:store,selectedPoint:$selectedPoint)
                        .aspectRatio(16/11,contentMode:.fit)
                        .padding(.top,16)
                    TrackingPanel(store:store,selectedPoint:$selectedPoint)
                }
                .background(ThermalBackdrop())
                .clipShape(RoundedRectangle(cornerRadius:24))
                .overlay(RoundedRectangle(cornerRadius:24).strokeBorder(.white.opacity(0.8),lineWidth:1))
                Text(selectedPoint == nil ? "아기 위의 격자를 눌러 온도를 확인하세요":"빈 곳을 누르면 기본 추적으로 돌아가요")
                    .font(.system(size:12)).foregroundStyle(Palette.muted)
            }.padding(24)
        }
        .background(Palette.cream).foregroundStyle(Palette.ink)
        .environment(\.locale,Locale(identifier:"ko_KR"))
    }
}

struct TrackingPanel: View {
    var store: MonitorStore
    @Binding var selectedPoint: ThermalPoint?
    @State private var hours=1.0
    @State private var selectedDate:Date?
    private var current:Double? {
        guard store.temperatureFresh else { return nil }
        return selectedPoint.map { $0.temperature(in:store.latest) } ?? store.currentValue
    }
    private func value(_ sample:TemperatureSample)->Double? {
        if let selectedPoint { return selectedPoint.temperature(in:sample) }
        return sample.value
    }
    private struct Point:Identifiable {
        let id:String
        let date:Date
        let value:Double
        let segment:Int
    }
    private var points:[Point] {
        let raw=store.samples.filter{$0.date >= store.now.addingTimeInterval(-hours*3600)}
        let samples:[TemperatureSample]
        if hours == 24 {
            samples=Dictionary(grouping:raw,by:{Int($0.date.timeIntervalSince1970)/60}).sorted{$0.key < $1.key}.compactMap { _,bucket in
                let valid=bucket.filter(\.isValid)
                guard !valid.isEmpty else { return bucket.first }
                return .init(date:valid[0].date,head:valid.compactMap(\.head).reduce(0,+)/Double(valid.count),torso:valid.compactMap(\.torso).reduce(0,+)/Double(valid.count))
            }
        } else { samples=raw }
        var result:[Point]=[],segment=0
        for (index,sample) in samples.enumerated() {
            if index > 0 && sample.date.timeIntervalSince(samples[index-1].date) > 75 { segment += 1 }
            if let reading=value(sample) { result.append(.init(id:sample.id,date:sample.date,value:reading,segment:segment)) }
            else { segment += 1 }
        }
        return result
    }
    var body: some View {
        let data=points
        let nearest=selectedDate.flatMap { selected in data.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) } }
        let lower=min(36.0,(data.map(\.value).min() ?? 36)-0.2)
        let upper=max(38.0,(data.map(\.value).max() ?? 38)+0.2)
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:8) {
                        Text(selectedPoint == nil ? "대표 보정 온도":"선택 지점 온도")
                            .font(.system(size:13,weight:.medium)).accessibilityIdentifier("trackingPointTitle")
                    }
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Text(temperatureString(nearest?.value ?? current)).font(.system(size:32,weight:.medium,design:.rounded)).monospacedDigit()
                        Text("°C").font(.system(size:14)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength:0)
                VStack(alignment:.trailing,spacing:8) {
                    Text(nearest.map{displayTime($0.date)} ?? "실시간 추이").font(.system(size:11)).foregroundStyle(Palette.muted)
                    HStack(spacing:0) {
                        period("15분",value:0.25,id:"period15")
                        period("1시간",value:1,id:"period1")
                        period("24시간",value:24,id:"period24")
                    }
                }
            }
            Chart {
                ForEach(data) { point in
                    AreaMark(x:.value("시간",point.date),yStart:.value("기준",lower),yEnd:.value("온도",point.value),series:.value("구간",point.segment))
                        .foregroundStyle(LinearGradient(colors:[Palette.wine.opacity(0.12),.white.opacity(0.02)],startPoint:.top,endPoint:.bottom))
                    LineMark(x:.value("시간",point.date),y:.value("온도",point.value),series:.value("구간",point.segment))
                        .foregroundStyle(Palette.wine).lineStyle(.init(lineWidth:2,lineCap:.round))
                }
                if let nearest {
                    RuleMark(x:.value("선택 시각",nearest.date)).foregroundStyle(Palette.wine.opacity(0.25))
                    PointMark(x:.value("시각",nearest.date),y:.value("온도",nearest.value)).foregroundStyle(Palette.wine).symbolSize(32)
                }
            }
            .chartXScale(domain:store.now.addingTimeInterval(-hours*3600)...store.now)
            .chartYScale(domain:lower...upper)
            .chartXAxis { AxisMarks(values:.automatic(desiredCount:3)) { _ in AxisValueLabel(format:.dateTime.hour().minute().locale(Locale(identifier:"ko_KR"))).foregroundStyle(Palette.muted) } }
            .chartYAxis { AxisMarks(position:.trailing,values:.automatic(desiredCount:3)) { _ in
                AxisGridLine(stroke:.init(lineWidth:0.5,dash:[2,4])).foregroundStyle(Palette.ink.opacity(0.12))
                AxisValueLabel().foregroundStyle(Palette.muted)
            } }
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
            .frame(height:112)
            .accessibilityIdentifier("temperatureChart")
            .accessibilityLabel((selectedPoint == nil ? "전체":"선택 지점")+" 온도 그래프")
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .background(.white.opacity(0.72))
        .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.8)).frame(height:1) }
        .onChange(of:selectedPoint) { _,_ in selectedDate=nil }
    }
    private func period(_ title:String,value:Double,id:String)->some View {
        Button { hours=value;selectedDate=nil } label: {
            Text(title).font(.system(size:11,weight:hours == value ? .semibold:.regular))
                .foregroundStyle(hours == value ? Palette.wine:Palette.muted)
                .padding(.horizontal,8).frame(height:32)
                .background(hours == value ? .white.opacity(0.8):.clear,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
