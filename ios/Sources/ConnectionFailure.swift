import Foundation
import Citadel
import NIOCore
import NIOSSH

// Never render arbitrary SSH diagnostics: peers may include sensitive or untrusted text.
func connectionFailureMessage(_ error: Error) -> String {
  if let error = error as? AppError { return error.localizedDescription }
  if let error = error as? NIOSSHError {
    switch error.type {
    case .keyExchangeNegotiationFailure:
      return "SSH negotiation failed: client and server have no compatible algorithms. Check the server's host-key and encryption support. (keyExchangeNegotiationFailure)"
    case .invalidExchangeHashSignature, .invalidHostKeyForKeyExchange:
      return "SSH host verification failed: the server signature does not match the negotiated algorithm or key. Connection refused. (\(error.type))"
    case .unknownPublicKey, .unknownSignature:
      return "SSH negotiation failed: the server used an unsupported key or signature. (\(error.type))"
    case .channelSetupRejected:
      return "SSH channel rejected: the server does not permit this terminal or subsystem. (channelSetupRejected)"
    case .tcpShutdown:
      return "The server closed the SSH connection. Check network access and retry. (tcpShutdown)"
    default:
      return "SSH protocol error; the exact failure stage is unknown. (\(error.type))"
    }
  }
  if let error = error as? SSHClientError {
    switch error {
    case .allAuthenticationOptionsFailed:
      return "Authentication failed. Check your username, credentials and the server's permitted login methods."
    case .unsupportedPasswordAuthentication:
      return "Authentication failed: the server does not offer password authentication."
    case .unsupportedPrivateKeyAuthentication:
      return "Authentication failed: the server does not offer public-key authentication."
    case .unsupportedHostBasedAuthentication:
      return "Authentication failed: host-based authentication is unsupported."
    case .channelCreationFailed:
      return "SSH channel creation failed. Check whether the server permits this operation."
    }
  }
  if error is AuthenticationFailed { return "Authentication failed. Check your credentials and server login policy." }
  if error is SocketAddressError || error is SocketAddressError.UnknownHost { return "Address resolution failed. Check the host name and network connection." }
  if let error = error as? ChannelError, case .connectTimeout = error {
    return "TCP connection timed out. Check the host, port and network access."
  }
  if error is IOError { return "Network I/O failed. Check the host, port and network access." }
  if error is CancellationError { return "Connection cancelled." }
  return "Unknown connection failure. Technical type: \(String(describing: type(of: error)))."
}
