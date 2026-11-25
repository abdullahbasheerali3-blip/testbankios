import SwiftUI

@main
struct TestBankApp: App {
    init() {
        Services.shared.bootstrap()
        LocalNotifier.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            RootContainer()
        }
    }
}

/// Rebuilds the whole tree when the language changes and applies RTL for Arabic.
struct RootContainer: View {
    @State private var language = Localizer.shared.language

    var body: some View {
        AppRoot()
            .id(language)
            .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: language))
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .approvalDialog()
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                language = Localizer.shared.language
            }
    }
}

struct AppRoot: View {
    @State private var ready = false
    @State private var authenticated = false
    @State private var otpToken: String?
    @State private var displayName = ""

    private func name(for user: User) -> String {
        if !user.displayName.isEmpty { return user.displayName }
        if !user.username.isEmpty { return user.username }
        return user.email
    }

    var body: some View {
        Group {
            if !ready {
                splash
            } else if authenticated {
                HomeShell(displayName: displayName, onLogout: logout)
            } else if let token = otpToken {
                OtpScreen(otpToken: token, onBack: { otpToken = nil }, onVerified: { user in
                    displayName = name(for: user)
                    authenticated = true
                    otpToken = nil
                })
            } else {
                LoginScreen(onOtpRequired: { otpToken = $0 }, onAuthenticated: { user in
                    displayName = name(for: user)
                    authenticated = true
                    otpToken = nil
                })
            }
        }
        .task { await bootstrap() }
    }

    private var splash: some View {
        HeroBackground(skyline: true) {
            VStack(spacing: 0) {
                AppLogo(size: 84)
                Text(tr("app_name")).font(AppFont.headlineSmall).foregroundColor(.white).padding(.top, 18)
                ProgressView().tint(.white).scaleEffect(1.2).padding(.top, 28)
            }
        }
    }

    private func bootstrap() async {
        authenticated = !(Services.shared.session.cookie ?? "").isEmpty
        if authenticated {
            switch await apiCall({ try await ApiClient.shared.me() }) {
            case .success(let user): displayName = name(for: user)
            case .failure: authenticated = false
            }
        }
        ready = true
    }

    private func logout() {
        Task {
            _ = try? await ApiClient.shared.logout()
            Services.shared.session.clear()
            authenticated = false
            displayName = ""
            otpToken = nil
        }
    }
}

struct HomeShell: View {
    var displayName: String
    var onLogout: () -> Void

    @State private var tab: AppTab = .overview
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Theme.background
                if showSettings {
                    SettingsScreen()
                } else {
                    switch tab {
                    case .overview: DashboardScreen(displayName: displayName, onOpenTab: { tab = $0 })
                    case .payments: PaymentsHubScreen()
                    case .cards: CardsScreen()
                    case .borrow: LoansScreen()
                    case .more:
                        MoreHubScreen(displayName: displayName,
                                      onOpenTab: { tab = $0 },
                                      onOpenSettings: { showSettings = true },
                                      onLogout: onLogout)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            AppLogo(size: 36)
            Text(tr("app_name")).font(AppFont.titleMedium).foregroundColor(.white)
            Spacer()
            topBarAction("gearshape.fill", label: tr("settings"), id: "top_settings") { showSettings = true }
            topBarAction("rectangle.portrait.and.arrow.right", label: tr("logout"), id: "top_logout", action: onLogout)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Brand.navy.ignoresSafeArea(edges: .top))
    }

    private func topBarAction(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(Color.white.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: icon).font(.system(size: 16)).foregroundColor(.white))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                let selected = !showSettings && tab == item
                Button {
                    showSettings = false
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon(for: item, selected: selected))
                            .font(.system(size: 20))
                            .frame(width: 56, height: 30)
                            .background(Capsule().fill(selected ? Theme.primaryContainer : Color.clear))
                        Text(tr(item.labelKey)).font(AppFont.labelMedium)
                    }
                    .foregroundColor(selected ? Theme.primary : Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nav_\(String(describing: item))")
                .accessibilityLabel(tr(item.labelKey))
            }
        }
        .background(Theme.surface.shadow(color: .black.opacity(0.12), radius: 8, y: -2).ignoresSafeArea(edges: .bottom))
    }

    private func icon(for tab: AppTab, selected: Bool) -> String {
        switch tab {
        case .overview: return selected ? "house.fill" : "house"
        case .payments: return selected ? "creditcard.and.123" : "creditcard.and.123"
        case .cards: return selected ? "creditcard.fill" : "creditcard"
        case .borrow: return selected ? "banknote.fill" : "banknote"
        case .more: return selected ? "square.grid.2x2.fill" : "square.grid.2x2"
        }
    }
}
