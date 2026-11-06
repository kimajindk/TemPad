import XCTest

final class TemPadUITests:XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    func launch(_ scenario:String="steady",tab:String="0")->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitesting","--reset","--scenario",scenario,"--tab",tab];app.launch();return app
    }
    func testHomeNavigationAndExpandedMonitor() {
        let app=launch()
        XCTAssertTrue(app.otherElements["thermalView"].waitForExistence(timeout:10))
        for word in ["시뮬레이션","모의","데모"] {XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@",word)).firstMatch.exists)}
        app.buttons["expandThermal"].tap()
        XCTAssertTrue(app.buttons["closeExpanded"].waitForExistence(timeout:3))
        app.buttons["period24"].tap()
        XCTAssertTrue(app.otherElements["temperatureChart"].exists)
        app.buttons["closeExpanded"].tap()
        app.buttons["tab1"].tap()
        XCTAssertTrue(app.staticTexts["알림 기록"].exists)
        app.buttons["tab2"].tap()
        XCTAssertTrue(app.buttons["saveThresholds"].exists)
    }
    func testGridSelectionFiltersMarkersAndTracking() {
        let app=launch()
        let monitor=app.otherElements["thermalView"]
        monitor.coordinate(withNormalizedOffset:CGVector(dx:0.46,dy:0.53)).tap()
        XCTAssertEqual(app.staticTexts["selectedPointTitle"].label,"선택 지점")
        app.buttons["expandThermal"].tap()
        XCTAssertEqual(app.staticTexts["trackingPointTitle"].label,"선택 지점 온도")
        XCTAssertTrue(app.otherElements["temperatureChart"].label.contains("선택 지점"))
        app.otherElements["thermalView"].coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.95)).tap()
        XCTAssertEqual(app.staticTexts["trackingPointTitle"].label,"대표 보정 온도")
    }
    func testHighAlertAcknowledgementAndHistory() {
        let app=launch("high")
        XCTAssertTrue(app.buttons["acknowledgeAlert"].waitForExistence(timeout:18))
        app.buttons["viewAlertRecord"].tap()
        XCTAssertTrue(app.staticTexts["알림 상세"].waitForExistence(timeout:5))
        app.buttons["닫기"].tap()
        app.buttons["tab1"].tap()
        XCTAssertTrue(app.buttons["event-high"].waitForExistence(timeout:4))
        XCTAssertFalse(app.buttons["acknowledgeAlert"].exists)
    }
    func testSettingsPersistAfterRelaunch() {
        let app=launch(tab:"2")
        app.buttons["상한 온도 높이기"].tap();app.buttons["saveThresholds"].tap()
        XCTAssertEqual(app.buttons["saveThresholds"].label,"저장했어요")
        app.terminate();app.launchArguments=["--uitesting","--tab","2"];app.launch()
        XCTAssertTrue(app.staticTexts["38.1°"].waitForExistence(timeout:5))
    }
    func testLowAlertAndSingleAcknowledgement() {
        let app=launch("low")
        XCTAssertTrue(app.buttons["acknowledgeAlert"].waitForExistence(timeout:18))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","설정 하한")).firstMatch.exists)
        app.buttons["acknowledgeAlert"].tap()
        app.buttons["tab1"].tap()
        XCTAssertEqual(app.buttons.matching(identifier:"event-low").count,1)
        XCTAssertFalse(app.buttons["acknowledgeAlert"].exists)
    }
    func testDisconnectedHidesStaleTemperature() {
        let app=launch("disconnected")
        XCTAssertTrue(app.buttons["acknowledgeAlert"].waitForExistence(timeout:22))
        XCTAssertTrue(app.staticTexts["온도 정보를 받지 못했어요"].exists)
        app.buttons["acknowledgeAlert"].tap()
        XCTAssertEqual(app.staticTexts["currentTemperature"].label,"--.-")
        XCTAssertTrue(app.otherElements["thermalView"].label.contains("새로운 온도"))
    }
    func testBackgroundNotificationOpensEvent() {
        let app=launch("delayedHigh",tab:"2")
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let permission=app.buttons["notificationPermission"]
        if permission.label == "알림 켜기" {
            permission.tap()
            let allow=springboard.buttons.matching(NSPredicate(format:"label == 'Allow' OR label == '허용'")).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout:5));allow.tap()
        }
        XCTAssertTrue(app.staticTexts["알림이 켜져 있어요"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home)
        let notification=springboard.staticTexts["온도를 확인해 주세요"]
        XCTAssertTrue(notification.waitForExistence(timeout:50))
        notification.tap()
        XCTAssertTrue(app.staticTexts["알림 상세"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["acknowledgeAlert"].exists)
    }
}
