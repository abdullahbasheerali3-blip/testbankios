import SwiftUI

struct LoansScreen: View {
    var initialSection: Int = 0

    var body: some View {
        Loadable(key: "loans", load: {
            await apiCall { () async throws -> LoansPayload in
                let products = try await ApiClient.shared.loanProducts()
                let loans = try await ApiClient.shared.loans()
                let apps = try await ApiClient.shared.loanApplications()
                return LoansPayload(products: products, loans: loans.items, applications: apps.items)
            }
        }) { (payload: LoansPayload) in
            LoansContent(payload: payload, initialSection: initialSection)
        }
        .background(Theme.background)
    }
}

private struct LoansPayload {
    var products: [LoanProduct]
    var loans: [Loan]
    var applications: [LoanApplication]
}

private struct LoansContent: View {
    let products: [LoanProduct]
    let loans: [Loan]

    @State private var applications: [LoanApplication]
    @State private var section: Int
    @State private var error: String?
    @State private var notice: String?
    @State private var saving = false

    @State private var calculatorProductId: String
    @State private var calculatorAmount = "5000"
    @State private var calculatorTerm = "36"
    @State private var applyProductId: String
    @State private var applyAmount = "5000"
    @State private var applyTerm = "36"
    @State private var purpose = ""

    init(payload: LoansPayload, initialSection: Int) {
        products = payload.products
        loans = payload.loans
        _applications = State(initialValue: payload.applications)
        _section = State(initialValue: min(max(initialSection, 0), 4))
        _calculatorProductId = State(initialValue: payload.products.first?.id ?? "")
        _applyProductId = State(initialValue: payload.products.first?.id ?? "")
    }

    private var sectionLabels: [String] {
        [tr("overview"), tr("products"), tr("calculator"), tr("apply"), tr("applications")]
    }

    private var activeCalculatorProduct: LoanProduct? {
        products.first(where: { $0.id == calculatorProductId }) ?? products.first
    }

    private var activeApplyProduct: LoanProduct? {
        products.first(where: { $0.id == applyProductId }) ?? products.first
    }

    private func majorString(_ minor: Int64) -> String { String(Double(minor) / 100.0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: tr("title_loans"), subtitle: tr("subtitle_loans"))
                SegmentedTabs(options: sectionLabels, selected: $section)
                ErrorBanner(message: error)
                SuccessBanner(message: notice)
                switch section {
                case 0: overview
                case 1: productsList
                case 2: calculator
                case 3: applyForm
                default: applicationsList
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        if loans.isEmpty {
            EmptyState(systemName: "banknote", title: tr("active_loans"), message: tr("no_active_loans"))
        } else {
            ForEach(loans) { loan in
                SectionCard(title: tr("loan_label", loan.id), icon: "banknote") {
                    Text(capitalizedFirst(loan.product)).font(AppFont.bodyMedium).fontWeight(.bold).foregroundColor(Theme.onSurface)
                    StatusPill(status: loan.status)
                    detailRow(tr("outstanding"), formatMinor(loan.outstandingMinor, loan.currency))
                    detailRow(tr("principal"), formatMinor(loan.principalMinor, loan.currency))
                    detailRow(tr("term"), tr("n_months", Int32(loan.termMonths)))
                    detailRow(tr("next_payment"), loan.nextPaymentOn.isEmpty ? "—" : loan.nextPaymentOn)
                }
            }
        }
    }

    // MARK: Products

    @ViewBuilder private var productsList: some View {
        ForEach(products) { product in
            SectionCard(title: product.name, icon: "banknote") {
                detailRow(tr("rate"), tr("rate_apr", String(Double(product.rateBps) / 100.0)))
                detailRow(tr("amount"), tr("amount_range", formatMinor(product.minMinor, "EUR"), formatMinor(product.maxMinor, "EUR")))
                detailRow(tr("term"), tr("months_range", Int32(product.minTerm), Int32(product.maxTerm)))
                HStack(spacing: 8) {
                    SecondaryButton(text: tr("calculator")) {
                        calculatorProductId = product.id
                        section = 2
                    }
                    .testTag("loan_product_calculator_\(product.id)")
                    PrimaryButton(text: tr("apply")) {
                        applyProductId = product.id
                        applyAmount = majorString(product.minMinor)
                        applyTerm = String(product.minTerm)
                        section = 3
                    }
                    .testTag("loan_product_apply_\(product.id)")
                }
            }
        }
    }

    // MARK: Calculator

    private var calculator: some View {
        let principal = Double(calculatorAmount) ?? 0
        let months = Int(calculatorTerm) ?? 0
        let monthlyRate = Double(activeCalculatorProduct?.rateBps ?? 0) / 10000.0 / 12.0
        var monthly = 0.0
        if principal > 0 && months > 0 {
            if monthlyRate == 0 {
                monthly = principal / Double(months)
            } else {
                monthly = principal * monthlyRate / (1 - pow(1 + monthlyRate, -Double(months)))
            }
        }
        let monthlyMinor = Int64(monthly * 100)
        let totalMinor = Int64(monthly * Double(months) * 100)
        return SectionCard(title: tr("calculator"), icon: "plus.forwardslash.minus") {
            Selector(
                label: tr("product"),
                selectedLabel: activeCalculatorProduct?.name ?? tr("no_product"),
                options: products.map { ($0.id, $0.name) },
                locator: "loan_calculator_product",
                onSelected: { id in
                    calculatorProductId = id
                    if let p = products.first(where: { $0.id == id }) {
                        calculatorAmount = majorString(p.minMinor)
                        calculatorTerm = String(p.minTerm)
                    }
                }
            )
            AppTextField(label: tr("amount"), text: $calculatorAmount, locator: Chaos.locator("loan_calculator_amount"), keyboard: .decimalPad)
            AppTextField(label: tr("term_months"), text: $calculatorTerm, locator: Chaos.locator("loan_calculator_term"), keyboard: .numberPad)
            detailRow(tr("estimated_monthly"), formatMinor(monthlyMinor, "EUR"))
            detailRow(tr("total_repayable"), formatMinor(totalMinor, "EUR"))
        }
    }

    // MARK: Apply

    private var applyForm: some View {
        SectionCard(title: tr("submit_application")) {
            Selector(
                label: tr("product"),
                selectedLabel: activeApplyProduct?.name ?? tr("no_product"),
                options: products.map { ($0.id, $0.name) },
                locator: "loan_apply_product",
                onSelected: { id in
                    applyProductId = id
                    if let p = products.first(where: { $0.id == id }) {
                        applyAmount = majorString(p.minMinor)
                        applyTerm = String(p.minTerm)
                    }
                }
            )
            AppTextField(label: tr("amount"), text: $applyAmount, locator: Chaos.locator("loan_apply_amount"), keyboard: .decimalPad)
            AppTextField(label: tr("term_months"), text: $applyTerm, locator: Chaos.locator("loan_apply_term"), keyboard: .numberPad)
            AppTextField(label: tr("purpose"), text: $purpose, locator: Chaos.locator("loan_apply_purpose"))
            PrimaryButton(text: saving ? tr("submitting") : tr("submit_application"), enabled: !saving) {
                submitApplication()
            }
            .testTag(Chaos.locator("loan_apply_submit"))
        }
    }

    private func submitApplication() {
        guard let product = activeApplyProduct,
              let amountDouble = Double(applyAmount),
              let term = Int(applyTerm) else {
            error = tr("loan_valid_amount_term")
            return
        }
        let amountMinor = Int64(amountDouble * 100)
        if amountMinor < product.minMinor || amountMinor > product.maxMinor {
            error = tr("loan_amount_between", formatMinor(product.minMinor, "EUR"), formatMinor(product.maxMinor, "EUR"))
            return
        }
        if term < product.minTerm || term > product.maxTerm {
            error = tr("loan_term_between", Int32(product.minTerm), Int32(product.maxTerm))
            return
        }
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = LoanApplicationRequest(
            product: product.id,
            amountMinor: amountMinor,
            currency: "EUR",
            termMonths: term,
            purpose: trimmedPurpose.isEmpty ? tr("loan_default_purpose") : purpose
        )
        Task { @MainActor in
            await requestApproval {
                Task { @MainActor in
                    saving = true
                    error = nil
                    switch await apiCall({ try await ApiClient.shared.applyForLoan(request) }) {
                    case .success(let created):
                        applications = [created] + applications
                        notice = tr("loan_submitted", created.id)
                        section = 4
                    case .failure(let e):
                        error = e.message
                    }
                    saving = false
                }
            }
        }
    }

    // MARK: Applications

    @ViewBuilder private var applicationsList: some View {
        if applications.isEmpty {
            EmptyState(systemName: "doc.text.fill", title: tr("applications"), message: tr("no_applications"))
        } else {
            ForEach(applications) { application in
                SectionCard(title: tr("application_label", application.id), icon: "doc.text.fill") {
                    Text(capitalizedFirst(application.product)).font(AppFont.bodyMedium).fontWeight(.bold).foregroundColor(Theme.onSurface)
                    StatusPill(status: application.status)
                    detailRow(tr("amount"), formatMinor(application.amountMinor, application.currency))
                    detailRow(tr("term"), tr("n_months", Int32(application.termMonths)))
                    ForEach(Array(application.timeline.enumerated()), id: \.offset) { _, entry in
                        Text("\(entry.status): \(entry.note)").font(AppFont.bodySmall).foregroundColor(Theme.onSurface)
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(AppFont.bodyMedium).foregroundColor(Theme.onSurfaceVariant)
            Spacer()
            Text(value).font(AppFont.bodyMedium).fontWeight(.semibold).foregroundColor(Theme.onSurface)
        }
    }
}
