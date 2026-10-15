import SwiftUI
import AuthenticationServices

/// Sign-up / login screen: Sign in with Apple, or e-mail + password (with e-mail verification).
/// `embedded` = used as step 2 of the onboarding (shows a "J'ai déjà un compte" switch instead of a title bar).
struct AuthFlowView: View {
    enum Mode { case signUp, signIn }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    var embedded = false
    @State private var mode: Mode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showPassword = false
    @State private var rawNonce = ""
    @State private var showForgotPassword = false
    @State private var verificationEmail: String?
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    /// Explicit: the synthesized memberwise init would be private (private `@FocusState`/`@State` without initial value).
    init(embedded: Bool = false) {
        self.embedded = embedded
        _mode = State(initialValue: embedded ? .signUp : .signIn)
    }

    private var auth: AuthService { env.auth }
    private var isSignUp: Bool { mode == .signUp }

    private var emailIsValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 5 && trimmed.contains("@") && trimmed.contains(".")
    }

    private var canSubmit: Bool {
        emailIsValid && password.count >= 8 && !auth.isWorking
    }

    var body: some View {
        Group {
            if let pending = verificationEmail {
                VerificationPendingView(email: pending,
                                        onSignIn: {
                                            email = pending
                                            password = ""
                                            verificationEmail = nil
                                            mode = .signIn
                                        },
                                        onChangeEmail: { verificationEmail = nil })
            } else {
                form
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(initialEmail: email)
        }
    }

    private var form: some View {
        FlowScreen {
            FlowHeader(title: isSignUp ? "Crée ton compte" : "Content de te revoir",
                       subtitle: isSignUp
                       ? "Ton compte sauvegarde ta progression et te la rend sur un nouvel iPhone."
                       : "Connecte-toi pour retrouver ta progression.",
                       display: false)

            SignInWithAppleButton(.continue, onRequest: { request in
                rawNonce = AppleNonce.random()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleNonce.sha256(rawNonce)
            }, onCompletion: handleApple)
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: Theme.primaryButtonHeight)
            .clipShape(Capsule())
            .accessibilityLabel(isSignUp ? "S'inscrire avec Apple" : "Se connecter avec Apple")

            Text("ou")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if isSignUp {
                    field("Prénom (facultatif)") {
                        TextField("Prénom", text: $displayName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .focused($focus, equals: .name)
                            .onSubmit { focus = .email }
                            .qField(isFocused: focus == .name)
                    }
                }
                field("Adresse e-mail") {
                    TextField("prenom@exemple.fr", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .qField(isFocused: focus == .email)
                }
                field(isSignUp ? "Mot de passe (8 caractères minimum)" : "Mot de passe") {
                    HStack(spacing: Theme.Spacing.s) {
                        Group {
                            if showPassword {
                                TextField("Mot de passe", text: $password)
                            } else {
                                SecureField("Mot de passe", text: $password)
                            }
                        }
                        .textContentType(isSignUp ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit { if canSubmit { submit() } }
                        Button {
                            showPassword.toggle()
                        } label: {
                            QIconView(icon: showPassword ? .eyeSlash : .eye, size: 20)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                    }
                    .qField(isFocused: focus == .password)
                }
            }

            if let message = auth.errorMessage { FlowMessage(text: message, kind: .error) }
            if let info = auth.infoMessage { FlowMessage(text: info, kind: .success) }

            VStack(spacing: 0) {
                if !isSignUp {
                    FlowLinkButton(title: "Mot de passe oublié ?") { showForgotPassword = true }
                }
                FlowLinkButton(title: isSignUp ? "J'ai déjà un compte" : "Créer un compte") {
                    auth.errorMessage = nil
                    mode = isSignUp ? .signIn : .signUp
                }
            }
        } footer: {
            Button(action: submit) {
                FlowButtonLabel(title: isSignUp ? "Créer mon compte" : "Me connecter", isWorking: auth.isWorking)
            }
            .buttonStyle(.primary)
            .disabled(!canSubmit)
            .accessibilityHint(canSubmit ? "" : "Saisis une adresse e-mail valide et un mot de passe d'au moins 8 caractères.")
        }
        .onAppear { auth.errorMessage = nil }
    }

    /// Label above a field: `QFieldLabel` + the field (the caller applies `.qField`).
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QFieldLabel(title)
            content()
        }
    }

    private func submit() {
        focus = nil
        let name = displayName
        let address = email
        Task {
            if isSignUp {
                if await auth.signUp(email: address, password: password, displayName: name) == .verificationRequired {
                    verificationEmail = address.trimmingCharacters(in: .whitespaces)
                }
            } else {
                await auth.signIn(email: address, password: password)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            let nonce = rawNonce
            Task { await auth.signInWithApple(authorization, rawNonce: nonce) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                auth.errorMessage = "La connexion avec Apple a échoué. Réessaie."
            }
        }
    }
}

/// Shown after a sign-up that requires the e-mail to be confirmed (deep link `quinze://auth-callback`).
struct VerificationPendingView: View {
    let email: String
    let onSignIn: () -> Void
    let onChangeEmail: () -> Void

    var body: some View {
        FlowScreen {
            FlowBadgeIcon(icon: .mail, pastel: .blue)
            FlowHeader(title: "Vérifie tes e-mails",
                       subtitle: "Nous avons envoyé un lien de confirmation à \(email). Ouvre-le sur cet iPhone pour activer ton compte.",
                       display: false)
            FlowMessage(text: "Tu ne le vois pas ? Regarde dans tes courriers indésirables.", kind: .info)
            FlowLinkButton(title: "Changer d'adresse e-mail", action: onChangeEmail)
        } footer: {
            Button("J'ai confirmé mon adresse", action: onSignIn)
                .buttonStyle(.primary)
        }
    }
}

/// Forgot-password sheet: sends the reset link (`quinze://reset-password`).
struct ForgotPasswordView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let initialEmail: String
    @State private var email = ""
    @State private var sent = false
    @FocusState private var emailFocused: Bool

    /// Explicit: the synthesized memberwise init would be private (private `@FocusState` without initial value).
    init(initialEmail: String) {
        self.initialEmail = initialEmail
    }

    private var isValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 5 && trimmed.contains("@") && trimmed.contains(".")
    }

    var body: some View {
        NavigationStack {
            FlowScreen {
                FlowHeader(title: "Mot de passe oublié",
                           subtitle: "Saisis ton adresse e-mail : nous t'enverrons un lien pour choisir un nouveau mot de passe.",
                           display: false)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    QFieldLabel("Adresse e-mail")
                    TextField("prenom@exemple.fr", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        .qField(isFocused: emailFocused)
                }
                if sent {
                    FlowMessage(text: "Si un compte existe avec cette adresse, un e-mail vient d'être envoyé. Ouvre le lien sur cet iPhone.",
                                kind: .success)
                }
                if let message = env.auth.errorMessage { FlowMessage(text: message, kind: .error) }
            } footer: {
                Button {
                    Task { sent = await env.auth.sendPasswordReset(email: email) }
                } label: {
                    FlowButtonLabel(title: sent ? "Renvoyer le lien" : "Envoyer le lien", isWorking: env.auth.isWorking)
                }
                .buttonStyle(.primary)
                .disabled(!isValid || env.auth.isWorking)
            }
            .navigationTitle("Récupération")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .onAppear {
                email = initialEmail
                env.auth.errorMessage = nil
            }
        }
        .tint(Theme.ink)
        .presentationCornerRadius(Theme.Radius.large)
        .presentationBackground(Theme.background)
    }
}

/// New-password screen, shown after the user opened `quinze://reset-password`.
struct NewPasswordView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var passwordFocused: Bool

    /// Explicit: the synthesized memberwise init would be private (private `@FocusState` without initial value).
    init() {}

    var body: some View {
        NavigationStack {
            FlowScreen {
                FlowHeader(title: "Nouveau mot de passe",
                           subtitle: "Choisis un mot de passe d'au moins 8 caractères.",
                           display: false)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    QFieldLabel("Nouveau mot de passe")
                    HStack(spacing: Theme.Spacing.s) {
                        Group {
                            if showPassword {
                                TextField("Nouveau mot de passe", text: $password)
                            } else {
                                SecureField("Nouveau mot de passe", text: $password)
                            }
                        }
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($passwordFocused)
                        Button {
                            showPassword.toggle()
                        } label: {
                            QIconView(icon: showPassword ? .eyeSlash : .eye, size: 20)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                    }
                    .qField(isFocused: passwordFocused)
                }
                if let message = env.auth.errorMessage { FlowMessage(text: message, kind: .error) }
            } footer: {
                Button {
                    Task { _ = await env.auth.updatePassword(password) }
                } label: {
                    FlowButtonLabel(title: "Enregistrer mon mot de passe", isWorking: env.auth.isWorking)
                }
                .buttonStyle(.primary)
                .disabled(password.count < 8 || env.auth.isWorking)
            }
            .navigationTitle("Mot de passe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { env.auth.cancelRecovery() }
                }
            }
            .onAppear { env.auth.errorMessage = nil }
        }
        .tint(Theme.ink)
        .interactiveDismissDisabled()
    }
}
