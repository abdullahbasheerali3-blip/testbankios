import SwiftUI

enum AppTab: CaseIterable {
    case overview, payments, cards, borrow, more

    var labelKey: String {
        switch self {
        case .overview: return "nav_overview"
        case .payments: return "nav_pay"
        case .cards: return "nav_cards"
        case .borrow: return "nav_borrow"
        case .more: return "nav_more"
        }
    }
}

private func greeting() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    if hour < 12 { return tr("greet_morning") }
    if hour < 18 { return tr("greet_afternoon") }
    return tr("greet_evening")
}

struct DashboardScreen: View {
    var displayName: String
    var onOpenTab: (AppTab) -> Void = { _ in }

    var body: some View {
        Loadable(key: "dashboard", load: {
            await apiCall { () async throws -> DashboardData in
                let summary = try await ApiClient.shared.accountSummary()
                let accounts = try await ApiClient.shared.accounts(limit: 6)
                return DashboardData(summary: summary, accounts: accounts)
            }
        }) { data in
            DashboardContent(displayName: displayName, data: data, onOpenTab: onOpenTab)
        }
        .background(Theme.background)
    }
}

private struct DashboardData {
    var summary: AccountSummary
    var accounts: AccountPage
}

private struct DashboardContent: View {
    var displayName: String
    var data: DashboardData
    var onOpenTab: (AppTab) -> Void
    @State private var hidden = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                quickActions
                HStack {
                    Text(tr("your_accounts")).font(AppFont.titleLarge).foregroundColor(Theme.onSurface)
                    Spacer()
                    Text(tr("total_n", data.accounts.items.count)).font(AppFont.bodyMedium).foregroundColor(Theme.onSurfaceVariant)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Array(data.accounts.items.enumerated()), id: \.offset) { index, account in
                        if index > 0 {
                            Divider().padding(.leading, 76)
                        }
                        AccountRow(account: account, hidden: hidden)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.outlineVariant, lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
    }

    private var hero: some View {
        let balances = data.summary.balances
        return ZStack(alignment: .topLeading) {
            Brand.heroVertical
            SkylineStrip().frame(maxHeight: .infinity, alignment: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(greeting()),").font(AppFont.bodyLarge).foregroundColor(Color.white.opacity(0.75))
                Text(displayName.isEmpty ? tr("customer") : displayName)
                    .font(AppFont.headlineMedium).foregroundColor(.white)
                Spacer().frame(height: 22)
                HStack {
                    Text(tr("total_position")).font(AppFont.labelLarge).foregroundColor(Color.white.opacity(0.75))
                    Spacer()
                    Button {
                        hidden.toggle()
                    } label: {
                        Image(systemName: hidden ? "eye.slash" : "eye")
                            .foregroundColor(Color.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(hidden ? tr("show_balances") : tr("hide_balances"))
                    .accessibilityIdentifier("toggle_balances")
                }
                if let primary = balances.first {
                    Text(hidden ? "•••••• \(primary.currency)" : Chaos.displayAmount(primary.totalMinor, primary.currency))
                        .font(AppFont.displaySmall).foregroundColor(.white)
                        .accessibilityIdentifier("total_balance")
                    Text(primary.accounts == 1 ? tr("one_account") : tr("n_accounts", primary.accounts))
                        .font(AppFont.bodyMedium).foregroundColor(Color.white.opacity(0.7))
                }
                ForEach(Array(balances.dropFirst().enumerated()), id: \.offset) { _, balance in
                    HStack {
                        Text(tr("currency_accounts", balance.currency, balance.accounts))
                            .font(AppFont.bodyMedium).foregroundColor(Color.white.opacity(0.85))
                        Spacer()
                        Text(hidden ? "••••••" : Chaos.displayAmount(balance.totalMinor, balance.currency))
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedCornerBottom(radius: 32))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickAction(systemName: "paperplane.fill", label: tr("qa_send"), tint: Brand.royal) { onOpenTab(.payments) }
            QuickAction(systemName: "creditcard.fill", label: tr("nav_cards"), tint: Brand.violet) { onOpenTab(.cards) }
            QuickAction(systemName: "banknote", label: tr("nav_borrow"), tint: Brand.teal) { onOpenTab(.borrow) }
            QuickAction(systemName: "square.grid.2x2.fill", label: tr("nav_more"), tint: Brand.amber) { onOpenTab(.more) }
        }
        .padding(.horizontal, 16)
    }
}

private struct RoundedCornerBottom: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.bottomLeft, .bottomRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

private struct QuickAction: View {
    var systemName: String
    var label: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                IconBadge(systemName: systemName, tint: tint, size: 46)
                Text(label).font(AppFont.labelMedium).foregroundColor(Theme.onSurface).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick_action_\(label)")
    }
}

private struct AccountRow: View {
    var account: Account
    var hidden: Bool

    var body: some View {
        let isSavings = account.type.lowercased().contains("sav")
        HStack(spacing: 14) {
            IconBadge(systemName: isSavings ? "banknote" : "wallet.pass.fill",
                      tint: isSavings ? Brand.teal : Brand.royal, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(AppFont.titleMedium).foregroundColor(Theme.onSurface).lineLimit(1)
                Text("\(accountTypeLabel(account.type)) · \(maskIban(account.iban))")
                    .font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Text(hidden ? "••••••" : Chaos.displayAmount(account.balanceMinor, account.currency))
                .font(AppFont.titleSmall).foregroundColor(Theme.onSurface)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
