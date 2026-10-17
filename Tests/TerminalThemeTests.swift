import SwiftUI
import XCTest
@testable import ModerntermIOS

@MainActor final class TerminalThemeTests: XCTestCase {
  func testAutoPaletteFollowsLightDarkAndReattachment() async throws {
    let defaults = UserDefaults.standard
    let previousPalette = defaults.object(forKey: "palette")
    defaults.set("ubuntu-neo", forKey: "palette")
    defer { defaults.set(previousPalette, forKey: "palette") }
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousWindow = scene.windows.first(where: { $0.isKeyWindow })
    let window = UIWindow(windowScene: scene)
    let session = SSHSession(server: Server())
    let host = UIHostingController(rootView: TerminalSurface(session: session))
    window.rootViewController = host
    window.overrideUserInterfaceStyle = .dark
    window.makeKeyAndVisible()
    defer {
      session.terminal.hideKeyboard()
      window.isHidden = true
      previousWindow?.makeKey()
    }
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(session.terminal.nativeBackgroundColor, UIColor(hex: "#300A24"))
    window.overrideUserInterfaceStyle = .light
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(session.terminal.nativeBackgroundColor, UIColor(hex: "#F8F8F8"))
    XCTAssertEqual(session.terminal.nativeForegroundColor, UIColor(hex: "#121212"))
    window.overrideUserInterfaceStyle = .dark
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(session.terminal.nativeBackgroundColor, UIColor(hex: "#300A24"))
    window.rootViewController = UIViewController()
    window.overrideUserInterfaceStyle = .light
    window.rootViewController = UIHostingController(rootView: TerminalSurface(session: session))
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(session.terminal.nativeBackgroundColor, UIColor(hex: "#F8F8F8"))
  }
}
