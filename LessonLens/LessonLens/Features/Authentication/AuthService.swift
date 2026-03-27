import Foundation
import AuthenticationServices
import AppKit
import CryptoKit

/// Service for handling Google OAuth authentication via ASWebAuthenticationSession
@MainActor
final class AuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private let config: AppConfiguration
    private let keychain = KeychainService.shared

    @Published var isAuthenticating = false
    @Published var authError: AuthError?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }

    // MARK: - Public Methods

    /// Initiates Google Sign-In flow
    func signIn() async throws -> SessionToken {
        isAuthenticating = true
        authError = nil

        defer { isAuthenticating = false }

        do {
            let idToken = try await performGoogleSignIn()
            let session = try await validateWithBackend(idToken: idToken)

            if let sessionData = try? JSONEncoder().encode(session) {
                _ = keychain.store(key: KeychainKeys.sessionToken, data: sessionData)
            }

            return session
        } catch let error as AuthError {
            authError = error
            throw error
        } catch {
            let authErr = AuthError.unknown(error)
            authError = authErr
            throw authErr
        }
    }

    /// Signs out the current user
    func signOut() {
        keychain.delete(key: KeychainKeys.sessionToken)
        keychain.delete(key: KeychainKeys.refreshToken)
    }

    /// Returns the current session if valid
    func getCurrentSession() -> SessionToken? {
        guard let data = keychain.retrieve(key: KeychainKeys.sessionToken),
              let session = try? JSONDecoder().decode(SessionToken.self, from: data),
              session.isValid else {
            return nil
        }
        return session
    }

    /// Refreshes the current session if needed
    func refreshSessionIfNeeded() async throws -> SessionToken? {
        guard let currentSession = getCurrentSession() else {
            return nil
        }

        let oneHourFromNow = Date().addingTimeInterval(3600)
        if currentSession.expiresAt < oneHourFromNow {
            return try await refreshSession(currentSession)
        }

        return currentSession
    }

    /// Returns a valid session, attempting refresh then re-authentication if needed.
    /// Updates appState on successful recovery so global auth state stays consistent.
    func getValidSession(updating appState: AppState? = nil) async throws -> SessionToken {
        // 1. Current session still valid
        if let session = getCurrentSession() {
            return session
        }

        // 2. Access token expired but refresh token may still be valid (30-day lifetime)
        if let rawSession = getRawSession(), rawSession.refreshToken != nil {
            do {
                let session = try await refreshSession(rawSession)
                appState?.isAuthenticated = true
                appState?.currentUser = session.user
                return session
            } catch {
                // Refresh failed (refresh token also expired), fall through to sign-in
            }
        }

        // 3. Full re-authentication via Google Sign-In
        let session = try await signIn()
        appState?.isAuthenticated = true
        appState?.currentUser = session.user
        return session
    }

    // MARK: - Private Methods

    /// Loads session from keychain without checking expiry, preserving the refresh token
    private func getRawSession() -> SessionToken? {
        guard let data = keychain.retrieve(key: KeychainKeys.sessionToken),
              let session = try? JSONDecoder().decode(SessionToken.self, from: data) else {
            return nil
        }
        return session
    }


    private func performGoogleSignIn() async throws -> String {
        guard !config.googleClientID.isEmpty else {
            throw AuthError.missingClientID
        }

        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // Build Google OAuth authorization URL
        let redirectScheme = "com.googleusercontent.apps." + config.googleClientID.components(separatedBy: ".").first!
        let redirectURI = "\(redirectScheme):/oauth2callback"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.googleClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "hd", value: config.allowedDomain),
        ]

        guard let authURL = components.url else {
            throw AuthError.unknown(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to build auth URL"]))
        }

        // Present ASWebAuthenticationSession
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let error = error {
                    continuation.resume(throwing: AuthError.unknown(error))
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.unknown(NSError(domain: "AuthService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No callback URL received"])))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // Extract authorization code from callback
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.unknown(NSError(domain: "AuthService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No authorization code in callback"]))
        }

        // Exchange authorization code for tokens
        let idToken = try await exchangeCodeForToken(code: code, codeVerifier: codeVerifier, redirectURI: redirectURI)
        return idToken
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String, redirectURI: String) async throws -> String {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "code": code,
            "client_id": config.googleClientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.unknown(NSError(domain: "AuthService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(errorBody)"]))
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        return tokenResponse.idToken
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Backend Communication

    private func validateWithBackend(idToken: String) async throws -> SessionToken {
        let url = config.backendURL.appendingPathComponent("auth/validate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["id_token": idToken]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(NSError(domain: "AuthService", code: -4))
        }

        switch httpResponse.statusCode {
        case 200:
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            return SessionToken(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn)),
                user: authResponse.user
            )
        case 403:
            throw AuthError.invalidDomain
        case 401:
            throw AuthError.tokenExpired
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.unknown(NSError(
                domain: "AuthService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
        }
    }

    private func refreshSession(_ session: SessionToken) async throws -> SessionToken {
        guard let refreshToken = session.refreshToken else {
            throw AuthError.tokenExpired
        }

        let url = config.backendURL.appendingPathComponent("auth/refresh")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenExpired
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        let newSession = SessionToken(
            accessToken: authResponse.accessToken,
            refreshToken: authResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn)),
            user: authResponse.user
        )

        if let sessionData = try? JSONEncoder().encode(newSession) {
            _ = keychain.store(key: KeychainKeys.sessionToken, data: sessionData)
        }

        return newSession
    }
}

// MARK: - Supporting Types

private struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct GoogleTokenResponse: Codable {
    let accessToken: String
    let idToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - Base64URL Encoding

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
