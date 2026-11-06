import Foundation

public struct TemperatureSample: Codable, Identifiable, Equatable, Sendable {
    public var id: String { String(date.timeIntervalSince1970) }
    public let date: Date
    public let head: Double?
    public let torso: Double?
    public var isValid: Bool { [head, torso].allSatisfy { $0.map { $0.isFinite && (20...50).contains($0) } ?? false } }
    public var value: Double? { isValid ? max(head!, torso!) : nil }
    public var minimum: Double? { isValid ? min(head!, torso!) - 0.3 : nil }
    public init(date: Date, head: Double?, torso: Double?) { self.date = date; self.head = head; self.torso = torso }
}

public struct TemperatureSettings: Codable, Equatable, Sendable {
    public var low: Double
    public var high: Double
    public init(low: Double = 36, high: Double = 38) { self.low = low; self.high = high }
    public var isValid: Bool { low.isFinite && high.isFinite && low >= 30 && high <= 45 && high - low >= 0.999 }
}

public enum EventKind: String, Codable, Sendable {
    case high, low, rise, connection, motion
    public var title: String {
        switch self { case .rise: return "온도 변화를 확인해 주세요"; case .high, .low: return "온도를 확인해 주세요"; case .connection: return "온도 정보를 받지 못했어요"; case .motion: return "움직임 정보를 확인하고 있어요" }
    }
    public var label: String {
        switch self { case .rise: return "빠른 온도 상승"; case .high: return "상한 초과"; case .low: return "하한 미만"; case .connection: return "연결 확인"; case .motion: return "움직임 정보" }
    }
}

public struct MonitorEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: EventKind
    public let date: Date
    public let value: Double?
    public let thresholds: TemperatureSettings
    public var acknowledgedAt: Date?
    public var resolvedAt: Date?
    public var endReason: String?
    public var referenceValue: Double?
    public init(kind: EventKind, date: Date, value: Double?, thresholds: TemperatureSettings, referenceValue: Double? = nil) {
        self.referenceValue = referenceValue
        self.id = "\(kind.rawValue)-\(Int(date.timeIntervalSince1970))"
        self.kind = kind; self.date = date; self.value = value; self.thresholds = thresholds
    }
    public var detail: String {
        switch kind {
        case .rise: return String(format:"최근 %.1f °C에서 %.1f °C로 올라갔어요. 아기의 상태를 확인해 주세요.",referenceValue ?? 0,value ?? 0)
        case .high: return String(format: "%.1f °C가 감지되어 설정 상한 %.1f °C를 넘었어요.", value ?? 0, thresholds.high)
        case .low: return String(format: "%.1f °C가 감지되어 설정 하한 %.1f °C보다 낮아요.", value ?? 0, thresholds.low)
        case .connection: return "새로운 온도 정보가 도착하지 않았어요. 패드 연결을 확인해 주세요."
        case .motion: return "아기의 마지막 모습을 표시하고 있어요. 연결 상태를 확인해 주세요."
        }
    }
}

public struct AlertEngine: Codable, Sendable {
    public private(set) var events:[MonitorEvent]=[]
    public private(set) var lastValid:Date?
    public private(set) var settings=TemperatureSettings()
    private var recovery=0
    private var recent:[TemperatureSample]?
    public init(settings:TemperatureSettings = .init()) { self.settings=settings }
    public var activeTemperature:MonitorEvent? {
        events.last { $0.resolvedAt == nil && [.high,.low,.rise].contains($0.kind) }
    }
    public mutating func receive(_ sample:TemperatureSample) {
        guard let value=sample.value,lastValid.map({sample.date > $0}) ?? true else { recovery=0;return }
        var history=(recent ?? []).filter{sample.date.timeIntervalSince($0.date) <= 300}
        if let lastValid,sample.date.timeIntervalSince(lastValid) > 7.5 { history.removeAll();recovery=0 }
        defer { history.append(sample);recent=history }
        lastValid=sample.date
        resolve(kind:.connection,at:sample.date,reason:"연결 복구")
        let absolute:EventKind? = value > settings.high ? .high:(value < settings.low ? .low:nil)
        let baseline=history.compactMap(\.value).min()
        if let active=activeTemperature {
            if let absolute,absolute != active.kind {
                resolve(kind:active.kind,at:sample.date,reason:active.kind == .rise ? "설정 범위 이탈로 전환":"반대 조건 전환")
                activate(absolute,at:sample.date,value:value)
                recovery=0
                return
            }
            let inRange=value >= settings.low+0.2-0.0001 && value <= settings.high-0.2+0.0001
            let recovered=active.kind == .rise ? inRange && value <= (active.referenceValue ?? value)+0.2 : inRange
            recovery=recovered ? recovery+1:0
            if recovery >= 3 {
                resolve(kind:active.kind,at:sample.date,reason:"설정 범위 복귀")
                recovery=0;history.removeAll()
            }
        } else if let absolute {
            activate(absolute,at:sample.date,value:value)
        } else if let baseline,value-baseline >= 0.5-0.0001 {
            activate(.rise,at:sample.date,value:value,reference:baseline)
        }
    }
    public mutating func checkHealth(now:Date,startedAt:Date,poseAt:Date) {
        if now.timeIntervalSince(lastValid ?? startedAt) >= 15 {
            activate(.connection,at:now,value:nil)
            resolve(kind:.motion,at:now,reason:"연결 상태에 통합")
            recovery=0;recent=nil
        } else if now.timeIntervalSince(poseAt) >= 5 { activate(.motion,at:now,value:nil) }
        else { resolve(kind:.motion,at:now,reason:"움직임 정보 복구") }
    }
    public mutating func configure(_ value:TemperatureSettings,at date:Date) {
        guard value.isValid else { return }
        for kind in [EventKind.high,.low,.rise] { resolve(kind:kind,at:date,reason:"기준 변경") }
        settings=value;recovery=0;recent=nil
    }
    public mutating func acknowledge(_ id:String,at date:Date) {
        if let i=events.firstIndex(where:{$0.id == id}),events[i].acknowledgedAt == nil { events[i].acknowledgedAt=date }
    }
    public mutating func recordDeliveredEvent(_ event:MonitorEvent) {
        guard !events.contains(where:{$0.id == event.id}) else { return }
        events.append(event)
    }
    public mutating func resetSession(at date:Date) {
        for kind in [EventKind.high,.low,.rise,.connection,.motion] { resolve(kind:kind,at:date,reason:"모니터링 재연결") }
        lastValid=nil;recovery=0;recent=nil
    }
    public mutating func prune(before date:Date) { events.removeAll{$0.date < date && $0.resolvedAt != nil} }
    private mutating func activate(_ kind:EventKind,at date:Date,value:Double?,reference:Double?=nil) {
        guard !events.contains(where:{$0.kind == kind && $0.resolvedAt == nil}) else { return }
        events.append(.init(kind:kind,date:date,value:value,thresholds:settings,referenceValue:reference))
    }
    private mutating func resolve(kind:EventKind,at date:Date,reason:String) {
        for i in events.indices where events[i].kind == kind && events[i].resolvedAt == nil {
            events[i].resolvedAt=date;events[i].endReason=reason
        }
    }
}

public enum Fixture {
    public static func nightFeverOnset(relativeTo date:Date, calendar:Calendar = .current)->Date {
        let today=calendar.date(bySettingHour:2,minute:0,second:0,of:date) ?? calendar.startOfDay(for:date).addingTimeInterval(7200)
        guard today > date else { return today }
        let yesterday=calendar.date(byAdding:.day,value:-1,to:date) ?? date.addingTimeInterval(-86400)
        return calendar.date(bySettingHour:2,minute:0,second:0,of:yesterday) ?? today.addingTimeInterval(-86400)
    }

    public static func sample(at date: Date, start: Date, scenario: String = "steady", settings: TemperatureSettings = .init()) -> TemperatureSample? {
        if scenario == "nightFever" {
            let minutes=date.timeIntervalSince(nightFeverOnset(relativeTo:start))/60
            let torso:Double
            if minutes < 0 { torso=36.8+0.06*sin(minutes/17) }
            else if minutes < 5 { torso=36.8+0.6*minutes/5 }
            else if minutes < 15 { torso=37.4+0.8*(minutes-5)/10 }
            else if minutes < 30 { torso=38.2+0.4*(minutes-15)/15 }
            else if minutes < 90 { torso=38.6-0.4*(minutes-30)/60 }
            else { torso=38.25+0.15*sin((minutes-90)/37+asin(-1.0/3)) }
            let head=torso-0.2+0.02*sin(minutes/11)
            return .init(date:date,head:(head*10).rounded()/10,torso:(torso*10).rounded()/10)
        }
        let elapsed = date.timeIntervalSince(start)
        if scenario == "launchFever" {
            let torso:Double
            if elapsed < 10 { torso=36.8 }
            else if elapsed < 30 { torso=36.8+0.6*(elapsed-10)/20 }
            else if elapsed < 60 { torso=37.4+(elapsed-30)/30 }
            else if elapsed < 90 { torso=38.4+0.2*(elapsed-60)/30 }
            else { torso=38.5+0.1*cos((elapsed-90)/35) }
            return .init(date:date,head:((torso-0.2)*10).rounded()/10,torso:(torso*10).rounded()/10)
        }
        if scenario == "disconnected" && elapsed >= 5 { return nil }
        let t = date.timeIntervalSince1970
        var head = 36.8 + 0.08 * sin(t / 71)
        var torso = 37.1 + 0.08 * sin(t / 103)
        if elapsed >= 0 && elapsed < 25 {
            if scenario == "high" { head = settings.high + 0.1; torso = settings.high + 0.3 }
            if scenario == "low" { head = settings.low - 0.3; torso = settings.low - 0.1 }
        }
        if scenario == "rise" && (10..<35).contains(elapsed) { head=37.2;torso=37.7 }
        if scenario == "delayedHigh" && (35..<60).contains(elapsed) { head = settings.high + 0.1; torso = settings.high + 0.3 }
        return .init(date: date, head: (head * 10).rounded() / 10, torso: (torso * 10).rounded() / 10)
    }
}

public struct Point2: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// Shared deformation field for the baby mesh and the anatomical marker anchors.
public enum BodyMotion {
    public static func transform(_ point: Point2, time: Double, reduced: Bool = false) -> Point2 {
        let intensity = reduced ? 0.1 : 1.0
        let aspect = 16.0/9
        // One slow inhale/exhale continues underneath each small change in resting pose.
        let breath = (1-cos(time * 2 * .pi / 4.8)) * 0.5 * intensity
        let elapsed = max(0,time-5)
        // Begin at five seconds, then alternate arms and head at five-second intervals.
        let cycle = elapsed.truncatingRemainder(dividingBy:15)
        func gesture(_ start:Double)->Double {
            let phase=(cycle-start)/2.8
            guard phase >= 0 && phase <= 1 else { return 0 }
            return pow(sin(.pi*phase),2)
        }
        func smoothStep(_ value:Double)->Double {
            let t=min(1,max(0,value))
            return t*t*(3-2*t)
        }
        let arm=gesture(0),head=gesture(5),otherArm=gesture(10)
        // Three-second transitions and nine-second holds keep the new posture after a gesture.
        // Both ends of the 24-second cycle have zero velocity, so there is no reset jump.
        let posePhase=elapsed.truncatingRemainder(dividingBy:24)
        let restPose:Double
        if posePhase < 3 { restPose=smoothStep(posePhase/3) }
        else if posePhase < 12 { restPose=1 }
        else if posePhase < 15 { restPose=1-smoothStep((posePhase-12)/3) }
        else { restPose=0 }

        let chest = exp(-pow((point.x-0.52)/0.19,2)-pow((point.y-0.54)/0.22,2))
        let body = exp(-pow((point.x-0.51)/0.45,2)-pow((point.y-0.53)/0.38,2))
        var out = point
        // A slight shared lean and chest shift preserve the outline while the resting pose changes.
        let lean = -0.014*restPose
        let dx=point.x-0.50,dy=point.y-0.54
        out.x += (dx*cos(lean)-dy*sin(lean)/aspect-dx)*body*intensity
        out.y += (dx*sin(lean)*aspect+dy*cos(lean)-dy)*body*intensity
        out.x += 0.0045*chest*restPose*intensity
        out.y -= 0.002*chest*restPose*intensity
        out.x += (point.x-0.52) * 0.012 * chest * breath
        out.y += (point.y-0.54) * 0.05 * chest * breath
        let zones: [(Point2,Point2,Double,Double,Double)] = [
            (.init(0.32,0.50),.init(0.23,0.48),0.14,0.18,head*0.105-restPose*0.025),
            (.init(0.40,0.43),.init(0.37,0.28),0.10,0.13,arm*0.27+restPose*0.03),
            (.init(0.40,0.65),.init(0.45,0.78),0.11,0.10,-otherArm*0.243+restPose*0.025),
            (.init(0.61,0.51),.init(0.77,0.36),0.14,0.14,sin(time*0.35)*0.006+restPose*0.016),
            (.init(0.61,0.63),.init(0.77,0.70),0.15,0.09,sin(time*0.40)*0.006-restPose*0.012)
        ]
        for (pivot,center,sx,sy,angle) in zones {
            let weight = exp(-pow((point.x-center.x)/sx,2)-pow((point.y-center.y)/sy,2)) * intensity
            let dx=point.x-pivot.x,dy=point.y-pivot.y
            out.x += (dx*cos(angle)-dy*sin(angle)/aspect-dx)*weight
            out.y += (dx*sin(angle)*aspect+dy*cos(angle)-dy)*weight
        }
        out.x=min(1,max(0,out.x));out.y=min(1,max(0,out.y))
        return out
    }
}
