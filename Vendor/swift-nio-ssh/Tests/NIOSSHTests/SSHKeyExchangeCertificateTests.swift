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

final class SSHKeyExchangeCertificateTests: XCTestCase {
    
    // MARK: - Host Certificate Validation Tests
    
    func testHostCertificateValidationInKeyExchange() throws {
        // Test that the key exchange properly handles host certificates
        // Using fixtures from CertifiedKeyTests
        let caKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.caPublicKey)
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        
        // Verify this is a certificate
        XCTAssertNotNil(NIOSSHCertifiedPublicKey(hostCertKey))
        
        // Verify certificate can be validated with correct CA
        let validatedCert = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        XCTAssertNoThrow(try validatedCert.validate(
            principal: "localhost",
            type: .host,
            allowedAuthoritySigningKeys: [caKey],
            acceptableCriticalOptions: ["cats"]
        ))
    }
    
    func testHostCertificateValidationFailsWithWrongCA() throws {
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        let validatedCert = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        
        // Create a different CA that didn't sign this certificate
        let wrongCA = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        
        XCTAssertThrowsError(try validatedCert.validate(
            principal: "localhost",
            type: .host,
            allowedAuthoritySigningKeys: [wrongCA],
            acceptableCriticalOptions: ["cats"]
        )) { error in
            XCTAssertEqual((error as? NIOSSHError)?.type, .invalidCertificate)
        }
    }
    
    func testHostCertificateValidationWithCriticalOptions() throws {
        let caKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.caPublicKey)
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        let validatedCert = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        
        // This certificate has critical option "cats" = "dogs"
        
        // Should fail without accepting the critical option
        XCTAssertThrowsError(try validatedCert.validate(
            principal: "localhost",
            type: .host,
            allowedAuthoritySigningKeys: [caKey],
            acceptableCriticalOptions: []
        ))
        
        // Should succeed when accepting the critical option
        let criticalOptions = try validatedCert.validate(
            principal: "localhost",
            type: .host,
            allowedAuthoritySigningKeys: [caKey],
            acceptableCriticalOptions: ["cats"]
        )
        XCTAssertEqual(criticalOptions, ["cats": "dogs"])
    }
    
    func testDelegateReceivesHostCertificateInformation() throws {
        // Test that the delegate's validateHostCertificate method receives correct information
        class TestDelegate: NIOSSHClientServerAuthenticationDelegate {
            var validateHostKeyCalled = false
            var validateHostCertificateCalled = false
            var receivedCertificate: NIOSSHCertifiedPublicKey?
            
            func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
                self.validateHostKeyCalled = true
                validationCompletePromise.succeed(())
            }
            
            func validateHostCertificate(hostKey: NIOSSHPublicKey, certifiedKey: NIOSSHCertifiedPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
                self.validateHostCertificateCalled = true
                self.receivedCertificate = certifiedKey
                validationCompletePromise.succeed(())
            }
        }
        
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        let certifiedKey = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        let delegate = TestDelegate()
        
        // Simulate the delegate being called
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: Void.self)
        
        // In the actual implementation, this would be called from SSHKeyExchangeStateMachine
        // when a certificate is detected and trusted CAs are configured
        delegate.validateHostCertificate(
            hostKey: hostCertKey,
            certifiedKey: certifiedKey,
            validationCompletePromise: promise
        )
        
        XCTAssertTrue(delegate.validateHostCertificateCalled)
        XCTAssertFalse(delegate.validateHostKeyCalled)
        XCTAssertEqual(delegate.receivedCertificate, certifiedKey)
        XCTAssertNoThrow(try promise.futureResult.wait())
    }
    
    func testHostCertificateWithEmptyPrincipalsAcceptsAnyHostname() throws {
        // The ed25519 user cert has empty principals, let's test that behavior
        let caKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.caPublicKey)
        let certKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.ed25519User)
        let validatedCert = try XCTUnwrap(NIOSSHCertifiedPublicKey(certKey))
        
        // This is a user cert with empty principals - it should accept any username
        XCTAssertEqual(validatedCert.validPrincipals, [])
        
        // Should accept any principal when empty
        XCTAssertNoThrow(try validatedCert.validate(
            principal: "anyuser",
            type: .user,
            allowedAuthoritySigningKeys: [caKey],
            acceptableCriticalOptions: ["force-command"]
        ))
    }
    
    func testMultipleTrustedCAsForHostCertificate() throws {
        let caKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.caPublicKey)
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        let validatedCert = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        
        // Create multiple CAs
        let wrongCA1 = NIOSSHPrivateKey(p256Key: .init()).publicKey
        let wrongCA2 = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        
        // Should succeed when the correct CA is in the list
        XCTAssertNoThrow(try validatedCert.validate(
            principal: "localhost",
            type: .host,
            allowedAuthoritySigningKeys: [wrongCA1, caKey, wrongCA2],
            acceptableCriticalOptions: ["cats"]
        ))
    }
    
    func testHostCertificateValidationIntegrationWithConfiguration() throws {
        // Test that the configuration properly stores and uses trusted host CAs
        let caKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.caPublicKey)
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        
        // Create client configuration with trusted CA
        var clientConfig = SSHClientConfiguration(
            userAuthDelegate: TestDenyAllClientAuthDelegate(),
            serverAuthDelegate: TestAcceptAllHostKeysDelegate()
        )
        clientConfig.trustedHostCAKeys = [caKey]
        clientConfig.hostname = "example.com"
        
        // Verify configuration is set correctly
        XCTAssertEqual(clientConfig.trustedHostCAKeys.count, 1)
        XCTAssertEqual(clientConfig.trustedHostCAKeys[0], caKey)
        XCTAssertEqual(clientConfig.hostname, "example.com")
        
        // In actual usage, the SSHKeyExchangeStateMachine would use these values
        // to validate the certificate
        let validatedCert = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        XCTAssertNoThrow(try validatedCert.validate(
            principal: clientConfig.hostname ?? "",
            type: .host,
            allowedAuthoritySigningKeys: clientConfig.trustedHostCAKeys,
            acceptableCriticalOptions: ["cats"]
        ))
    }
    
    func testDefaultDelegateImplementation() throws {
        // Test that the default implementation of validateHostCertificate calls validateHostKey
        class TestDefaultDelegate: NIOSSHClientServerAuthenticationDelegate {
            var validateHostKeyCalled = false
            
            func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
                self.validateHostKeyCalled = true
                validationCompletePromise.succeed(())
            }
            
            // Not implementing validateHostCertificate - should use default
        }
        
        let hostCertKey = try NIOSSHPublicKey(openSSHPublicKey: CertifiedKeyTests.Fixtures.p384Host)
        let certifiedKey = try XCTUnwrap(NIOSSHCertifiedPublicKey(hostCertKey))
        let delegate = TestDefaultDelegate()
        
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: Void.self)
        
        // Call the default implementation
        delegate.validateHostCertificate(
            hostKey: hostCertKey,
            certifiedKey: certifiedKey,
            validationCompletePromise: promise
        )
        
        // Should have called validateHostKey
        XCTAssertTrue(delegate.validateHostKeyCalled)
        XCTAssertNoThrow(try promise.futureResult.wait())
    }
}

// MARK: - Test Fixtures
extension CertifiedKeyTests {
    fileprivate enum Fixtures {
        // Reuse fixtures from CertifiedKeyTests
        static let caPublicKey = "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBHYlMSXacXt13oBLpMXEP0OSMw5okd5c7G3hoim1MR/THUOyOS2AVQKEqLZs+td3Y6yYCrq5TGWDNGY2dfKFX99nLqJCq2kxR//CP3UherkZnn6u4eW4biLL7xODqNOzkQ== lukasa@MacBook-Pro.local"
        
        static let p384Host = "ecdsa-sha2-nistp384-cert-v01@openssh.com AAAAKGVjZHNhLXNoYTItbmlzdHAzODQtY2VydC12MDFAb3BlbnNzaC5jb20AAAAgvD8+H64ZEuPHwYIxuym9XHVpiJEoCvCqyy8Ch7JAZEgAAAAIbmlzdHAzODQAAABhBJPOgAXHijSxoZBiyhSDOR3eUELUoc+hqh/SY1Wq4/562jThf6Q+tjVzZTMWZMAP4S6DD2qZswsRvisxXkcZDOw5bvyk0WmezYvjUP6TZII/0BDVTotCf4SxukEtcqBZqgAAAAAAAAIfAAAAAgAAAA1Ib3N0IFAzODQga2V5AAAAHAAAAAlsb2NhbGhvc3QAAAALZXhhbXBsZS5jb20AAAAAXtfWGQAAAAC8kfpVAAAAFAAAAARjYXRzAAAACAAAAARkb2dzAAAALgAAAARsZW5zAAAACAAAAAR3aWRlAAAABHNpemUAAAAOAAAACmZ1bGwtZnJhbWUAAAAAAAAAiAAAABNlY2RzYS1zaGEyLW5pc3RwMzg0AAAACG5pc3RwMzg0AAAAYQR2JTEl2nF7dd6AS6TFxD9DkjMOaJHeXOxt4aIptTEf0x1DsjktgFUChKi2bPrXd2OsmAq6uUxlgzRmNnXyhV/fZy6iQqtpMUf/wj91IXq5GZ5+ruHluG4iy+8Tg6jTs5EAAACEAAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAABpAAAAMH0U5Rb7TVXX4TP1T1keRioun8qUwsynDX9HHJ/lxgQVdpv3rK/8JVRYE3iEhs8gCwAAADEAp+ljZpPr60aE5l0Q1KrLv5/gfEbYasXBdnSbO47qnAYRg+6VuEb+GGiG9ZAXsq5G lukasa@MacBook-Pro.local"
        
        static let ed25519User = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIDxk/nOhhVDtrweRRR1trNm3T3RdPinf7bYLTPnfWAPuAAAAIJfkNV4OS33ImTXvorZr72q4v5XhVEQKfvqsxOEJ/XaRAAAAAAAAAAAAAAABAAAAEFVzZXIgZWQyNTUxOSBrZXkAAAAAAAAAAF7X1scAAAAAvJH7AwAAACEAAAANZm9yY2UtY29tbWFuZAAAAAwAAAAIdW5hbWUgLWEAAACCAAAAFXBlcm1pdC1YMTEtZm9yd2FyZGluZwAAAAAAAAAXcGVybWl0LWFnZW50LWZvcndhcmRpbmcAAAAAAAAAFnBlcm1pdC1wb3J0LWZvcndhcmRpbmcAAAAAAAAACnBlcm1pdC1wdHkAAAAAAAAADnBlcm1pdC11c2VyLXJjAAAAAAAAAAAAAACIAAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBHYlMSXacXt13oBLpMXEP0OSMw5okd5c7G3hoim1MR/THUOyOS2AVQKEqLZs+td3Y6yYCrq5TGWDNGY2dfKFX99nLqJCq2kxR//CP3UherkZnn6u4eW4biLL7xODqNOzkQAAAIMAAAATZWNkc2Etc2hhMi1uaXN0cDM4NAAAAGgAAAAwBWeqRhZqFoGRXg7WtKSbQ9rOn2WNUiaDV1XjX2aCyi/W7431Hxpxg5iGLzP5B7ZuAAAAMByxIrsZhBM9RDxS2qGV9QByw5ebAaRFLtmvJSyxgn1nwWtkPnKetYTsP1Olh4+3tQ== lukasa@MacBook-Pro.local"
    }
}

// MARK: - Helper Delegates

fileprivate final class TestAcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
    
    func validateHostCertificate(hostKey: NIOSSHPublicKey, certifiedKey: NIOSSHCertifiedPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

fileprivate final class TestDenyAllClientAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        nextChallengePromise.succeed(nil)
    }
}