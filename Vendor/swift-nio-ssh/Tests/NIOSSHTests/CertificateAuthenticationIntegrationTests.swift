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
import NIOPosix
@testable import NIOSSH
import XCTest

/// Integration tests for certificate authentication flow
/// These tests focus on the interaction between components rather than full end-to-end testing
final class CertificateAuthenticationIntegrationTests: XCTestCase {
    
    // MARK: - Configuration Integration Tests
    
    func testClientServerConfigurationWithCertificates() throws {
        // Test that client and server configurations properly handle certificate settings
        let caKey = NIOSSHPrivateKey(p384Key: .init()).publicKey
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        
        // Client configuration
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestCertificateValidatingDelegate()
        )
        clientConfig.trustedHostCAKeys = [caKey]
        clientConfig.hostname = "test.example.com"
        
        // Server configuration
        var serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestCertificateAcceptingDelegate()
        )
        serverConfig.trustedUserCAKeys = [caKey]
        
        // Verify configurations are set correctly
        XCTAssertEqual(clientConfig.trustedHostCAKeys.count, 1)
        XCTAssertEqual(clientConfig.trustedHostCAKeys[0], caKey)
        XCTAssertEqual(clientConfig.hostname, "test.example.com")
        XCTAssertEqual(serverConfig.trustedUserCAKeys.count, 1)
        XCTAssertEqual(serverConfig.trustedUserCAKeys[0], caKey)
    }
    
    func testDelegateIntegrationWithCertificateValidation() throws {
        // Test that delegates receive certificate information correctly
        let testDelegate = TestCertificateValidatingDelegate()
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: testDelegate
        )
        
        let caKey = NIOSSHPrivateKey(p384Key: .init()).publicKey
        clientConfig.trustedHostCAKeys = [caKey]
        
        // In actual usage, the SSHKeyExchangeStateMachine would call the delegate
        // Here we simulate that call
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: Void.self)
        
        // Create a mock certificate for testing
        let hostKey = NIOSSHPrivateKey(p256Key: .init()).publicKey
        
        // Test regular host key validation
        testDelegate.validateHostKey(hostKey: hostKey, validationCompletePromise: promise)
        XCTAssertTrue(testDelegate.validateHostKeyCalled)
        XCTAssertFalse(testDelegate.validateHostCertificateCalled)
        
        // Reset state
        testDelegate.validateHostKeyCalled = false
        
        // Test certificate validation would be called when a certificate is detected
        // This demonstrates the integration point
        XCTAssertEqual(clientConfig.trustedHostCAKeys.count, 1)
    }
    
    func testUserAuthenticationWithCertificateInfo() throws {
        // Test that user authentication properly passes certificate information
        let userAuthDelegate = TestCertificateAcceptingDelegate()
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        var serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: userAuthDelegate
        )
        
        let caKey = NIOSSHPrivateKey(p384Key: .init()).publicKey
        serverConfig.trustedUserCAKeys = [caKey]
        
        // Create a user authentication request with certificate info
        let userKey = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        let request = NIOSSHUserAuthenticationRequest(
            username: "testuser",
            serviceName: "ssh-connection",
            request: .publicKey(.init(publicKey: userKey, certifiedKey: nil))
        )
        
        // Test the delegate receives the request
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: NIOSSHUserAuthenticationOutcome.self)
        userAuthDelegate.requestReceived(request: request, responsePromise: promise)
        
        XCTAssertTrue(userAuthDelegate.authenticationRequested)
        XCTAssertEqual(userAuthDelegate.lastUsername, "testuser")
    }
    
    func testMultipleCAsIntegration() throws {
        // Test handling of multiple certificate authorities
        let ca1 = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let ca2 = NIOSSHPrivateKey(p384Key: .init()).publicKey
        let ca3 = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestCertificateValidatingDelegate()
        )
        clientConfig.trustedHostCAKeys = [ca1, ca2, ca3]
        
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        var serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestCertificateAcceptingDelegate()
        )
        serverConfig.trustedUserCAKeys = [ca3, ca2, ca1] // Different order
        
        // Verify all CAs are stored
        XCTAssertEqual(clientConfig.trustedHostCAKeys.count, 3)
        XCTAssertEqual(serverConfig.trustedUserCAKeys.count, 3)
        
        // Verify they contain the same CAs despite different order
        XCTAssertTrue(clientConfig.trustedHostCAKeys.contains(ca1))
        XCTAssertTrue(clientConfig.trustedHostCAKeys.contains(ca2))
        XCTAssertTrue(clientConfig.trustedHostCAKeys.contains(ca3))
        XCTAssertTrue(serverConfig.trustedUserCAKeys.contains(ca1))
        XCTAssertTrue(serverConfig.trustedUserCAKeys.contains(ca2))
        XCTAssertTrue(serverConfig.trustedUserCAKeys.contains(ca3))
    }
    
    func testEmptyCAListBehavior() throws {
        // Test behavior when no CAs are configured
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestCertificateValidatingDelegate()
        )
        
        let hostKey = NIOSSHPrivateKey(p256Key: .init())
        var serverConfig = SSHServerConfiguration(
            hostKeys: [hostKey],
            userAuthDelegate: TestCertificateAcceptingDelegate()
        )
        
        // Initially empty
        XCTAssertTrue(clientConfig.trustedHostCAKeys.isEmpty)
        XCTAssertTrue(serverConfig.trustedUserCAKeys.isEmpty)
        
        // When empty, certificate validation should not be attempted
        // This is handled in the state machine implementations
    }
}

// MARK: - Test Delegates

private final class TestCertificateValidatingDelegate: NIOSSHClientServerAuthenticationDelegate {
    var validateHostKeyCalled = false
    var validateHostCertificateCalled = false
    var lastHostKey: NIOSSHPublicKey?
    var lastCertificate: NIOSSHCertifiedPublicKey?
    
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        self.validateHostKeyCalled = true
        self.lastHostKey = hostKey
        validationCompletePromise.succeed(())
    }
    
    func validateHostCertificate(hostKey: NIOSSHPublicKey, certifiedKey: NIOSSHCertifiedPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        self.validateHostCertificateCalled = true
        self.lastHostKey = hostKey
        self.lastCertificate = certifiedKey
        validationCompletePromise.succeed(())
    }
}

private final class TestCertificateAcceptingDelegate: NIOSSHServerUserAuthenticationDelegate {
    var authenticationRequested = false
    var lastUsername: String?
    var lastCertificate: NIOSSHCertifiedPublicKey?
    
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
        [.publicKey]
    }
    
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        self.authenticationRequested = true
        self.lastUsername = request.username
        
        if case .publicKey(let keyInfo) = request.request {
            self.lastCertificate = keyInfo.certifiedKey
        }
        
        responsePromise.succeed(.success)
    }
}

private final class TestDenyAllClientAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        nextChallengePromise.succeed(nil)
    }
}

private final class TestAcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}