import SwiftUI

private func todayString() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

struct PaymentScreen: View {
    @State private var accounts: [Account] = []
    @State private var beneficiaries: [Beneficiary] = []
    @State private var fromAccountId = ""
    @State private var beneficiaryId = ""
    @State private var amount = ""
    @State private var reference = ""
    @State private var executeOn = todayString()
    @State private var loadError: String?
    @State private var error: String?
    @State private var submitting = false
    @State private var created: Payment?
    @State private var status = ""

    private var accountOptions: [(String, String)] {
        accounts.map { ($0.id, "\($0.name) · \(formatMinor($0.balanceMinor, $0.currency))") }
    }

    private var beneficiaryOptions: [(String, String)] {
        beneficiaries.map { ($0.id, "\($0.name) · \(maskIban($0.iban))") }
    }

    private var currentCurrency: String {
        accounts.first(where: { $0.id == fromAccountId })?.currency ?? "EUR"
    }

    var body: some View {
        PageScroll {
            SectionCard(title: tr("pay_who_from"), icon: "arrow.left.arrow.right") {
                Selector(
                    label: tr("from_account"),
                    selectedLabel: accountOptions.first(where: { $0.0 == fromAccountId })?.1 ?? tr("select_account"),
                    options: accountOptions,
                    locator: "payment_from_account",
                    onSelected: { fromAccountId = $0 }
                )
                Selector(
                    label: tr("beneficiary"),
                    selectedLabel: beneficiaryOptions.first(where: { $0.0 == beneficiaryId })?.1 ?? tr("select_beneficiary"),
                    options: beneficiaryOptions,
                    locator: "payment_beneficiary",
                    onSelected: { beneficiaryId = $0 }
                )
            }

            SectionCard(title: tr("pay_how_much"), icon: "banknote") {
                amountField
                AppTextField(label: tr("reference_optional"), text: $reference, locator: Chaos.locator("payment_reference"))
                AppTextField(label: tr("execution_date"), text: $executeOn, locator: Chaos.locator("payment_execute_on"),
                             keyboard: .numbersAndPunctuation, capitalization: .never)
            }

            ErrorBanner(message: loadError, title: tr("load_accounts_error"))
            ErrorBanner(message: error, title: tr("payment_not_sent"))

            PrimaryButton(text: submitting ? tr("submitting") : tr("submit_payment"),
                          icon: "paperplane.fill",
                          loading: submitting,
                          enabled: !submitting) {
                submit()
            }
            .accessibilityIdentifier(Chaos.locator("payment_submit"))

            if let payment = created { resultCard(payment) }

            Text(tr("payments_footer"))
                .font(AppFont.bodySmall)
                .foregroundColor(Theme.onSurfaceVariant)
                .padding(.top, 8)
        }
        .task { await load() }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("amount")).font(AppFont.labelMedium).foregroundColor(Theme.onSurfaceVariant)
            HStack(spacing: 8) {
                Text(currentCurrency).font(AppFont.titleLarge).foregroundColor(Theme.onSurfaceVariant)
                TextField("0.00", text: $amount)
                    .font(AppFont.headlineSmall)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(Chaos.locator("payment_amount"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceLow))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.outline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func resultCard(_ payment: Payment) -> some View {
        let finalStatus = status.isEmpty ? payment.status : status
        let failed = finalStatus.lowercased() == "failed"
        VStack(spacing: 8) {
            Image(systemName: failed ? "exclamationmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(failed ? Theme.error : Theme.tertiary)
            Text(tr("payment_submitted")).font(AppFont.titleLarge).foregroundColor(Theme.onSurface)
            Text(formatMinor(payment.amountMinor, payment.currency)).font(AppFont.headlineMedium).foregroundColor(Theme.onSurface)
            StatusPill(status: finalStatus)
            Group {
                Text(tr("id_label", payment.id))
                Text(tr("status_label", statusLabel(finalStatus)))
                Text(tr("amount_label", formatMinor(payment.amountMinor, payment.currency)))
                if !payment.reference.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(tr("reference_label", payment.reference))
                }
            }
            .font(AppFont.bodySmall)
            .foregroundColor(Theme.onSurface)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(failed ? Theme.errorContainer : Theme.tertiaryContainer))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("payment_result")
    }

    @MainActor
    private func load() async {
        switch await apiCall({ try await ApiClient.shared.accounts(page: 1, pageSize: 100) }) {
        case .success(let page):
            accounts = page.items
            fromAccountId = page.items.first?.id ?? ""
        case .failure(let e):
            loadError = e.message
        }
        switch await apiCall({ try await ApiClient.shared.beneficiaries(pageSize: 100) }) {
        case .success(let page):
            let active = page.items.filter { $0.status.lowercased() == "active" }
            beneficiaries = active
            beneficiaryId = active.first?.id ?? ""
        case .failure(let e):
            loadError = e.message
        }
    }

    @MainActor
    private func submit() {
        let amountMinor = Int64((Double(amount) ?? 0.0) * 100)
        error = nil
        if fromAccountId.isEmpty || beneficiaryId.isEmpty || amountMinor <= 0 {
            error = tr("pay_validation")
            return
        }
        created = nil
        status = ""
        let selected = beneficiaryOptions.first(where: { $0.0 == beneficiaryId })?.1
        let beneficiaryName: String = selected.map { String($0.components(separatedBy: " · ").first ?? $0) } ?? tr("your_beneficiary")
        let request = PaymentRequest(
            fromAccountId: fromAccountId,
            beneficiaryId: beneficiaryId,
            amountMinor: amountMinor,
            currency: currentCurrency,
            reference: reference,
            executeOn: executeOn,
            idempotencyKey: "idem-\(Int(Date().timeIntervalSince1970 * 1000))"
        )
        Task { @MainActor in
            await requestApproval {
                submitting = true
                Task { @MainActor in
                    let result = await apiCall { try await ApiClient.shared.createPayment(request) }
                    switch result {
                    case .success(let payment):
                        LocalNotifier.schedule(
                            title: tr("payment_submitted"),
                            message: tr("notif_payment_body", formatMinor(payment.amountMinor, payment.currency), beneficiaryName)
                        )
                        created = payment
                        var current = payment.status
                        for _ in 0..<5 {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            if case .success(let s) = await apiCall({ try await ApiClient.shared.paymentStatus(id: payment.id) }) {
                                current = s.status
                            }
                            let lower = current.lowercased()
                            if lower == "completed" || lower == "failed" { break }
                        }
                        status = current
                    case .failure(let e):
                        error = e.message
                    }
                    submitting = false
                }
            }
        }
    }
}
