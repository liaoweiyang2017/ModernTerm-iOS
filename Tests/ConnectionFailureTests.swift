import XCTest
import Citadel
import NIOCore
@testable import NIOSSH
@testable import ModerntermIOS

final class ConnectionFailureTests: XCTestCase {
  func testNegotiationFailureIsActionable() {
    let message = connectionFailureMessage(NIOSSHError.keyExchangeNegotiationFailure)
    XCTAssertTrue(message.contains("SSH negotiation"))
    XCTAssertTrue(message.contains("algorithms"))
    XCTAssertFalse(message.contains("error 1"))
  }
  func testAuthenticationAndTrustAreDistinct() {
    XCTAssertTrue(connectionFailureMessage(SSHClientError.allAuthenticationOptionsFailed).contains("Authentication"))
    XCTAssertTrue(connectionFailureMessage(SSHClientError.unsupportedPasswordAuthentication).contains("password authentication"))
    let trust = AppError.message("Server host key changed. Connection refused.")
    XCTAssertEqual(connectionFailureMessage(trust), trust.localizedDescription)
  }
  func testUnknownErrorsDoNotExposeOpaqueDiagnostics() {
    struct SensitiveError: Error, CustomStringConvertible {
      var description: String { "password=do-not-expose" }
    }
    let message = connectionFailureMessage(SensitiveError())
    XCTAssertTrue(message.contains("Unknown"))
    XCTAssertFalse(message.contains("do-not-expose"))
  }
  func testNetworkErrorsHaveSafeStageDescriptions() {
    XCTAssertTrue(connectionFailureMessage(SocketAddressError.failedToParseIPString("private-host")).contains("Address resolution"))
    XCTAssertTrue(connectionFailureMessage(ChannelError.connectTimeout(.seconds(1))).contains("TCP connection timed out"))
    XCTAssertFalse(connectionFailureMessage(SocketAddressError.failedToParseIPString("private-host")).contains("private-host"))
  }

}
