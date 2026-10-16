import SwiftUI
import XCTest

@testable import ModerntermIOS

@MainActor final class TerminalKeyboardTests: XCTestCase {
  func testTerminalGetsInputFocusWhenShown() async throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first(where: { $0.isKeyWindow })
    var server = Server()
    server.host = "keyboard-test.invalid"
    server.user = "test"
    let session = SSHSession(server: server)
    session.connected = true  // Presentation fixture only: no network connection or credentials.
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(rootView: TerminalSurface(session: session))
    window.makeKeyAndVisible()
    defer {
      session.terminal.resignFirstResponder()
      window.isHidden = true
      previous?.makeKey()
    }
    for _ in 0..<10 {
      if session.terminal.isFirstResponder { break }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertNotNil(session.terminal.window)
    XCTAssertTrue(session.terminal.canBecomeFirstResponder)
    XCTAssertTrue(
      session.terminal.isFirstResponder,
      "A visible terminal must request keyboard focus after joining the window")
  }
  func testHideReopenAndDetachedViewCannotStealFocus() async throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first(where: { $0.isKeyWindow })
    let session = SSHSession(server: Server())
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(rootView: TerminalSurface(session: session))
    window.makeKeyAndVisible()
    defer {
      session.terminal.hideKeyboard()
      window.isHidden = true
      previous?.makeKey()
    }
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertTrue(session.terminal.isFirstResponder)
    session.terminal.hideKeyboard()
    session.status = "Refresh does not request focus"
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertFalse(session.terminal.isFirstResponder)
    session.terminal.showKeyboard()
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertTrue(session.terminal.isFirstResponder)
    session.terminal.showKeyboard()
    window.rootViewController = UIViewController()
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertNil(session.terminal.window)
    XCTAssertFalse(session.terminal.isFirstResponder)
  }

}
