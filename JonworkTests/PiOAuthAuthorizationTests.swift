@testable import Jonwork
import CryptoKit
import Foundation
import Testing

struct PiOAuthAuthorizationTests {
    @Test(arguments: [301, 302, 303, 307, 308])
    func credentialBearingRequestsNeverFollowRedirects(_ status: Int) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for target in ["https://jonwork.com/other", "https://foreign.example/token", "http://jonwork.com/token"] {
            var original = URLRequest(url: URL(string: "https://jonwork.com/v1/auth/token")!)
            original.httpMethod = "POST"
            original.httpBody = Data("refresh_token=fixture".utf8)
            let task = session.dataTask(with: original)
            let response = try #require(HTTPURLResponse(url: original.url!, statusCode: status, httpVersion: nil, headerFields: ["Location": target]))
            var redirected = URLRequest(url: URL(string: target)!)
            redirected.httpMethod = "POST"
            redirected.httpBody = original.httpBody
            let permitted: URLRequest? = await withCheckedContinuation { continuation in
                PiOAuthRequestDelegate.shared.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) {
                    continuation.resume(returning: $0)
                }
            }
            #expect(permitted == nil)
            task.cancel()
        }
    }

    @Test @MainActor
    func signInDistinguishesNetworkAndTimeoutFromGatewayOutage() {
        for error in [PiServiceError.timedOut, .networkUnavailable, .connectionLost, .transportFailure(code: -1200)] {
            #expect(PiSignInViewController.presentedMessage(for: error) == error.localizedDescription)
            #expect(PiSignInViewController.presentedMessage(for: error) != PiServiceError.gatewayUnavailable.localizedDescription)
        }
    }

    private var authentication: PiGatewayWire.Authentication {
        .init(type: "oauth2", clientId: "jonwork-ios",
              authorizationEndpoint: URL(string: "https://jonwork.com/api/oauth/authorize")!,
              credentialEndpoint: URL(string: "https://jonwork.com/v1/auth/password")!,
              tokenEndpoint: URL(string: "https://jonwork.com/api/oauth/token")!,
              revocationEndpoint: URL(string: "https://jonwork.com/api/oauth/revoke")!,
              scopes: ["pi.gateway"], pkceMethods: ["S256"], accessTokenLifetimeSeconds: 900,
              refreshTokenRotation: "required")
    }

    @Test func authorizationUsesS256AndNeverSendsVerifierToBrowser() throws {
        let request = try PiOAuthAuthorizationRequest(authentication: authentication)
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let expected = Data(SHA256.hash(data: Data(request.verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(value("response_type") == "code")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == expected)
        #expect(value("redirect_uri") == "jonwork://oauth/pi")
        #expect(value("state") == request.state)
        #expect(value("code_verifier") == nil)
        #expect(request.verifier.count == 43)
        let other = try PiOAuthAuthorizationRequest(authentication: authentication)
        #expect(request.state != other.state)
        #expect(request.verifier != other.verifier)
    }

    @Test func callbackAcceptsOnlyExactRouteUniqueStateAndCode() throws {
        let request = try PiOAuthAuthorizationRequest(authentication: authentication)
        #expect(try request.code(from: URL(string: "jonwork://oauth/pi?state=\(request.state)&code=fixture")!) == "fixture")
        let invalid = [
            "jonwork://oauth/pi?state=wrong&code=fixture",
            "jonwork://oauth/wrong?state=\(request.state)&code=fixture",
            "https://oauth/pi?state=\(request.state)&code=fixture",
            "jonwork://oauth/pi?state=\(request.state)&state=other&code=fixture",
            "jonwork://oauth/pi?state=\(request.state)&code=one&code=two",
            "jonwork://oauth/pi?state=\(request.state)&code=",
            "jonwork://oauth/pi?state=\(request.state)&code=fixture&error=access_denied",
            "jonwork://user@oauth/pi?state=\(request.state)&code=fixture",
        ]
        for url in invalid {
            #expect(throws: PiOAuthError.stateMismatch) { try request.code(from: URL(string: url)!) }
        }
    }
}
