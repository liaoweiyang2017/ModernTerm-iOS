import XCTest

final class TermTransferUITests: XCTestCase {
  func testExternalFileColdAndWarmOpen() throws {
    let source = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "attachment", withExtension: "term"))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("received.term")
    try Data(contentsOf: source).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let app = XCUIApplication()
    app.launch()
    app.terminate()
    XCUIDevice.shared.system.open(url)
    let unlock = app.secureTextFields["File password"]
    XCTAssertTrue(unlock.waitForExistence(timeout: 8), app.debugDescription)
    unlock.tap()
    unlock.typeText("incorrect-password")
    app.buttons["Unlock and continue"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label == 'Wrong password or damaged file.'")
      ).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    unlock.tap()
    unlock.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: "incorrect-password".count))
    unlock.typeText("attachment-test-2026")
    app.buttons["Unlock and continue"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Import preview'")).firstMatch
        .waitForExistence(timeout: 10), app.debugDescription)
    app.buttons["Done"].tap()
    XCUIDevice.shared.system.open(url)
    XCTAssertTrue(unlock.waitForExistence(timeout: 8), app.debugDescription)
    app.buttons["Cancel import"].tap()
    app.buttons["Done"].tap()
  }

  func testShortPasswordShowsVisibleErrorAndKeepsInput() throws {
    let app = XCUIApplication()
    app.launch()
    app.buttons["Add server"].tap()
    app.textFields["Host"].tap()
    app.textFields["Host"].typeText("validation.invalid")
    app.textFields["Username"].tap()
    app.textFields["Username"].typeText("test")
    app.buttons["Save"].tap()
    app.buttons["SSH transfer"].tap()
    app.buttons["Select all"].tap()
    for label in ["File password (12+ characters)", "Repeat file password"] {
      let field = app.secureTextFields[label]
      for _ in 0..<12 {
        if field.isHittable { break }
        app.swipeUp()
      }
      field.tap()
      field.typeText("12345678")
    }
    let button = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Export ' AND label ENDSWITH ' connections'")
    ).firstMatch
    for _ in 0..<4 {
      if button.isHittable { break }
      app.swipeUp()
    }
    button.tap()
    XCTAssertTrue(app.alerts["Export failed"].waitForExistence(timeout: 5))
    if app.alerts["Export failed"].exists {
      XCTAssertTrue(
        app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS 'at least 12'"))
          .firstMatch.exists)
      app.alerts.buttons["OK"].tap()
      XCTAssertTrue(button.isEnabled, "Inputs must remain available to correct after failure")
    }
  }

  func testShareOpensNativeAttachmentSheet() throws {
    let app = XCUIApplication()
    app.launch()
    app.buttons["Add server"].tap()
    app.textFields["Host"].tap()
    app.textFields["Host"].typeText("share.invalid")
    app.textFields["Username"].tap()
    app.textFields["Username"].typeText("test")
    app.buttons["Save"].tap()
    app.buttons["SSH transfer"].tap()
    app.buttons["Select all"].tap()
    for label in ["File password (12+ characters)", "Repeat file password"] {
      let field = app.secureTextFields[label]
      for _ in 0..<12 {
        if field.isHittable { break }
        app.swipeUp()
      }
      field.tap()
      field.typeText("sharing-test-2026")
    }
    let button = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Share ' AND label ENDSWITH ' connections'")
    ).firstMatch
    for _ in 0..<5 {
      if button.isHittable { break }
      app.swipeUp()
    }
    button.tap()
    let filename = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS 'ModernTerm-connections'")
    ).firstMatch
    XCTAssertTrue(filename.waitForExistence(timeout: 15), app.debugDescription)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Encrypted file share sheet"
    shot.lifetime = .keepAlways
    add(shot)
    if app.buttons["Close"].exists {
      app.buttons["Close"].firstMatch.tap()
    } else {
      app.swipeDown()
    }
  }

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
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label ==[c] %@", "Export saved SSH connections")
      ).firstMatch.waitForExistence(timeout: 5))
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
    let save = app.buttons.matching(NSPredicate(format: "label == 'Save' OR label == 'Move'"))
      .firstMatch
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
    // A fresh iOS18 picker opens an empty Recents tab; browse the save destination.
    if !file.waitForExistence(timeout: 2) {
      let browse = app.buttons["Browse"].firstMatch
      if browse.exists { browse.tap() }
      if !file.waitForExistence(timeout: 2) {
        let local = app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if local.exists { local.tap() }
      }
    }
    XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription)
    file.tap()
    if app.buttons["Open"].exists { app.buttons["Open"].tap() }
    let unlock = app.secureTextFields["File password"]
    XCTAssertTrue(unlock.waitForExistence(timeout: 5), app.debugDescription)
    unlock.tap()
    unlock.typeText("test-transfer-2026")
    app.buttons["Unlock and continue"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Import preview")).firstMatch
        .waitForExistence(timeout: 10), app.debugDescription)
    let preview = XCTAttachment(screenshot: app.screenshot())
    preview.name = "iOS import preview"
    preview.lifetime = .keepAlways
    add(preview)
    app.buttons["Done"].tap()
  }
}
