//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
import NIOCore
import NIOEmbedded
@testable import NIOSSH
import XCTest

final class SSHConfigurationCertificateTests: XCTestCase {
    
    // MARK: - Client Configuration Tests
    
    func testClientConfigurationTrustedHostCAKeys() throws {
        // Test that client configuration properly stores trusted host CA keys
        let caKey1 = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let caKey2 = NIOSSHPrivateKey(p384Key: .init()).publicKey
        let caKey3 = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        
        var config = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestAcceptAllHostKeysDelegate()
        )
        
        // Initially empty
        XCTAssertEqual(config.trustedHostCAKeys.count, 0)
        
        // Add single CA
        config.trustedHostCAKeys = [caKey1]
        XCTAssertEqual(config.trustedHostCAKeys.count, 1)
        XCTAssertEqual(config.trustedHostCAKeys[0], caKey1)
        
        // Add multiple CAs
        config.trustedHostCAKeys = [caKey1, caKey2, caKey3]
        XCTAssertEqual(config.trustedHostCAKeys.count, 3)
        XCTAssertEqual(config.trustedHostCAKeys[0], caKey1)
        XCTAssertEqual(config.trustedHostCAKeys[1], caKey2)
        XCTAssertEqual(config.trustedHostCAKeys[2], caKey3)
        
        // Clear CAs
        config.trustedHostCAKeys = []
        XCTAssertEqual(config.trustedHostCAKeys.count, 0)
    }
    
    func testClientConfigurationHostname() throws {
        // Test that client configuration properly stores hostname
        var config = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestAcceptAllHostKeysDelegate()
        )
        
        // Initially nil
        XCTAssertNil(config.hostname)
        
        // Set hostname
        config.hostname = "example.com"
        XCTAssertEqual(config.hostname, "example.com")
        
        // Change hostname
        config.hostname = "localhost"
        XCTAssertEqual(config.hostname, "localhost")
        
        // Clear hostname
        config.hostname = nil
        XCTAssertNil(config.hostname)
    }
    
    func testClientConfigurationWithCertificateDelegate() throws {
        // Test that client configuration works with certificate-aware delegate
        class CertAwareDelegate: NIOSSHClientServerAuthenticationDelegate {
            var validateHostKeyCalled = false
            var validateHostCertificateCalled = false
            
            func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
                self.validateHostKeyCalled = true
                validationCompletePromise.succeed(())
            }
            
            func validateHostCertificate(hostKey: NIOSSHPublicKey, certifiedKey: NIOSSHCertifiedPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
                self.validateHostCertificateCalled = true
                validationCompletePromise.succeed(())
            }
        }
        
        let delegate = CertAwareDelegate()
        let caKey = NIOSSHPrivateKey(p256Key: .init()).publicKey
        
        var config = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: delegate
        )
        config.trustedHostCAKeys = [caKey]
        config.hostname = "test.example.com"
        
        // Verify configuration is set correctly
        XCTAssertEqual(config.trustedHostCAKeys.count, 1)
        XCTAssertEqual(config.hostname, "test.example.com")
        // Verify configuration is set with the delegate
        XCTAssertNotNil(config.serverAuthDelegate)
    }
    
    // MARK: - Server Configuration Tests
    
    func testServerConfigurationTrustedUserCAKeys() throws {
        // Test that server configuration properly stores trusted user CA keys
        let caKey1 = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let caKey2 = NIOSSHPrivateKey(p384Key: .init()).publicKey
        let caKey3 = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        
        var config = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        
        // Initially empty
        XCTAssertEqual(config.trustedUserCAKeys.count, 0)
        
        // Add single CA
        config.trustedUserCAKeys = [caKey1]
        XCTAssertEqual(config.trustedUserCAKeys.count, 1)
        XCTAssertEqual(config.trustedUserCAKeys[0], caKey1)
        
        // Add multiple CAs
        config.trustedUserCAKeys = [caKey1, caKey2, caKey3]
        XCTAssertEqual(config.trustedUserCAKeys.count, 3)
        XCTAssertEqual(config.trustedUserCAKeys[0], caKey1)
        XCTAssertEqual(config.trustedUserCAKeys[1], caKey2)
        XCTAssertEqual(config.trustedUserCAKeys[2], caKey3)
        
        // Clear CAs
        config.trustedUserCAKeys = []
        XCTAssertEqual(config.trustedUserCAKeys.count, 0)
    }
    
    func testServerConfigurationWithCertificateDelegate() throws {
        // Test that server configuration works with certificate-aware delegate
        class CertAwareDelegate: NIOSSHServerUserAuthenticationDelegate {
            var receivedCertificate: NIOSSHCertifiedPublicKey?
            
            var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
                [.publicKey]
            }
            
            func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
                if case .publicKey(let keyInfo) = request.request {
                    self.receivedCertificate = keyInfo.certifiedKey
                }
                responsePromise.succeed(.success)
            }
        }
        
        let delegate = CertAwareDelegate()
        let caKey = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        
        var config = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: delegate
        )
        config.trustedUserCAKeys = [caKey]
        
        // Verify configuration is set correctly
        XCTAssertEqual(config.trustedUserCAKeys.count, 1)
        // Verify configuration is set with the delegate
        XCTAssertNotNil(config.userAuthDelegate)
    }
    
    // MARK: - Configuration Interaction Tests
    
    func testClientServerConfigurationInteraction() throws {
        // Test that client and server configurations work together
        let caKey = NIOSSHPrivateKey(p384Key: .init()).publicKey
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        let userKey = NIOSSHPrivateKey(ed25519Key: .init())
        
        // Client configuration
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: SimplePasswordDelegate(username: "testuser", password: "testpass"),
            serverAuthDelegate: AcceptAllHostKeysDelegate()
        )
        clientConfig.trustedHostCAKeys = [caKey]
        clientConfig.hostname = "localhost"
        
        // Server configuration
        var serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        serverConfig.trustedUserCAKeys = [caKey]
        
        // Verify configurations are independent
        XCTAssertEqual(clientConfig.trustedHostCAKeys.count, 1)
        XCTAssertEqual(serverConfig.trustedUserCAKeys.count, 1)
        XCTAssertNotNil(clientConfig.hostname)
        
        // Configurations use the same CA key but for different purposes
        XCTAssertEqual(clientConfig.trustedHostCAKeys[0], caKey)
        XCTAssertEqual(serverConfig.trustedUserCAKeys[0], caKey)
    }
    
    func testConfigurationWithMultipleCertificateTypes() throws {
        // Test configurations that handle multiple certificate types
        let hostCAKey = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let userCAKey = NIOSSHPrivateKey(p384Key: .init()).publicKey
        let mixedCAKey = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        
        // Client can trust multiple CAs for host certificates
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestAcceptAllHostKeysDelegate()
        )
        clientConfig.trustedHostCAKeys = [hostCAKey, mixedCAKey]
        
        // Server can trust multiple CAs for user certificates
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        var serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        serverConfig.trustedUserCAKeys = [userCAKey, mixedCAKey]
        
        // Verify each configuration has its own set of trusted CAs
        XCTAssertEqual(clientConfig.trustedHostCAKeys.count, 2)
        XCTAssertEqual(serverConfig.trustedUserCAKeys.count, 2)
        
        // Mixed CA key is trusted by both client and server
        XCTAssertTrue(clientConfig.trustedHostCAKeys.contains(mixedCAKey))
        XCTAssertTrue(serverConfig.trustedUserCAKeys.contains(mixedCAKey))
    }
    
    func testEmptyConfigurationBehavior() throws {
        // Test behavior when certificate-related configuration is empty
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        
        // Client with no trusted CAs and no hostname
        let clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestAcceptAllHostKeysDelegate()
        )
        XCTAssertTrue(clientConfig.trustedHostCAKeys.isEmpty)
        XCTAssertNil(clientConfig.hostname)
        
        // Server with no trusted CAs
        let serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        XCTAssertTrue(serverConfig.trustedUserCAKeys.isEmpty)
        
        // When empty, certificate validation should not be attempted
        // This is tested in the state machine tests
    }
    
    func testServerConfigurationAcceptableCriticalOptions() throws {
        // Test that server configuration properly handles custom acceptable critical options
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        
        // Test default configuration
        let defaultConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        XCTAssertEqual(defaultConfig.acceptableCriticalOptions, ["force-command", "source-address"])
        
        // Test custom configuration
        var customConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        customConfig.acceptableCriticalOptions = ["custom-option", "another-option"]
        XCTAssertEqual(customConfig.acceptableCriticalOptions, ["custom-option", "another-option"])
        
        // Test empty configuration
        var emptyConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        emptyConfig.acceptableCriticalOptions = []
        XCTAssertTrue(emptyConfig.acceptableCriticalOptions.isEmpty)
    }
    
    func testConfigurationCopySemantics() throws {
        // Test that configuration structs have proper value semantics
        let caKey1 = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let caKey2 = NIOSSHPrivateKey(p384Key: .init()).publicKey
        
        // Client configuration
        var clientConfig1 = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestAcceptAllHostKeysDelegate()
        )
        clientConfig1.trustedHostCAKeys = [caKey1]
        clientConfig1.hostname = "original.com"
        
        var clientConfig2 = clientConfig1
        clientConfig2.trustedHostCAKeys = [caKey2]
        clientConfig2.hostname = "modified.com"
        
        // Original should be unchanged
        XCTAssertEqual(clientConfig1.trustedHostCAKeys, [caKey1])
        XCTAssertEqual(clientConfig1.hostname, "original.com")
        
        // Copy should have new values
        XCTAssertEqual(clientConfig2.trustedHostCAKeys, [caKey2])
        XCTAssertEqual(clientConfig2.hostname, "modified.com")
        
        // Server configuration
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        var serverConfig1 = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestAcceptAllAuthDelegate()
        )
        serverConfig1.trustedUserCAKeys = [caKey1]
        
        var serverConfig2 = serverConfig1
        serverConfig2.trustedUserCAKeys = [caKey2]
        
        // Original should be unchanged
        XCTAssertEqual(serverConfig1.trustedUserCAKeys, [caKey1])
        
        // Copy should have new values
        XCTAssertEqual(serverConfig2.trustedUserCAKeys, [caKey2])
    }
}

// MARK: - Helper Delegates

fileprivate final class TestDenyAllClientAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        nextChallengePromise.succeed(nil)
    }
}

fileprivate final class TestAcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

fileprivate final class TestAcceptAllAuthDelegate: NIOSSHServerUserAuthenticationDelegate {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
        [.publicKey, .password]
    }
    
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        responsePromise.succeed(.success)
    }
}

fileprivate final class SimplePasswordDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String
    
    init(username: String, password: String) {
        self.username = username
        self.password = password
    }
    
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard availableMethods.contains(.password) else {
            nextChallengePromise.succeed(nil)
            return
        }
        
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: self.username, serviceName: "ssh-connection", offer: .password(.init(password: self.password))))
    }
}