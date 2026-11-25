import SwiftUI

private func todayStringSO() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

struct StandingOrderScreen: View {
    var body: some View {
        Loadable(key: "standing-orders", load: {
            await apiCall { () async throws -> StandingOrderData in
                let accounts = try await ApiClient.shared.accounts(page: 1, pageSize: 100)
                let beneficiaries = try await ApiClient.shared.beneficiaries(pageSize: 100)
                let orders = try await ApiClient.shared.standingOrders()
                return StandingOrderData(accounts: accounts, beneficiaries: beneficiaries, orders: orders)
            }
        }) { data in
            StandingOrderContent(accounts: data.accounts, beneficiaries: data.beneficiaries, initialOrders: data.orders.items)
        }
    }
}

private struct StandingOrderData {
    var accounts: AccountPage
    var beneficiaries: BeneficiaryPage
    var orders: StandingOrderPage
}

private struct StandingOrderContent: View {
    let accounts: AccountPage
    let beneficiaries: BeneficiaryPage

    @State private var orders: [StandingOrder]
    @State private var error: String?
    @State private var notice: String?
    @State private var saving = false
    @State private var fromAccountId: String
    @State private var beneficiaryId: String
    @State private var amount = "12.50"
    @State private var frequency = "monthly"
    @State private var firstRunOn = todayStringSO()
    @State private var endOn = ""
    @State private var reference = ""

    init(accounts: AccountPage, beneficiaries: BeneficiaryPage, initialOrders: [StandingOrder]) {
        self.accounts = accounts
        self.beneficiaries = beneficiaries
        _orders = State(initialValue: initialOrders)
        _fromAccountId = State(initialValue: accounts.items.first?.id ?? "")
        _beneficiaryId = State(initialValue: beneficiaries.items.first?.id ?? "")
    }

    var body: some View {
        PageScroll {
            ScreenHeader(title: tr("title_standing"), subtitle: tr("subtitle_standing"))
            ErrorBanner(message: error)
            SuccessBanner(message: notice)

            SectionCard(title: tr("create_standing_order"), icon: "repeat") {
                Selector(
                    label: tr("from_account"),
                    selectedLabel: accounts.items.first(where: { $0.id == fromAccountId })?.name ?? tr("select_account"),
                    options: accounts.items.map { ($0.id, $0.name) },
                    locator: "standing_from_account",
                    onSelected: { fromAccountId = $0 }
                )
                Selector(
                    label: tr("beneficiary"),
                    selectedLabel: beneficiaries.items.first(where: { $0.id == beneficiaryId })?.name ?? tr("select_beneficiary"),
                    options: beneficiaries.items.map { ($0.id, $0.name) },
                    locator: "standing_beneficiary",
                    onSelected: { beneficiaryId = $0 }
                )
                AppTextField(label: tr("amount"), text: $amount, locator: Chaos.locator("standing_amount"), keyboard: .decimalPad)
                Selector(
                    label: tr("frequency"),
                    selectedLabel: frequencyLabel(frequency),
                    options: ["weekly", "monthly", "quarterly", "yearly"].map { ($0, frequencyLabel($0)) },
                    locator: "standing_frequency",
                    onSelected: { frequency = $0 }
                )
                AppTextField(label: tr("first_run"), text: $firstRunOn, locator: Chaos.locator("standing_first_run"),
                             keyboard: .numbersAndPunctuation, capitalization: .never)
                AppTextField(label: tr("end_date_optional"), text: $endOn, locator: Chaos.locator("standing_end_date"),
                             keyboard: .numbersAndPunctuation, capitalization: .never)
                AppTextField(label: tr("reference"), text: $reference, locator: Chaos.locator("standing_reference"))
                PrimaryButton(text: saving ? tr("creating") : tr("create_standing_order"), enabled: !saving) {
                    create()
                }
                .accessibilityIdentifier(Chaos.locator("standing_create"))
            }

            Text(tr("existing_orders")).font(AppFont.titleMedium).foregroundColor(Theme.onSurface)

            ForEach(orders) { order in
                SectionCard(title: tr("order_label", order.id), icon: "repeat") {
                    Text(order.beneficiaryName ?? order.beneficiaryId)
                        .font(AppFont.bodyMedium).fontWeight(.bold).foregroundColor(Theme.onSurface)
                    StatusPill(status: order.status)
                    SODetailRow(label: tr("amount"), value: formatMinor(order.amountMinor, order.currency))
                    SODetailRow(label: tr("frequency"), value: frequencyLabel(order.frequency))
                    SODetailRow(label: tr("next_run"), value: order.nextRunOn)
                    SODetailRow(label: tr("reference"), value: order.reference ?? "—")
                    if order.status.lowercased() == "active" {
                        SecondaryButton(text: tr("cancel_order")) { cancel(order) }
                            .accessibilityIdentifier(Chaos.locator("standing_cancel_\(order.id)"))
                    }
                }
            }
        }
    }

    @MainActor
    private func create() {
        guard let value = Double(amount), Int64(value * 100) > 0,
              !fromAccountId.isEmpty, !beneficiaryId.isEmpty else {
            error = tr("standing_validation")
            return
        }
        let amountMinor = Int64(value * 100)
        let trimmedEnd = endOn.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRef = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = StandingOrderRequest(
            fromAccountId: fromAccountId,
            beneficiaryId: beneficiaryId,
            amountMinor: amountMinor,
            currency: "EUR",
            frequency: frequency,
            firstRunOn: firstRunOn.trimmingCharacters(in: .whitespacesAndNewlines),
            endOn: trimmedEnd.isEmpty ? nil : trimmedEnd,
            reference: trimmedRef.isEmpty ? nil : trimmedRef
        )
        Task { @MainActor in
            await requestApproval {
                Task { @MainActor in
                    saving = true
                    error = nil
                    switch await apiCall({ try await ApiClient.shared.createStandingOrder(request) }) {
                    case .success(let order):
                        orders = [order] + orders
                        notice = tr("standing_created", order.id)
                    case .failure(let e):
                        error = e.message
                    }
                    saving = false
                }
            }
        }
    }

    @MainActor
    private func cancel(_ order: StandingOrder) {
        Task { @MainActor in
            await requestApproval {
                Task { @MainActor in
                    error = nil
                    switch await apiCall({ try await ApiClient.shared.cancelStandingOrder(id: order.id) }) {
                    case .success:
                        orders = orders.filter { $0.id != order.id }
                        notice = tr("standing_cancelled", order.id)
                    case .failure(let e):
                        error = e.message
                    }
                }
            }
        }
    }
}

private struct SODetailRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(Theme.onSurfaceVariant)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundColor(Theme.onSurface)
        }
        .font(AppFont.bodyMedium)
    }
}
