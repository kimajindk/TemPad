import XCTest
@testable import TemPadCore

final class MonitoringTests:XCTestCase {
    let start=Date(timeIntervalSince1970:1_800_000_000)
    func sample(_ second:Double,_ value:Double?)->TemperatureSample {
        .init(date:start.addingTimeInterval(second),head:value.map{$0-0.3},torso:value)
    }
    func testFirstValidThresholdCrossingAlertsWithoutWaiting() {
        var engine=AlertEngine()
        engine.receive(sample(0,38.2))
        XCTAssertEqual(engine.events.count,1)
        XCTAssertEqual(engine.events[0].kind,.high)
        engine.acknowledge(engine.events[0].id,at:start)
        for i in 1...10 { engine.receive(sample(Double(i*5),38.2)) }
        XCTAssertEqual(engine.events.count,1)
        XCTAssertNotNil(engine.events[0].acknowledgedAt)
        XCTAssertNil(engine.events[0].resolvedAt)
    }
    func testThresholdBoundaryDoesNotTriggerAbsoluteAlert() {
        var engine=AlertEngine()
        for i in 0...5 { engine.receive(sample(Double(i*5),38)) }
        XCTAssertTrue(engine.events.isEmpty)
        engine.receive(sample(30,38.1))
        XCTAssertEqual(engine.events.first?.kind,.high)
    }
    func testHalfDegreeRiseAlertsBelowAbsoluteThreshold() {
        var engine=AlertEngine()
        engine.receive(sample(0,37.0));engine.receive(sample(5,37.3))
        XCTAssertTrue(engine.events.isEmpty)
        engine.receive(sample(10,37.5))
        XCTAssertEqual(engine.events.first?.kind,.rise)
        XCTAssertEqual(engine.events.first?.referenceValue,37.0)
        engine.receive(sample(15,37.6))
        XCTAssertEqual(engine.events.count,1)
    }
    func testAbsoluteThresholdTakesPriorityOverRelativeRise() {
        var engine=AlertEngine()
        engine.receive(sample(0,37.0));engine.receive(sample(5,38.2))
        XCTAssertEqual(engine.events.map(\.kind),[.high])
    }
    func testRecoveryRequiresThreeInnerRangeReadings() {
        var engine=AlertEngine()
        engine.receive(sample(0,38.2))
        for i in 1...3 { engine.receive(sample(Double(i*5),37.9)) }
        XCTAssertNil(engine.events[0].resolvedAt)
        for i in 4...6 { engine.receive(sample(Double(i*5),37.7)) }
        XCTAssertNotNil(engine.events[0].resolvedAt)
        engine.receive(sample(35,38.2))
        XCTAssertEqual(engine.events.count,2)
    }
    func testInvalidAndOldReadingsDoNotCreateAlerts() {
        var engine=AlertEngine()
        engine.receive(sample(5,37));engine.receive(sample(10,nil))
        engine.receive(sample(0,39));engine.receive(sample(5,39))
        XCTAssertTrue(engine.events.isEmpty)
    }
    func testGapDoesNotCountAsTemperatureRise() {
        var engine=AlertEngine()
        engine.receive(sample(0,37));engine.receive(sample(30,37.6))
        XCTAssertTrue(engine.events.isEmpty)
    }
    func testConnectionAndMotionAreCombined() {
        var engine=AlertEngine()
        engine.receive(sample(0,37))
        engine.checkHealth(now:start.addingTimeInterval(5),startedAt:start,poseAt:start)
        engine.checkHealth(now:start.addingTimeInterval(15),startedAt:start,poseAt:start)
        XCTAssertEqual(engine.events.map(\.kind),[.motion,.connection])
        XCTAssertNotNil(engine.events[0].resolvedAt)
    }
    func testSettingsPreserveHistoricalThresholds() {
        var engine=AlertEngine()
        engine.receive(sample(0,38.2))
        engine.configure(.init(low:35,high:39),at:start.addingTimeInterval(5))
        XCTAssertEqual(engine.events[0].thresholds.high,38)
        XCTAssertEqual(engine.events[0].endReason,"기준 변경")
    }
    func testNotificationRestoreIsIdempotent() throws {
        var engine=AlertEngine()
        let event=MonitorEvent(kind:.rise,date:start,value:37.5,thresholds:.init(),referenceValue:37)
        engine.recordDeliveredEvent(event);engine.acknowledge(event.id,at:start)
        engine.recordDeliveredEvent(event)
        XCTAssertEqual(engine.events.count,1)
        let restored=try JSONDecoder().decode(AlertEngine.self,from:JSONEncoder().encode(engine))
        XCTAssertEqual(restored.events,engine.events)
        XCTAssertNotNil(restored.events[0].acknowledgedAt)
    }
    func testGridSelectionFollowsBreathingCoordinates() {
        XCTAssertEqual(Set(ThermalGrid.points.map(\.id)).count,1560)
        let targets=[ThermalPoint(column:11,row:13),.init(column:23,row:17),.init(column:36,row:21)]
        for time in [0.0,2.4,4.8] {
            for point in targets {
                let p=ThermalProjection.position(point.position,time:time)
                XCTAssertEqual(ThermalGrid.nearest(to:p,time:time),point)
            }
        }
    }
    func testGentleBreathingAndSmallGesturesPreserveOriginalPose() {
        let chest=Point2(0.53,0.40)
        XCTAssertGreaterThan(abs(BodyMotion.transform(chest,time:2.4).y-chest.y),0.001)
        for point in ThermalGrid.overviewPoints {
            for time in stride(from:0.0,through:10,by:0.5) {
                let p=BodyMotion.transform(point.position,time:time)
                XCTAssertLessThan(hypot(p.x-point.position.x,p.y-point.position.y),0.02)
            }
        }
        XCTAssertLessThan(abs(BodyMotion.transform(chest,time:2.4,reduced:true).y-chest.y),0.001)
    }
    func testPointTemperatureUsesSelectedCoordinate() {
        let reading=sample(0,37.1)
        let a=ThermalPoint(column:11,row:13),b=ThermalPoint(column:29,row:16)
        XCTAssertNotEqual(a.temperature(in:reading),b.temperature(in:reading))
        XCTAssertNil(a.temperature(in:sample(0,nil)))
    }
}
