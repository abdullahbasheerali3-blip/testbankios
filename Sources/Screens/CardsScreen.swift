import SwiftUI

struct CardsScreen: View {
    var body: some View {
        Loadable(key: "cards", load: { await apiCall { try await ApiClient.shared.cards() } }) { (page: CardPage) in
            CardsContent(initial: page.items)
        }
        .background(Theme.background)
    }
}

private struct CardsContent: View {
    @State private var cards: [BankCard]
    @State private var actionError: String?

    init(initial: [BankCard]) {
        _cards = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    ScreenHeader(title: tr("title_cards"), subtitle: tr("subtitle_cards"))
                    ErrorBanner(message: actionError)
                }
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    VStack(spacing: 12) {
                        CardVisual(card: card, index: index)
                        cardActionRow(card)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isActive(_ card: BankCard) -> Bool {
        card.status.lowercased() == "active"
    }

    private func cardActionRow(_ card: BankCard) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTypeLabel(card.type)).font(AppFont.titleMedium).foregroundColor(Theme.onSurface)
                Text(tr("linked_account", card.accountId)).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            if isActive(card) {
                SecondaryButton(text: tr("freeze"), icon: "snowflake", fullWidth: false) {
                    toggle(card, freeze: true)
                }
                .frame(height: 44)
                .testTag(Chaos.locator("card_freeze_\(card.id)"))
            } else {
                PrimaryButton(text: tr("unfreeze"), icon: "lock.open.fill", fullWidth: false) {
                    toggle(card, freeze: false)
                }
                .frame(height: 44)
                .testTag(Chaos.locator("card_unfreeze_\(card.id)"))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.outlineVariant, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func toggle(_ card: BankCard, freeze: Bool) {
        let cardId = card.id
        Task { @MainActor in
            await requestApproval {
                Task { @MainActor in
                    actionError = nil
                    let result = await apiCall { () async throws -> BankCard in
                        freeze ? try await ApiClient.shared.freezeCard(id: cardId) : try await ApiClient.shared.unfreezeCard(id: cardId)
                    }
                    switch result {
                    case .success(let updated):
                        cards = cards.map { $0.id == updated.id ? updated : $0 }
                    case .failure(let e):
                        actionError = e.message
                    }
                }
            }
        }
    }
}

private func cardGradient(_ card: BankCard, _ index: Int) -> LinearGradient {
    let colors: [Color]
    if card.status.lowercased() != "active" {
        colors = [Color(hex: 0x4B5563), Color(hex: 0x1F2937)]
    } else if card.type.lowercased() == "credit" {
        colors = [Color(hex: 0x1B1035), Color(hex: 0x4C2A9A), Brand.violet]
    } else if index % 2 == 1 {
        colors = [Color(hex: 0x053B3A), Color(hex: 0x0C7C73), Brand.teal]
    } else {
        colors = [Brand.navy, Brand.navyMid, Brand.royal]
    }
    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct CardVisual: View {
    let card: BankCard
    let index: Int

    private var frozen: Bool { card.status.lowercased() != "active" }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(cardGradient(card, index))
            Canvas { ctx, size in
                let c = CGPoint(x: size.width * 0.92, y: size.height * 0.10)
                for i in 1...4 {
                    let r = size.width * (0.12 + CGFloat(i) * 0.11)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(Color.white.opacity(0.08)), lineWidth: 1.5)
                }
                let r2 = size.width * 0.28
                ctx.fill(Path(ellipseIn: CGRect(x: -r2, y: size.height - r2, width: r2 * 2, height: r2 * 2)),
                         with: .color(Color.white.opacity(0.06)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack(alignment: .leading) {
                HStack {
                    Text(tr("app_name").uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white)
                    Spacer()
                    StatusPill(status: card.status)
                        .background(Capsule().fill(Color.white))
                }
                Spacer()
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color(hex: 0xFFE08A), Color(hex: 0xD9A441)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 32)
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 22))
                        .foregroundColor(Color.white.opacity(0.85))
                }
                Spacer()
                Text(card.maskedPan)
                    .font(.system(size: 21, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("card_holder")).font(AppFont.labelSmall).foregroundColor(Color.white.opacity(0.6))
                        Text(card.holderName.uppercased()).font(AppFont.labelLarge).foregroundColor(.white).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("card_expires")).font(AppFont.labelSmall).foregroundColor(Color.white.opacity(0.6))
                        Text(card.expiry).font(AppFont.labelLarge).foregroundColor(.white)
                    }
                    .padding(.trailing, 14)
                    ZStack(alignment: .leading) {
                        Circle().fill(Color(hex: 0xEB5757).opacity(0.95)).frame(width: 30, height: 30)
                        Circle().fill(Brand.amber.opacity(0.9)).frame(width: 30, height: 30).offset(x: 16)
                    }
                    .frame(width: 46, height: 30)
                }
                .padding(.top, 10)
            }
            .padding(22)

            if frozen {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x111827).opacity(0.35))
                VStack(spacing: 8) {
                    Circle().fill(Color.white.opacity(0.18)).frame(width: 56, height: 56)
                        .overlay(Image(systemName: "lock.fill").font(.system(size: 26)).foregroundColor(.white))
                    Text(tr("card_frozen")).font(AppFont.titleSmall).foregroundColor(.white)
                }
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: Brand.navy.opacity(0.35), radius: 12, y: 6)
    }
}
