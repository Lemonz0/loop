import SwiftUI

@MainActor
public struct InviteAuthView: View {
    @Environment(\.appTheme) private var theme
    @Bindable public var authManager = AuthSessionManager.shared
    public let onSuccess: () -> Void
    @State private var signingUp = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var invite = ""
    @State private var serverAddress = AppEnvironment.shared.serverAddress
    @State private var localError: String?
    public init(initialSignup: Bool = false, onSuccess: @escaping () -> Void) { self.onSuccess = onSuccess; _signingUp = State(initialValue: initialSignup) }
    public var body: some View {
        ZStack {
            AmbientGlowBackground()
            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 20) {
                        Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(theme.accent)
                            .frame(width: 80, height: 80).glassEffect(.regular, in: Circle())
                        Text("Loop").font(.largeTitle.bold())
                        Text("A private space for your friends.").foregroundStyle(theme.secondaryText)
                        Picker("Account", selection: $signingUp) {
                            Text("Log in").tag(false)
                            Text("Create account").tag(true)
                        }.pickerStyle(.segmented).disabled(authManager.isAuthenticating)
                        VStack(spacing: 14) {
                            TextField("Username", text: $username).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().padding().circleSurface(radius: 20)
                            SecureField(signingUp ? "Password (12–128 characters)" : "Password", text: $password)
                                .textContentType(signingUp ? .newPassword : .password).padding().circleSurface(radius: 20)
                            if signingUp {
                                TextField("Display name", text: $displayName).textContentType(.name).padding().circleSurface(radius: 20)
                                SecureField("Invite code", text: $invite).autocorrectionDisabled().padding().circleSurface(radius: 20)
                            }
                            DisclosureGroup("Server connection") {
                                TextField("http://192.168.1.132:8080", text: $serverAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                    .padding(.vertical, 12)
                                Text("For PC testing, use the same Wi-Fi and allow Local Network access. A hosted server must use HTTPS.")
                                    .font(.footnote).foregroundStyle(theme.secondaryText)
                            }.padding().circleSurface(radius: 20)
                            if let error = localError ?? authManager.lastError {
                                Text(error).font(.footnote).foregroundStyle(theme.destructive)
                            }
                            Button { submit() } label: {
                                HStack { if authManager.isAuthenticating { ProgressView() }; Text(signingUp ? "Create account" : "Log in") }
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.glassProminent).disabled(authManager.isAuthenticating || username.isEmpty || password.isEmpty)
                            if authManager.currentSession != nil && !authManager.isAuthenticated {
                                Button("Retry saved session") {
                                    Task {
                                        if let url = AccountCodec.serverURL(serverAddress), await authManager.validateSavedSession(serverURL: url) { onSuccess() }
                                    }
                                }.buttonStyle(.glass).disabled(authManager.isAuthenticating)
                            }
                        }
                    }.padding(20)
                }
            }.scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: signingUp) { _, _ in password = ""; localError = nil; authManager.lastError = nil }
    }
    private func submit() {
        localError = nil
        guard let url = AccountCodec.serverURL(serverAddress) else { localError = "Enter an HTTPS server URL or a local network HTTP address."; return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if signingUp {
            guard name.range(of: "^[a-z0-9_]{3,32}$", options: .regularExpression) != nil else { localError = "Username: 3–32 letters, numbers, or underscores."; return }
            guard (12...128).contains(password.count), password == password.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !invite.isEmpty else {
                localError = "Enter a display name, invite, and password of 12–128 characters without surrounding spaces."; return
            }
        }
        AppEnvironment.shared.serverAddress = url.absoluteString
        Task {
            if await authManager.signIn(username: name, password: password, invite: signingUp ? invite.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines), serverURL: url) {
                password = ""; invite = ""; HapticFeedback.success(); onSuccess()
            } else { HapticFeedback.error() }
        }
    }
}
#Preview("Account · dark") { InviteAuthView(onSuccess: {}).circlePreviewTheme(.aurora) }
#Preview("Account · light") { InviteAuthView(onSuccess: {}).circlePreviewTheme(.daylight) }

#Preview("Signup · dark") { InviteAuthView(initialSignup: true, onSuccess: {}).circlePreviewTheme(.aurora) }
#Preview("Signup · light") { InviteAuthView(initialSignup: true, onSuccess: {}).circlePreviewTheme(.daylight) }
