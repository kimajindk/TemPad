import SwiftUI
import Charts
import TemPadCore
import UserNotifications

enum Palette {
    static let cream = Color(red:0.965,green:0.961,blue:0.929)
    static let paper = Color(red:0.985,green:0.982,blue:0.966)
    static let wine = Color(red:0.65,green:0,blue:0.19)
    static let ink = Color(red:0.19,green:0.16,blue:0.17)
    static let muted = Color(red:0.43,green:0.43,blue:0.41)
    static let green = Color(red:0.32,green:0.47,blue:0.36)
    static let line = Color(red:0.90,green:0.88,blue:0.85)
}

@main struct TemPadApp: App {
    @State private var store = MonitorStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView(store:store).preferredColorScheme(.light)
                .environment(\.locale,Locale(identifier:"ko_KR"))
                .onChange(of:phase) { _,value in store.phaseChanged(value) }
        }
    }
}

struct RootView: View {
    @Bindable var store: MonitorStore
    var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()
            Group {
                if store.tab == 0 { HomeView(store:store) }
                else if store.tab == 1 { EventsView(store:store) }
                else { SettingsView(store:store) }
            }
            .safeAreaInset(edge:.bottom,spacing:0) { navigation }
        }
        .foregroundStyle(Palette.ink)
        .sheet(item:$store.selectedEvent) { event in EventDetail(store:store,event:event) }
        .monitoringAlerts(store:store)
    }
    private var navigation: some View {
        HStack {
            nav("홈",icon:"house",selectedIcon:"house.fill",index:0)
            nav("알림",icon:"bell",selectedIcon:"bell.fill",index:1)
            nav("설정",icon:"slider.horizontal.3",selectedIcon:"slider.horizontal.3",index:2)
        }
        .padding(.vertical,8).frame(height:64)
        .background(Palette.cream).overlay(alignment:.top) { Rectangle().fill(Palette.line).frame(height:1) }
    }
    private func nav(_ title:String,icon:String,selectedIcon:String,index:Int)->some View {
        Button { store.tab=index } label: {
            VStack(spacing:8) {
                Image(systemName:store.tab == index ? selectedIcon : icon).font(.system(size:19,weight:.medium))
                Text(title).font(.system(size:10,weight:.semibold))
            }.frame(maxWidth:.infinity).foregroundStyle(store.tab == index ? Palette.wine : Palette.muted.opacity(0.8))
        }.accessibilityIdentifier("tab\(index)").accessibilityLabel(title)
    }
}

struct EventsView:View {
    var store:MonitorStore
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                pageHeader("알림 기록",subtitle:"최근 알림을 확인하세요")
                if store.events.isEmpty {
                    VStack(spacing:16) {
                        Image(systemName:"bell.badge").font(.system(size:34,weight:.ultraLight)).foregroundStyle(Palette.wine).frame(width:80,height:80).background(Palette.wine.opacity(0.045),in:Circle())
                        Text("아직 새로운 알림이 없어요").font(.system(size:16,weight:.semibold))
                        Text("온도 변화나 연결 상태를 확인할 일이 생기면\n이곳에서 확인할 수 있어요.").font(.system(size:13)).lineSpacing(8).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
                    }.frame(maxWidth:.infinity).padding(.vertical,64)
                } else {
                    Text("최근 7일 · \(store.events.count)건").font(.caption).foregroundStyle(Palette.muted)
                    ForEach(store.events){event in
                        Button {store.showDetail(event)} label:{
                            HStack(alignment:.top,spacing:16) {
                                Image(systemName:event.kind == .connection || event.kind == .motion ? "wifi.exclamationmark":"thermometer.medium").font(.system(size:18)).foregroundStyle(Palette.wine).frame(width:40,height:40).background(Palette.wine.opacity(0.05),in:RoundedRectangle(cornerRadius:16))
                                VStack(alignment:.leading,spacing:8) {
                                    Text(event.kind.label).font(.system(size:14,weight:.semibold))
                                    Text(event.detail).font(.system(size:12)).foregroundStyle(Palette.muted).multilineTextAlignment(.leading)
                                    Text(displayTime(event.date,full:true)).font(.system(size:10)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength:0)
                                Text(event.resolvedAt != nil ? "종료" : (event.acknowledgedAt == nil ? "확인 필요" : "확인함")).font(.system(size:9,weight:.medium)).foregroundStyle(event.resolvedAt == nil ? Palette.wine:Palette.muted)
                            }.padding(24).background(.white,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain).accessibilityIdentifier("event-\(event.kind.rawValue)")
                    }
                }
            }.padding(24)
        }
    }
}

struct SettingsView:View {
    var store:MonitorStore
    @State private var low=36.0
    @State private var high=38.0
    @State private var confirming=false
    @State private var saved=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                pageHeader("설정",subtitle:"알림과 모니터링 환경")
                VStack(alignment:.leading,spacing:16) {
                    sectionLabel("온도 알림",icon:"thermometer.medium")
                    Text("설정 범위를 벗어나면 바로 알려드려요.").font(.system(size:12)).foregroundStyle(Palette.muted)
                    Text("최근 5분 내 0.5°C 이상 상승해도 즉시 알려드려요.").font(.system(size:12)).foregroundStyle(Palette.wine)
                    threshold("상한 온도",value:$high,range:(low+1)...45)
                    Divider().overlay(Palette.line)
                    threshold("하한 온도",value:$low,range:30...(high-1))
                    Button {
                        store.configure(.init(low:low,high:high));saved=true
                    } label:{Text(saved ? "저장했어요":"변경사항 저장").font(.system(size:13,weight:.semibold)).frame(maxWidth:.infinity).padding(.vertical,16).background(Palette.wine,in:RoundedRectangle(cornerRadius:16)).foregroundStyle(.white)}.accessibilityIdentifier("saveThresholds")
                }.padding(24).background(.white,in:RoundedRectangle(cornerRadius:24))
                VStack(alignment:.leading,spacing:16) {
                    sectionLabel("iPhone 알림",icon:"bell")
                    Text(store.authorization == .authorized ? "알림이 켜져 있어요":"화면을 보고 있지 않을 때도\n필요한 알림을 받을 수 있어요.").font(.system(size:13)).lineSpacing(8).foregroundStyle(Palette.muted)
                    Button {
                        if store.authorization == .denied || store.authorization == .authorized {UIApplication.shared.open(URL(string:UIApplication.openSettingsURLString)!)}
                        else {Task{await store.requestPermission()}}
                    }label:{HStack{Text(store.authorization == .notDetermined ? "알림 켜기":"알림 설정 열기");Spacer();Image(systemName:"arrow.up.right")}.font(.system(size:13,weight:.semibold)).foregroundStyle(Palette.wine)}.accessibilityIdentifier("notificationPermission")
                    if store.notificationsError {Text("알림을 설정하지 못했어요. 다시 시도해 주세요.").font(.caption).foregroundStyle(.orange)}
                }.padding(24).background(.white,in:RoundedRectangle(cornerRadius:24))
                VStack(spacing:16) {
                    HStack{Text("온도 단위");Spacer();Text("섭씨 °C").foregroundStyle(Palette.muted)}
                    Divider()
                    HStack{Text("기록 보관");Spacer();Text("최근 7일").foregroundStyle(Palette.muted)}
                    Divider()
                    Button{confirming=true}label:{HStack{Text("기록 초기화");Spacer();Image(systemName:"trash")}.foregroundStyle(Palette.wine)}.accessibilityIdentifier("clearHistory")
                }.font(.system(size:13)).padding(24).background(.white,in:RoundedRectangle(cornerRadius:24))
                HStack {Spacer();Image("TemPadLogo").resizable().scaledToFit().frame(width:80).opacity(0.45);Spacer()}.padding(.top,8)
                Text("TemPad · 0.2.0").font(.system(size:10)).foregroundStyle(Palette.muted).frame(maxWidth:.infinity)
            }.padding(24)
        }
        .onAppear{low=store.settings.low;high=store.settings.high}
        .onChange(of:low){_,_ in saved=false}.onChange(of:high){_,_ in saved=false}
        .confirmationDialog("저장된 온도와 알림 기록을 지울까요?",isPresented:$confirming,titleVisibility:.visible) {
            Button("기록 삭제",role:.destructive){store.clearHistory()}
            Button("취소",role:.cancel){}
        }message:{Text("예약된 알림도 함께 삭제됩니다. 온도 기준 설정은 유지됩니다.")}
    }
    private func threshold(_ title:String,value:Binding<Double>,range:ClosedRange<Double>)->some View {
        HStack {
            Text(title).font(.system(size:13))
            Spacer()
            Button{value.wrappedValue=max(range.lowerBound,(value.wrappedValue*10-1).rounded()/10)}label:{Image(systemName:"minus").frame(width:48,height:48).background(Palette.cream,in:Circle())}.accessibilityLabel(title+" 낮추기")
            Text(String(format:"%.1f°",value.wrappedValue)).font(.system(size:22,weight:.medium,design:.rounded)).monospacedDigit().frame(width:64)
            Button{value.wrappedValue=min(range.upperBound,(value.wrappedValue*10+1).rounded()/10)}label:{Image(systemName:"plus").frame(width:48,height:48).background(Palette.cream,in:Circle())}.accessibilityLabel(title+" 높이기")
        }.foregroundStyle(Palette.ink)
    }
}

struct AlertCard:View {
    let event:MonitorEvent
    let onConfirm:()->Void
    let onDetail:()->Void
    var body:some View {
        VStack(spacing:16) {
            Image(systemName:"thermometer.medium").font(.system(size:30,weight:.light)).foregroundStyle(Palette.wine).frame(width:64,height:64).background(Palette.wine.opacity(0.07),in:Circle())
            Text(event.kind.title).font(.system(size:20,weight:.semibold)).multilineTextAlignment(.center)
            Text(event.detail).font(.system(size:14)).lineSpacing(8).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
            Text(displayTime(event.date)).font(.system(size:11)).foregroundStyle(Palette.muted)
            Button(action:onConfirm){Text("확인").font(.system(size:15,weight:.semibold)).frame(maxWidth:.infinity).padding(.vertical,16).background(Palette.wine,in:RoundedRectangle(cornerRadius:16)).foregroundStyle(.white)}.accessibilityIdentifier("acknowledgeAlert")
            Button("기록 보기",action:onDetail).font(.system(size:13)).foregroundStyle(Palette.muted).accessibilityIdentifier("viewAlertRecord")
        }.padding(24).background(Palette.paper,in:RoundedRectangle(cornerRadius:24))
    }
}

private struct MonitoringAlertsModifier:ViewModifier {
    var store:MonitorStore
    @State private var detail:MonitorEvent?

    func body(content:Content)->some View {
        ZStack {
            content
                .accessibilityHidden(store.popup != nil)
                .allowsHitTesting(store.popup == nil)
            if let event=store.popup {
                Color.black.opacity(0.25).ignoresSafeArea().accessibilityHidden(true)
                AlertCard(event:event,onConfirm:{store.acknowledge(event)},onDetail:{
                    store.acknowledge(event)
                    detail=event
                })
                .padding(24)
                .transition(.opacity.combined(with:.scale(scale:0.97)))
                .accessibilityElement(children:.contain)
            }
        }
        .animation(.easeInOut(duration:0.2),value:store.popup?.id)
        .sheet(item:$detail) { event in
            // EventDetail also hosts alerts; erase the recursive presentation's view type.
            AnyView(EventDetail(store:store,event:event))
        }
    }
}

extension View {
    func monitoringAlerts(store:MonitorStore)->some View {
        modifier(MonitoringAlertsModifier(store:store))
    }
}

struct EventDetail:View {
    var store:MonitorStore
    let event:MonitorEvent
    @Environment(\.dismiss) private var dismiss
    private var current:MonitorEvent {store.engine.events.first{$0.id == event.id} ?? event}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Image(systemName:"thermometer.medium").font(.system(size:32,weight:.light)).foregroundStyle(Palette.wine)
                    Text(current.kind.title).font(.title2.bold())
                    Text(current.detail).font(.body).foregroundStyle(Palette.muted)
                    VStack(spacing:16) {
                        detailRow("발생",value:displayTime(current.date,full:true))
                        detailRow("확인",value:current.acknowledgedAt.map{displayTime($0)} ?? "아직 확인하지 않음")
                        detailRow("종료",value:current.resolvedAt.map{displayTime($0)} ?? "상태 확인 중")
                        if let reason=current.endReason {detailRow("종료 사유",value:reason)}
                        if let reference=current.referenceValue { detailRow("상승 기준 온도",value:String(format:"%.1f °C",reference)) }
                        detailRow("당시 기준",value:String(format:"%.1f - %.1f °C",current.thresholds.low,current.thresholds.high))
                    }.padding(24).background(.white,in:RoundedRectangle(cornerRadius:24))
                    Text("당시 온도 변화").font(.headline)
                    eventChart
                }.padding(24)
            }.background(Palette.cream).navigationTitle("알림 상세").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button("닫기"){dismiss()}}}
        }
        .monitoringAlerts(store:store)
    }
    private struct EventReading:Identifiable {
        let date:Date
        let value:Double
        let segment:Int
        var id:Date {date}
    }
    private var eventChart:some View {
        let samples=store.samples.filter{abs($0.date.timeIntervalSince(current.date)) <= 150}.sorted{$0.date < $1.date}
        var points:[EventReading]=[]
        var segment=0
        for sample in samples {
            guard let value=sample.value else {segment += 1;continue}
            if let previous=points.last,sample.date.timeIntervalSince(previous.date)>75 {segment += 1}
            points.append(.init(date:sample.date,value:value,segment:segment))
        }
        let lower=min(36,(points.map(\.value).min() ?? 36)-0.2)
        let upper=max(38,(points.map(\.value).max() ?? 38)+0.2)
        return Group {
            if points.isEmpty {
                Text("해당 시각의 온도 기록이 없어요").font(.system(size:13)).foregroundStyle(Palette.muted)
                    .frame(maxWidth:.infinity).frame(height:160)
            } else {
                Chart(points) { point in
                    LineMark(x:.value("시간",point.date),y:.value("온도",point.value),series:.value("구간",point.segment))
                        .foregroundStyle(Palette.wine).lineStyle(.init(lineWidth:2,lineCap:.round))
                }
                .chartYScale(domain:lower...upper)
                .chartXAxis { AxisMarks(values:.automatic(desiredCount:3)) { _ in
                    AxisValueLabel(format:.dateTime.hour().minute().locale(Locale(identifier:"en_GB"))).foregroundStyle(Palette.muted)
                } }
                .chartYAxis { AxisMarks(position:.trailing,values:.automatic(desiredCount:3)) { _ in
                    AxisGridLine(stroke:.init(lineWidth:0.5,dash:[2,4])).foregroundStyle(Palette.line)
                    AxisValueLabel().foregroundStyle(Palette.muted)
                } }
                .frame(height:160)
            }
        }
    }
    private func detailRow(_ title:String,value:String)->some View {HStack{Text(title).foregroundStyle(Palette.muted);Spacer();Text(value)}.font(.system(size:12))}
}

func pageHeader(_ title:String,subtitle:String)->some View {
    VStack(alignment:.leading,spacing:8){Text(title).font(.system(size:28,weight:.semibold)).tracking(-1);Text(subtitle).font(.system(size:13)).foregroundStyle(Palette.muted)}.padding(.top,8).padding(.bottom,8)
}
func sectionLabel(_ title:String,icon:String)->some View {Label(title,systemImage:icon).font(.system(size:15,weight:.semibold))}
func displayTime(_ date:Date,full:Bool=false)->String {
    let style:Date.FormatStyle = full ? .dateTime.month().day().hour().minute() : .dateTime.hour().minute()
    return date.formatted(style.locale(Locale(identifier:"ko_KR")))
}

func temperatureString(_ value:Double?)->String {
    value.map{String(format:"%.1f",$0)} ?? "--.-"
}

struct ConnectionLabel: View {
    let connected: Bool
    var compact = false
    var body: some View {
        HStack(spacing:8) {
            Circle().fill(connected ? Palette.green:.orange).frame(width:8,height:8)
            Text(connected ? (compact ? "LIVE":"패드 연결됨"):"연결 확인 중")
                .font(.system(size:11,weight:.medium)).foregroundStyle(Palette.muted)
        }
    }
}
