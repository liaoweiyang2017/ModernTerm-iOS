import XCTest

final class TermTransferUITests: XCTestCase {
  func testSelectionPasswordAndNativeExporter() throws {
    let app = XCUIApplication()
    app.launch()
    for n in 1...2 {
      app.buttons["Add server"].tap()
      let name = app.textFields["Name"]
      XCTAssertTrue(name.waitForExistence(timeout: 5))
      name.tap()
      name.typeText("Transfer UI \(n)")
      app.textFields["Host"].tap()
      app.textFields["Host"].typeText("fixture\(n).invalid")
      app.textFields["Username"].tap()
      app.textFields["Username"].typeText("test@group")
      app.buttons["Save"].tap()
    }
    app.buttons["SSH transfer"].tap()
    XCTAssertTrue(app.staticTexts["Export saved SSH connections"].waitForExistence(timeout: 5))
    app.buttons["Select all"].tap()
    let password = app.secureTextFields["File password (12+ characters)"]
    for _ in 0..<5 {
      if password.isHittable { break }
      app.swipeUp()
    }
    password.tap()
    password.typeText("test-transfer-2026")
    let repeatPassword = app.secureTextFields["Repeat file password"]
    for _ in 0..<5 {
      if repeatPassword.isHittable { break }
      app.swipeUp()
    }
    repeatPassword.tap()
    repeatPassword.typeText("test-transfer-2026")
    let export = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Export ' AND label ENDSWITH ' connections'")
    ).firstMatch
    for _ in 0..<5 {
      if export.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(export.isEnabled)
    export.tap()
    let save = app.buttons["Save"]
    XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "iOS encrypted file exporter"
    shot.lifetime = .keepAlways
    add(shot)
    save.tap()
    if app.buttons["Keep Both"].waitForExistence(timeout: 2) { app.buttons["Keep Both"].tap() }
    XCTAssertTrue(app.navigationBars["SSH transfer"].waitForExistence(timeout: 5))
    let choose = app.buttons["Choose .term files…"]
    for _ in 0..<4 {
      if choose.isHittable { break }
      app.swipeUp()
    }
    choose.tap()
    let file = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS 'ModernTerm-connections'")
    ).firstMatch
    XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription)
    file.tap()
    if app.buttons["Open"].exists { app.buttons["Open"].tap() }
    let unlock = app.secureTextFields["File password"]
    XCTAssertTrue(unlock.waitForExistence(timeout: 5), app.debugDescription)
    unlock.tap()
    unlock.typeText("test-transfer-2026")
    app.buttons["Unlock and continue"].tap()
    XCTAssertTrue(
      app.staticTexts["Import preview"].waitForExistence(timeout: 10), app.debugDescription)
    let preview = XCTAttachment(screenshot: app.screenshot())
    preview.name = "iOS import preview"
    preview.lifetime = .keepAlways
    add(preview)
    app.buttons["Done"].tap()
  }
}
