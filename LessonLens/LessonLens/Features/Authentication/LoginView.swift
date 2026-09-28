import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.serviceContainer) private var services

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            // Logo and title
            VStack(spacing: 16) {
                LessonLensLogoView(size: 120)

                Text("LessonLens")
                    .font(PSDFonts.largeTitle)
                    .foregroundStyle(Color.psdPacific)

                Text("Reflect, Analyze, Grow")
                    .font(PSDFonts.title3)
                    .foregroundStyle(.secondary)
            }

            // Domain notice
            VStack(spacing: 8) {
                Text("Peninsula School District")
                    .font(PSDFonts.headline)

                Text("Sign in with your @\(services.config.allowedDomain) account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Sign in button
            Button {
                signIn()
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                    }
                    Text(isSigningIn ? "Signing in..." : "Sign in with Google")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSigningIn)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            // Footer
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text("Your audio stays on your device")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Only transcripts are sent for analysis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    PSDLogoView(size: 20)
                    Text("Brought to you by Peninsula School District")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .background(
            LinearGradient(
                colors: [Color.psdSkylight, Color.psdSeaFoam],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                let session = try await services.authService.signIn()
                appState.currentUser = session.user
                appState.isAuthenticated = true
            } catch let error as AuthError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Sign in failed: \(error.localizedDescription)"
            }

            isSigningIn = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
        .environment(ServiceContainer.shared)
}
