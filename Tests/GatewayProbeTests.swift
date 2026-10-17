import XCTest
import Citadel
import NIOSSH
import NIOCore
@testable import ModerntermIOS

// Opt-in pre-authentication probe: never offers credentials or trusts the remote key.
private final class NoCredentials: NIOSSHClientUserAuthenticationDelegate {
  func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
    nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
    nextChallengePromise.fail(AppError.message("PROBE_AUTH_BLOCKED"))
  }
}
final class GatewayProbeTests: XCTestCase {
  func testGatewayReachesHostValidation() async throws {
    struct Probe: Decodable { let host: String }
    guard let url = Bundle(for: Self.self).url(forResource: "GatewayProbe", withExtension: "json") else {
      throw XCTSkip("Run Scripts/gateway_probe.py HOST")
    }
    let probe = try JSONDecoder().decode(Probe.self, from: Data(contentsOf: url))
    let validator = HostValidator(host: "probe") { _, _, promise in
      promise.fail(AppError.message("PROBE_HOST_REACHED"))
    }
    let algorithms = SSHCompatibility.algorithms
    do {
      let client = try await SSHClient.connect(host: probe.host,
        authenticationMethod: .custom(NoCredentials()), hostKeyValidator: .custom(validator),
        reconnect: .never, algorithms: algorithms, connectTimeout: .seconds(10))
      try await client.close()
      XCTFail("Probe must stop before authentication")
    } catch {

      XCTAssertEqual(error.localizedDescription, "PROBE_HOST_REACHED")
    }
  }
}
