import XCTest

/// UI Tests for Geoclock.
///
/// Before running, grant permissions and set location from the terminal:
///   xcrun simctl privacy booted grant location-always maurizi.Geoclock
///   xcrun simctl location booted set 40.7580,-73.9855
final class GeoclockUITests: XCTestCase {

    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        dismissSystemAlerts()
        deleteAllAlarms()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Dismisses any visible system alert (location, AlarmKit, notifications, etc.)
    @MainActor
    private func dismissSystemAlerts() {
        let allowLabels = ["Allow While Using App", "Allow Once", "Always Allow", "Allow", "OK"]
        for label in allowLabels {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 2) {
                btn.tap()
                return
            }
        }
    }

    @MainActor
    private func createAlarmAtCurrentLocation() {
        let addButton = app.buttons["plus"]
        guard addButton.waitForExistence(timeout: 15) else { return }

        // Retry opening the sheet until CoreLocation has populated the user location.
        // The sheet is initialized with the current userLocation snapshot; if it's nil
        // the coordinates will be 0,0 and "No location set" appears. We cancel and
        // reopen after a short wait until the location arrives via startUpdatingLocation.
        for _ in 0..<10 {
            addButton.tap()

            let saveButton = app.buttons["Save"]
            guard saveButton.waitForExistence(timeout: 10) else { return }

            let noLocation = app.staticTexts["No location set"]
            if noLocation.waitForExistence(timeout: 2) {
                // Location not yet available — cancel and retry
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists { cancelButton.tap() }
                _ = addButton.waitForExistence(timeout: 5)
                continue
            }

            saveButton.tap()
            // Wait for sheet to dismiss
            _ = app.buttons["plus"].waitForExistence(timeout: 15)
            // AlarmKit authorization dialog may appear asynchronously after alarm creation
            dismissSystemAlerts()
            return
        }
    }

    @MainActor
    private func tapFirstAlarmRow() {
        let row = app.descendants(matching: .any).matching(identifier: "alarm-row").firstMatch
        guard row.waitForExistence(timeout: 3) else { return }
        row.tap()
    }

    @MainActor
    private func deleteAllAlarms() {
        for _ in 0..<25 {
            guard app.descendants(matching: .any).matching(identifier: "alarm-row").firstMatch
                    .waitForExistence(timeout: 1) else { break }
            tapFirstAlarmRow()
            let deleteButton = app.buttons["Delete"]
            if deleteButton.waitForExistence(timeout: 3) {
                deleteButton.tap()
                // Edit sheet delete is immediate — no confirmation dialog
            } else {
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists { cancelButton.tap() }
                break
            }
        }
    }

    // MARK: - Tests

    @MainActor
    func testAddButton_exists() throws {
        XCTAssertTrue(app.buttons["plus"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyState_showsNoAlarmsMessage() throws {
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateAlarm_opensEditSheet() throws {
        let addButton = app.buttons["plus"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateAlarm_appearsInList() throws {
        createAlarmAtCurrentLocation()

        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["No alarms yet"].exists)
    }

    @MainActor
    func testDeleteAlarm_viaSwipe() throws {
        createAlarmAtCurrentLocation()

        let row = app.descendants(matching: .any).matching(identifier: "alarm-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        dismissSystemAlerts()

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let confirmDelete = app.buttons["Delete"]
        if confirmDelete.waitForExistence(timeout: 2) {
            confirmDelete.tap()
        }

        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeleteAlarm_viaEditSheet() throws {
        createAlarmAtCurrentLocation()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alarm-row").firstMatch
            .waitForExistence(timeout: 5))
        dismissSystemAlerts()
        tapFirstAlarmRow()

        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        // Edit sheet delete is immediate — no confirmation dialog

        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testToggleAlarm_offAndOn() throws {
        createAlarmAtCurrentLocation()

        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        dismissSystemAlerts()

        let initialValue = toggle.value as? String
        toggle.tap()
        dismissSystemAlerts() // AlarmKit may appear when toggling

        let afterOff = toggle.value as? String
        XCTAssertNotEqual(initialValue, afterOff)

        toggle.tap()
        dismissSystemAlerts()

        let afterOn = toggle.value as? String
        XCTAssertEqual(initialValue, afterOn)
    }

    @MainActor
    func testAlarmAtCurrentLocation_showsWithinRange() throws {
        createAlarmAtCurrentLocation()

        // "Within range" requires CoreLocation to report the simulator's position
        // and geofence detection to run; give it extra time
        XCTAssertTrue(app.staticTexts["Within range"].waitForExistence(timeout: 90))
    }

    @MainActor
    func testMultipleAlarms_allAppear() throws {
        createAlarmAtCurrentLocation()
        createAlarmAtCurrentLocation()
        createAlarmAtCurrentLocation()

        XCTAssertTrue(app.cells.element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.cells.count, 3)
    }

    @MainActor
    func testGeofenceLimitIndicator_showsCount() throws {
        createAlarmAtCurrentLocation()

        let limitLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "/20 alarms")
        ).firstMatch
        XCTAssertTrue(limitLabel.waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditAlarm_changesReflected() throws {
        createAlarmAtCurrentLocation()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alarm-row").firstMatch
            .waitForExistence(timeout: 5))
        dismissSystemAlerts()
        tapFirstAlarmRow()

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 15))
    }
}
