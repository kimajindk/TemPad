import SwiftUI
import UserNotifications
import TemPadCore

@MainActor @Observable final class MonitorStore {
    var samples: [TemperatureSample] = []
    var engine = AlertEngine()
    var latest: TemperatureSample?
    var now = Date()
    var poseDate = Date()
    var startedAt = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970/5)*5)
    var motionStartedAt = Date()
    var popup: MonitorEvent?
    var selectedEvent: MonitorEvent?
    var tab = 0
    var authorization: UNAuthorizationStatus = .notDetermined
    var storageError = false
    var notificationsError = false
    var isActive = true
    private var timer: Timer?
    private var lastTick: Date?
    private var shown: Set<String> = []
    private var scheduled: Set<String> = []
    private var lastPoseTime: Double = 0
    private var previewHistorySeeded = false
    private var schedulingGeneration = UUID()
    let scenario: String
    let uiTesting: Bool
    let coordinator = NotificationCoordinator()
    var settings: TemperatureSettings { engine.settings }
    var events: [MonitorEvent] { engine.events.sorted { $0.date > $1.date } }
    var temperatureFresh: Bool { latest?.isValid == true && now.timeIntervalSince(latest!.date) < 15 }
    var motionFresh: Bool { now.timeIntervalSince(poseDate) < 1 }
    var currentValue: Double? { temperatureFresh ? latest?.value : nil }
    var poseTime: Double { lastPoseTime }
    var activeTemperature: MonitorEvent? { engine.activeTemperature }
    var connected: Bool { temperatureFresh && motionFresh }
    var stateText: String {
        if !temperatureFresh { return "온도 확인 중" }
        guard let v = currentValue else { return "온도 확인 중" }
        if v > settings.high { return "설정 상한을 넘었어요" }
        if v < settings.low { return "설정 하한보다 낮아요" }
        return "설정 범위 안이에요"
    }
    var isWarning: Bool { !connected || activeTemperature != nil || (currentValue.map { $0 > settings.high || $0 < settings.low } ?? false) }

    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename: String
        switch scenario {
        case "launchFever": filename = "monitor-launch-fever-v1.json"
        case "nightFever": filename = "monitor-night-fever-v1.json"
        default: filename = "monitor-v1.json"
        }
        return dir.appendingPathComponent(filename)
    }
    struct Saved: Codable { let samples: [TemperatureSample]; let engine: AlertEngine; let shown: Set<String>; let scheduled: Set<String>; let previewHistorySeeded: Bool?; let nightFeverOnset:Date? }

    init() {
        let args = ProcessInfo.processInfo.arguments
        uiTesting = args.contains("--uitesting")
        scenario = args.firstIndex(of: "--scenario").flatMap { args.indices.contains($0+1) ? args[$0+1] : nil } ?? (uiTesting ? "steady":"launchFever")
        coordinator.store = self
        UNUserNotificationCenter.current().delegate = coordinator
        if args.contains("--reset") || scenario == "launchFever" { coordinator.cancelAll() }
        if scenario == "nightFever" { coordinator.cancelPending() }
        if scenario == "launchFever" {
            // Each new app process starts the presentation from a quiet baseline.
            // Keep preferences, but don't restore the previous run's active event or shown IDs.
            if !args.contains("--reset"), let data = try? Data(contentsOf: saveURL),
               let saved = try? JSONDecoder().decode(Saved.self, from: data) {
                engine = AlertEngine(settings: saved.engine.settings)
            }
            samples = stride(from: -86400.0, through: -60, by: 60).compactMap {
                Fixture.sample(at: startedAt.addingTimeInterval($0), start: startedAt, scenario: scenario, settings: settings)
            }
        } else if !args.contains("--reset"), let data = try? Data(contentsOf: saveURL), let saved = try? JSONDecoder().decode(Saved.self, from: data),
           scenario != "nightFever" || saved.nightFeverOnset == Fixture.nightFeverOnset(relativeTo:startedAt) {
            samples = saved.samples; engine = saved.engine; shown = saved.shown; scheduled = saved.scheduled; previewHistorySeeded = saved.previewHistorySeeded ?? false
            if scenario == "nightFever" {
                scheduled.removeAll()
                continueNightFeverHistory()
            } else { engine.resetSession(at: now) }
        } else if scenario == "nightFever" {
            seedNightFeverHistory()
        } else {
            // Development input is injected below the UI. All product views use the same domain models.
            samples = stride(from: -86400.0, through: -60, by: 60).compactMap { offset in Fixture.sample(at: now.addingTimeInterval(offset), start: now.addingTimeInterval(-90000)) }
        }
        if let i = args.firstIndex(of: "--tab"), args.indices.contains(i+1) { tab = Int(args[i+1]) ?? 0 }
        if !uiTesting && scenario != "nightFever" && !previewHistorySeeded { seedPreviewHistory() }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        Task { await refreshPermission() }
    }

    func tick() {
        guard isActive else { return }
        now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        if scenario != "motionGap" || elapsed < 4 { poseDate = now; lastPoseTime = max(0,now.timeIntervalSince(motionStartedAt)) }
        let sampleDate = Date(timeIntervalSince1970:floor(now.timeIntervalSince1970/5)*5)
        if lastTick == nil || sampleDate > lastTick! {
            lastTick = sampleDate
            if let sample = Fixture.sample(at: sampleDate, start: startedAt, scenario: scenario, settings: settings) {
                latest = sample; samples.append(sample); engine.receive(sample)
            } else {
                samples.append(.init(date:sampleDate,head:nil,torso:nil))
            }
            samples.removeAll { now.timeIntervalSince($0.date) > 7*86400 }
            engine.prune(before: now.addingTimeInterval(-7*86400))
            save()
        }
        let previousCount = engine.events.count
        engine.checkHealth(now: now, startedAt: startedAt, poseAt: poseDate)
        if engine.events.count != previousCount { save() }
        presentNextEvent()
    }

    func presentNextEvent() {
        guard popup == nil else { return }
        let priorities: [EventKind: Int] = [.connection: 0, .high: 1, .low: 1, .rise: 1, .motion: 2]
        if let event = events.filter({ $0.resolvedAt == nil && !shown.contains($0.id) && !scheduled.contains($0.id) }).sorted(by: { priorities[$0.kind, default: 3] < priorities[$1.kind, default: 3] }).first {
            shown.insert(event.id); popup = event; save()
        }
    }
    func acknowledge(_ event: MonitorEvent) { engine.acknowledge(event.id, at: now); popup = nil; save() }
    func showDetail(_ event: MonitorEvent) { acknowledge(event); tab = 1; selectedEvent = event }
    func configure(_ settings: TemperatureSettings) {
        guard settings.isValid else { return }
        engine.configure(settings, at: now)
        popup = nil; schedulingGeneration = UUID()
        coordinator.cancelPending(); scheduled.removeAll(); save()
    }
    func clearHistory() {
        samples.removeAll(); engine = AlertEngine(settings: settings); latest = nil
        shown.removeAll(); scheduled.removeAll(); popup = nil; selectedEvent = nil
        schedulingGeneration = UUID()
        coordinator.cancelAll(); lastTick = nil; startedAt = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970/5)*5); motionStartedAt=Date(); save(); tick()
    }
    func refreshPermission() async { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func requestPermission() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); notificationsError = false }
        catch { notificationsError = true }
        await refreshPermission()
    }
    func phaseChanged(_ phase: ScenePhase) {
        if phase == .background {
            isActive = false; save()
            Task { await scheduleFuture() }
        } else if phase == .active {
            isActive = true; schedulingGeneration = UUID(); coordinator.cancelPending()
            // Fill only known fixture samples; never fabricate missing input intervals.
            let end = Date()
            if let lastTick, end.timeIntervalSince(lastTick) > 5 {
                for offset in stride(from: 5.0, through: min(900, end.timeIntervalSince(lastTick)), by: 5) {
                    let date = lastTick.addingTimeInterval(offset)
                    if let sample = Fixture.sample(at: date, start: startedAt, scenario: scenario, settings: settings) { latest = sample; samples.append(sample); engine.receive(sample) }
                    else { samples.append(.init(date:date,head:nil,torso:nil)) }
                    engine.checkHealth(now:date,startedAt:startedAt,poseAt:scenario == "motionGap" ? min(date,startedAt.addingTimeInterval(4)) : date)
                    self.lastTick = date
                }
            }
            // Past events remain in history, without a burst of retroactive popups.
            shown.formUnion(engine.events.filter { $0.date < end }.map(\.id))
            scheduled.removeAll(); tick(); Task { await refreshPermission() }
        }
    }
    func scheduleFuture() async {
        guard authorization == .authorized || authorization == .provisional else { return }
        let generation = schedulingGeneration
        var forecast = engine
        let old = Set(forecast.events.map(\.id))
        let anchor = lastTick ?? now
        var future: [MonitorEvent] = []
        for offset in stride(from: 5.0, through: 900, by: 5) {
            let date = anchor.addingTimeInterval(offset)
            if let sample = Fixture.sample(at: date, start: startedAt, scenario: scenario, settings: settings) { forecast.receive(sample) }
            forecast.checkHealth(now:date,startedAt:startedAt,poseAt:scenario == "motionGap" ? min(date,startedAt.addingTimeInterval(4)) : date)
        }
        future = forecast.events.filter { !old.contains($0.id) && $0.date > Date() }.prefix(20).map { $0 }
        do {
            for var event in future {
                guard !isActive, generation == schedulingGeneration else { return }
                event.resolvedAt = nil; event.endReason = nil
                try await coordinator.schedule(event)
                guard !isActive, generation == schedulingGeneration else { coordinator.cancelPending(); return }
                scheduled.insert(event.id)
            }
            notificationsError = false; save()
        } catch { notificationsError = true }
    }
    func openNotification(_ id: String, payload: String?) {
        if let payload, let data = Data(base64Encoded:payload), let event = try? JSONDecoder().decode(MonitorEvent.self,from:data) {
            engine.recordDeliveredEvent(event)
        }
        if let event = engine.events.first(where: { $0.id == id }) { showDetail(event) }
    }

    private func seedNightFeverHistory() {
        let currentSampleDate=Date(timeIntervalSince1970:floor(now.timeIntervalSince1970/5)*5)
        let historyStart=currentSampleDate.addingTimeInterval(-86400)
        let replayStart=max(historyStart,Fixture.nightFeverOnset(relativeTo:startedAt).addingTimeInterval(-300))
        samples=[]
        engine=AlertEngine(settings:settings)
        // Keep the quiet part of the previous day compact, then replay the overnight event continuously.
        for timestamp in stride(from:historyStart.timeIntervalSince1970,to:replayStart.timeIntervalSince1970,by:60) {
            if let sample=Fixture.sample(at:Date(timeIntervalSince1970:timestamp),start:startedAt,scenario:scenario,settings:settings) {
                samples.append(sample)
            }
        }
        for timestamp in stride(from:replayStart.timeIntervalSince1970,to:currentSampleDate.timeIntervalSince1970,by:5) {
            if let sample=Fixture.sample(at:Date(timeIntervalSince1970:timestamp),start:startedAt,scenario:scenario,settings:settings) {
                samples.append(sample)
                engine.receive(sample)
            }
        }
        latest=samples.last
        lastTick=engine.lastValid
        shown.formUnion(engine.events.filter { $0.resolvedAt != nil }.map(\.id))
        previewHistorySeeded=true
        // tick() supplies the current reading and presents the still-active event once.
    }

    private func continueNightFeverHistory() {
        let currentSampleDate=Date(timeIntervalSince1970:floor(now.timeIntervalSince1970/5)*5)
        if let previous=engine.lastValid {
            for timestamp in stride(from:previous.addingTimeInterval(5).timeIntervalSince1970,to:currentSampleDate.timeIntervalSince1970,by:5) {
                if let sample=Fixture.sample(at:Date(timeIntervalSince1970:timestamp),start:startedAt,scenario:scenario,settings:settings) {
                    samples.append(sample)
                    engine.receive(sample)
                }
            }
        }
        latest=samples.last
        lastTick=engine.lastValid
    }

    private func seedPreviewHistory() {
        let cases:[(EventKind,Double,Double?,Double?)] = [
            (.rise,-24*60,37.2,36.7),
            (.high,-2*3600,38.2,nil),
            (.connection,-5*3600,nil,nil),
            (.rise,-19*3600,37.4,36.9)
        ]
        for (kind,offset,value,reference) in cases {
            let date=now.addingTimeInterval(offset)
            var event=MonitorEvent(kind:kind,date:date,value:value,thresholds:settings,referenceValue:reference)
            event.acknowledgedAt=date.addingTimeInterval(24)
            event.resolvedAt=date.addingTimeInterval(kind == .connection ? 120:600)
            event.endReason=kind == .connection ? "연결 복구":"온도 변화 확인 완료"
            engine.recordDeliveredEvent(event);shown.insert(event.id)
            guard let value else { continue }
            samples.removeAll { abs($0.date.timeIntervalSince(date)) <= 600 }
            for second in stride(from:-600.0,through:600,by:5) {
                let baseline=reference ?? 37.1
                let temperature:Double
                if second < -120 { temperature=baseline }
                else if second < 0 { temperature=baseline+(value-baseline)*(second+120)/120 }
                else { temperature=value+(37.1-value)*min(second/600,1) }
                samples.append(.init(date:date.addingTimeInterval(second),head:temperature-0.3,torso:temperature))
            }
        }
        samples.sort{$0.date < $1.date}
        previewHistorySeeded=true
    }

    private func save() {
        do { let data = try JSONEncoder().encode(Saved(samples: samples, engine: engine, shown: shown, scheduled: scheduled, previewHistorySeeded:previewHistorySeeded,nightFeverOnset:scenario == "nightFever" ? Fixture.nightFeverOnset(relativeTo:startedAt):nil)); try data.write(to: saveURL, options: .atomic); storageError = false }
        catch { storageError = true }
    }
}

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    weak var store: MonitorStore?
    func schedule(_ event: MonitorEvent) async throws {
        let content = UNMutableNotificationContent(); content.title = event.kind.title; content.body = event.detail; content.sound = .default
        content.userInfo = ["eventID": event.id, "eventData": try JSONEncoder().encode(event).base64EncodedString()]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, event.date.timeIntervalSinceNow), repeats: false)
        try await UNUserNotificationCenter.current().add(.init(identifier: event.id, content: content, trigger: trigger))
    }
    func cancelPending() { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    func cancelAll() { cancelPending(); UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["eventID"] as? String
        let payload = response.notification.request.content.userInfo["eventData"] as? String
        // UIKit's response completion also performs scene restoration; finish on the main actor.
        Task { @MainActor in
            if let id { store?.openNotification(id,payload:payload) }
            completionHandler()
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([]) }
    }
}
