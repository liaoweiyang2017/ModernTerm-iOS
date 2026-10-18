import SwiftTerm
import UIKit

/// Request focus only after UIKit has attached the terminal to a window.
/// Explicit show/hide actions also work when a host container hides its keyboard.
final class TerminalInputView: TerminalView {
  private var wantsKeyboard = false

  func showKeyboard(force: Bool = true) {
    wantsKeyboard = true
    if force && isFirstResponder { resignFirstResponder() }
    requestFocusWhenAttached()
  }

  func hideKeyboard() {
    wantsKeyboard = false
    resignFirstResponder()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { requestFocusWhenAttached() } else { resignFirstResponder() }
  }

  private func requestFocusWhenAttached() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.wantsKeyboard, self.window != nil, !self.isFirstResponder else { return }
      self.becomeFirstResponder()
    }
  }
}
