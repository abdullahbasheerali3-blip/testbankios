import SwiftUI

struct PaymentsHubScreen: View {
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabs(options: [tr("new_payment"), tr("title_standing")], selected: $section)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            if section == 0 {
                PaymentScreen()
            } else {
                StandingOrderScreen()
            }
        }
        .background(Theme.background)
    }
}

private struct MoreAction {
    var key: String
    var title: String
    var subtitle: String
    var icon: String
    var tint: Color
}

struct MoreHubScreen: View {
    var displayName: String = ""
    var onOpenTab: (AppTab) -> Void
    var onOpenSettings: () -> Void
    var onLogout: () -> Void = {}

    @State private var section = "menu"

    private func open(_ action: MoreAction) {
        switch action.key {
        case "cards": onOpenTab(.cards)
        case "borrow": onOpenTab(.borrow)
        case "settings": onOpenSettings()
        default: section = action.key
        }
    }

    var body: some View {
        Group {
            switch section {
            case "statements":
                SubScreen(title: tr("title_statements"), onBack: { section = "menu" }) { StatementsScreen() }
            case "kyc":
                SubScreen(title: tr("title_kyc"), onBack: { section = "menu" }) { KycScreen() }
            case "standing":
                SubScreen(title: tr("title_standing"), onBack: { section = "menu" }) { StandingOrderScreen() }
            case "beneficiaries":
                SubScreen(title: tr("beneficiaries"), onBack: { section = "menu" }) { BeneficiaryScreen() }
            case "calculator":
                // Android opens LoansScreen(initialSection = 2) (Calculator tab).
                SubScreen(title: tr("calculator"), onBack: { section = "menu" }) { LoansScreen(initialSection: 2) }
            default:
                menu
            }
        }
        .background(Theme.background)
    }

    private var menu: some View {
        let money = [
            MoreAction(key: "statements", title: tr("title_statements"), subtitle: tr("subtitle_statements"), icon: "doc.text.fill", tint: Brand.royal),
            MoreAction(key: "standing", title: tr("title_standing"), subtitle: tr("subtitle_standing"), icon: "repeat", tint: Brand.teal),
            MoreAction(key: "beneficiaries", title: tr("beneficiaries"), subtitle: tr("beneficiaries_subtitle"), icon: "person.2.fill", tint: Brand.violet),
        ]
        let products = [
            MoreAction(key: "cards", title: tr("nav_cards"), subtitle: tr("subtitle_cards"), icon: "creditcard.fill", tint: Brand.rose),
            MoreAction(key: "borrow", title: tr("nav_borrow"), subtitle: tr("subtitle_loans"), icon: "building.columns.fill", tint: Brand.amber),
            MoreAction(key: "calculator", title: tr("calculator"), subtitle: tr("subtitle_loans"), icon: "plus.forwardslash.minus", tint: Brand.mint),
        ]
        let account = [
            MoreAction(key: "kyc", title: tr("title_kyc"), subtitle: tr("subtitle_kyc"), icon: "checkmark.shield.fill", tint: Brand.royal),
            MoreAction(key: "settings", title: tr("settings"), subtitle: tr("settings_subtitle"), icon: "gearshape.fill", tint: Color(hex: 0x64748B)),
        ]
        let logout = [
            MoreAction(key: "logout", title: tr("logout"), subtitle: "", icon: "rectangle.portrait.and.arrow.right", tint: Theme.error),
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Avatar(name: displayName.isEmpty ? "C" : displayName, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName.isEmpty ? tr("customer") : displayName).font(AppFont.titleLarge).foregroundColor(Theme.onSurface)
                        Text(tr("nav_more")).font(AppFont.bodyMedium).foregroundColor(Theme.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

                MenuGroup(title: tr("group_money"), actions: money, onClick: open)
                MenuGroup(title: tr("group_products"), actions: products, onClick: open)
                MenuGroup(title: tr("group_account"), actions: account, onClick: open)
                MenuGroup(title: nil, actions: logout) { _ in onLogout() }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MenuGroup: View {
    var title: String?
    var actions: [MoreAction]
    var onClick: (MoreAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased()).font(AppFont.labelMedium).foregroundColor(Theme.onSurfaceVariant).padding(.leading, 6)
            }
            VStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    if index > 0 {
                        Divider().padding(.leading, 72)
                    }
                    Button { onClick(action) } label: {
                        HStack(spacing: 14) {
                            IconBadge(systemName: action.icon, tint: action.tint, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title).font(AppFont.titleMedium)
                                    .foregroundColor(action.key == "logout" ? Theme.error : Theme.onSurface)
                                if !action.subtitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(action.subtitle).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if action.key != "logout" {
                                Image(systemName: "chevron.right").foregroundColor(Theme.onSurfaceVariant)
                                    .flipsForRightToLeftLayoutDirection(true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("more_\(action.key)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.outlineVariant, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }
}
