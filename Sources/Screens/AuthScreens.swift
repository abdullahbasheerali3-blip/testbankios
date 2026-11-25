import SwiftUI

// MARK: - Shared auth layout: branded hero on top, rounded form sheet below.

private struct AuthScaffold<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            HeroBackground { EmptyView() }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        AppLogo(size: 52)
                        Text(tr("app_name")).font(AppFont.titleLarge).foregroundColor(.white)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(AppFont.headlineLarge).foregroundColor(.white)
                        Text(subtitle).font(AppFont.bodyLarge).foregroundColor(Color.white.opacity(0.8))
                    }
                    .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 20)

                SkylineStrip()
                    .frame(height: 70)
                    .frame(maxWidth: .infinity)

                ScrollView {
                    VStack(spacing: 14) {
                        content()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity)
                }
                .background(
                    Theme.background
                        .clipShape(RoundedCorner(radius: 32, corners: [.topLeft, .topRight]))
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - Login

struct LoginScreen: View {
    var onOtpRequired: (String) -> Void
    var onAuthenticated: (User) -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var loading = false
    @State private var showTestCredentials = false
    @State private var passwordVisible = false
    @State private var saveForBiometric = Services.shared.settings.biometricLoginEnabled
    @State private var biometricReady = Services.shared.settings.biometricLoginEnabled && Services.shared.credentials.hasCredentials()

    private var canSubmit: Bool {
        !loading
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor
    private func performSignIn(user: String, pass: String, skipOtp: Bool, rememberCredentials: Bool) async {
        loading = true
        error = nil
        let trimmed = user.trimmingCharacters(in: .whitespaces)
        let loginResult = await apiCall { try await ApiClient.shared.login(LoginRequest(username: trimmed, password: pass)) }
        switch loginResult {
        case .failure(let e):
            error = e.message
        case .success(let response):
            if rememberCredentials {
                Services.shared.credentials.save(username: trimmed, password: pass)
                Services.shared.settings.biometricLoginEnabled = true
                saveForBiometric = true
                biometricReady = true
            }
            if skipOtp && !response.otpToken.isEmpty {
                let otpResult = await apiCall { try await ApiClient.shared.devOtp(token: response.otpToken) }
                switch otpResult {
                case .failure(let e):
                    error = e.message
                case .success(let otp):
                    let verifyResult = await apiCall { try await ApiClient.shared.verifyOtp(OtpRequest(otpToken: response.otpToken, code: otp.code)) }
                    switch verifyResult {
                    case .success(let verified): onAuthenticated(verified.user)
                    case .failure(let e): error = e.message
                    }
                }
            } else if response.otpToken.isEmpty {
                let meResult = await apiCall { try await ApiClient.shared.me() }
                switch meResult {
                case .success(let u): onAuthenticated(u)
                case .failure(let e): error = e.message
                }
            } else {
                onOtpRequired(response.otpToken)
            }
        }
        loading = false
    }

    private func submit() {
        let u = username, p = password, remember = saveForBiometric
        Task { await performSignIn(user: u, pass: p, skipOtp: false, rememberCredentials: remember) }
    }

    @MainActor
    private func biometricSignIn() async {
        loading = true
        error = nil
        let ok = await BiometricAuth.authenticate(.deviceCredential)
        if !ok {
            error = tr("biometric_unavailable")
            loading = false
            return
        }
        guard let saved = Services.shared.credentials.load() else {
            biometricReady = false
            error = tr("biometric_unavailable")
            loading = false
            return
        }
        await performSignIn(user: saved.username, pass: saved.password, skipOtp: true, rememberCredentials: false)
    }

    var body: some View {
        AuthScaffold(title: tr("login_title"), subtitle: tr("login_subtitle")) {
            if showTestCredentials {
                HStack(spacing: 12) {
                    IconBadge(systemName: "flask", tint: Brand.teal, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("test_sign_in")).font(AppFont.labelMedium).foregroundColor(Color(hex: 0x00403A))
                        Text("cust01 / Passw0rd!").font(AppFont.titleMedium).foregroundColor(Color(hex: 0x00403A))
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.secondaryContainer))
            }

            AppTextField(label: Chaos.label(tr("username")), text: $username,
                         locator: Chaos.locator("login_username"),
                         keyboard: .default, capitalization: .never)

            ZStack(alignment: .bottomTrailing) {
                AppTextField(label: Chaos.label(tr("password")), text: $password,
                             locator: Chaos.locator("login_password"),
                             secure: !passwordVisible)
                Button {
                    passwordVisible.toggle()
                } label: {
                    Image(systemName: passwordVisible ? "eye.slash" : "eye")
                        .foregroundColor(Theme.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(passwordVisible ? tr("hide_password") : tr("show_password"))
                .accessibilityIdentifier("login_password_toggle")
                .padding(.trailing, 4)
                .padding(.bottom, 2)
            }

            HStack(spacing: 12) {
                Image(systemName: "touchid").foregroundColor(Theme.primary).font(.system(size: 22))
                Text(tr("biometric_login")).font(AppFont.bodyMedium).foregroundColor(Theme.onSurface)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { saveForBiometric },
                    set: { checked in
                        saveForBiometric = checked
                        if !checked {
                            biometricReady = false
                            Services.shared.credentials.clear()
                            Services.shared.settings.biometricLoginEnabled = false
                        }
                    }
                ))
                .labelsHidden()
                .accessibilityIdentifier(Chaos.locator("login_biometric_toggle"))
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceLow))

            ErrorBanner(message: error)

            PrimaryButton(text: loading ? tr("signing_in") : tr("sign_in"),
                          icon: "arrow.right.circle",
                          loading: loading,
                          enabled: canSubmit,
                          action: submit)
                .testTag(Chaos.locator("login_submit"))

            if biometricReady {
                SecondaryButton(text: tr("biometric_login_button"), icon: "touchid", enabled: !loading) {
                    Task { await biometricSignIn() }
                }
                .testTag(Chaos.locator("login_biometric"))
            }

            Button {
                username = "cust01"
                password = "Passw0rd!"
                showTestCredentials = true
                error = nil
            } label: {
                Label(tr("use_test_credentials"), systemImage: "flask")
                    .font(AppFont.labelMedium)
                    .foregroundColor(Theme.onSurface)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
            }
            .accessibilityIdentifier("use_test_credentials")

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield").font(.system(size: 14)).foregroundColor(Theme.onSurfaceVariant)
                Text(tr("synthetic_notice")).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
                Spacer(minLength: 0)
            }
        }
        .onSubmit { if canSubmit { submit() } }
    }
}

// MARK: - OTP

struct OtpScreen: View {
    var otpToken: String
    var onBack: () -> Void
    var onVerified: (User) -> Void

    @State private var code = ""
    @State private var error: String?
    @State private var notice: String?
    @State private var loading = false
    @State private var fetching = false

    @MainActor
    private func verify() async {
        loading = true
        error = nil
        let c = code.trimmingCharacters(in: .whitespaces)
        let result = await apiCall { try await ApiClient.shared.verifyOtp(OtpRequest(otpToken: otpToken, code: c)) }
        switch result {
        case .success(let r): onVerified(r.user)
        case .failure(let e): error = e.message
        }
        loading = false
    }

    @MainActor
    private func fetchOtp() async {
        fetching = true
        notice = nil
        error = nil
        let result = await apiCall { try await ApiClient.shared.devOtp(token: otpToken) }
        switch result {
        case .success(let otp):
            code = otp.code
            notice = tr("otp_fetched", otp.code)
        case .failure(let e):
            error = e.message
        }
        fetching = false
    }

    var body: some View {
        AuthScaffold(title: tr("otp_title"), subtitle: tr("otp_subtitle")) {
            AppTextField(label: Chaos.label(tr("code")), text: $code,
                         locator: Chaos.locator("otp_code"),
                         keyboard: .numberPad, capitalization: .never)

            ErrorBanner(message: error)
            SuccessBanner(message: notice)

            PrimaryButton(text: loading ? tr("verifying") : tr("verify"),
                          loading: loading,
                          enabled: !loading && !code.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task { await verify() }
            }
            .testTag("otp_verify")

            Button(action: onBack) {
                Label(tr("back"), systemImage: "arrow.backward").font(AppFont.labelLarge)
            }
            .disabled(loading)
            .accessibilityIdentifier("otp_back")

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flask").foregroundColor(Brand.teal).font(.system(size: 16))
                    Text(tr("dev_tools")).font(AppFont.labelMedium).foregroundColor(Theme.onSurface)
                    Spacer(minLength: 0)
                }
                SecondaryButton(text: fetching ? tr("fetching_otp") : tr("dev_fetch_otp"), enabled: !fetching) {
                    Task { await fetchOtp() }
                }
                .testTag("otp_dev_fetch")
                Button {
                    notice = tr("otp_resend_notice")
                } label: {
                    Text(tr("resend_code")).font(AppFont.labelLarge)
                }
                .accessibilityIdentifier("otp_resend")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surfaceLow))
        }
        .onSubmit { if !loading && !code.trimmingCharacters(in: .whitespaces).isEmpty { Task { await verify() } } }
    }
}
