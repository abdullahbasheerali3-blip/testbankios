import SwiftUI

struct BeneficiaryScreen: View {
    @State private var beneficiaries: [Beneficiary] = []
    @State private var search = ""
    @State private var statusFilter = "All"
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var showValidation = false
    @State private var saving = false
    @State private var showForm = false
    @State private var editingId: String?
    @State private var formName = ""
    @State private var formNickname = ""
    @State private var formIban = ""
    @State private var formBank = ""
    @State private var formCountry = ""
    @State private var visibleIbans: Set<String> = []
    @State private var deleteTarget: Beneficiary?

    private var statusOptions: [(String, String)] {
        [("All", tr("filter_all")),
         ("Active", tr("st_active")),
         ("Pending", tr("st_pending")),
         ("Blocked", tr("st_blocked"))]
    }

    private var filtered: [Beneficiary] {
        beneficiaries.filter { b in
            let fields = [b.name, b.nickname ?? "", b.iban, b.bankName]
            let textMatch = search.isEmpty || fields.contains(where: { $0.localizedCaseInsensitiveContains(search) })
            let statusMatch = statusFilter == "All" || b.status.lowercased() == statusFilter.lowercased()
            return textMatch && statusMatch
        }
    }

    var body: some View {
        PageScroll {
            ScreenHeader(title: tr("ben_title"), subtitle: tr("ben_subtitle"))

            HStack {
                Text(tr("ben_count", beneficiaries.count))
                    .font(AppFont.bodyMedium)
                    .foregroundColor(Theme.onSurfaceVariant)
                Spacer()
                PrimaryButton(text: tr("ben_add"), icon: "person.badge.plus", fullWidth: false) {
                    resetForm()
                    showForm = true
                }
            }

            if showForm { formCard }

            searchSection

            VStack(spacing: 6) {
                ErrorBanner(message: loadError, title: tr("ben_load_error"))
                ErrorBanner(message: actionError, title: tr("ben_not_saved"))
            }

            if filtered.isEmpty {
                EmptyState(systemName: "person.2.fill",
                           title: tr("ben_none"),
                           message: beneficiaries.isEmpty ? tr("ben_none_yet") : tr("ben_none_match"))
            }

            ForEach(filtered) { beneficiary in
                BeneficiaryRow(
                    beneficiary: beneficiary,
                    ibanVisible: visibleIbans.contains(beneficiary.id),
                    onToggleIban: {
                        if visibleIbans.contains(beneficiary.id) {
                            visibleIbans.remove(beneficiary.id)
                        } else {
                            visibleIbans.insert(beneficiary.id)
                        }
                    },
                    onEdit: { startEditing(beneficiary) },
                    onDelete: { deleteTarget = beneficiary }
                )
            }
        }
        .task { await reload() }
        .alert(tr("ben_delete_title"),
               isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
               presenting: deleteTarget) { target in
            Button(tr("delete"), role: .destructive) { confirmDelete(target) }
            Button(tr("cancel"), role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text(tr("ben_delete_body", target.name))
        }
    }

    // MARK: Sections

    private var formCard: some View {
        SectionCard(title: editingId == nil ? tr("ben_new") : tr("ben_edit")) {
            AppTextField(
                label: tr("ben_name"),
                text: Binding(get: { formName }, set: { formName = $0; actionError = nil }),
                placeholder: tr("ben_name_ph"),
                locator: Chaos.locator("beneficiary_name"),
                helper: (showValidation && isBlank(formName)) ? tr("ben_name_required") : nil
            )
            AppTextField(
                label: tr("ben_nickname"),
                text: Binding(get: { formNickname }, set: { formNickname = $0; actionError = nil }),
                locator: "beneficiary_nickname"
            )
            AppTextField(
                label: tr("ben_iban"),
                text: Binding(get: { formIban }, set: { formIban = $0; actionError = nil }),
                placeholder: tr("ben_iban_ph"),
                locator: Chaos.locator("beneficiary_iban"),
                capitalization: .characters,
                helper: ibanHelper,
                enabled: editingId == nil
            )
            AppTextField(
                label: tr("ben_bank"),
                text: Binding(get: { formBank }, set: { formBank = $0; actionError = nil }),
                locator: "beneficiary_bank"
            )
            AppTextField(
                label: tr("ben_country"),
                text: Binding(get: { formCountry }, set: { formCountry = $0; actionError = nil }),
                placeholder: tr("ben_country_ph"),
                locator: Chaos.locator("beneficiary_country"),
                helper: (showValidation && isBlank(formCountry)) ? tr("ben_country_required") : tr("ben_country_hint")
            )
            HStack(spacing: 12) {
                Button {
                    save()
                } label: {
                    Text(saveLabel)
                        .font(AppFont.labelLarge)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundColor(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(saving ? Theme.primary.opacity(0.4) : Theme.primary))
                }
                .disabled(saving)
                .accessibilityIdentifier(Chaos.locator("beneficiary_save"))

                Button {
                    resetForm()
                } label: {
                    Text(tr("cancel"))
                        .font(AppFont.labelLarge)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundColor(Theme.primary)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.primary.opacity(0.5), lineWidth: 1.5))
                }
                .accessibilityIdentifier("beneficiary_cancel")
            }
        }
    }

    private var searchSection: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("ben_search")).font(AppFont.labelMedium).foregroundColor(Theme.onSurfaceVariant)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(Theme.onSurfaceVariant)
                    TextField(tr("ben_search_ph"), text: $search)
                        .font(AppFont.bodyLarge)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .accessibilityIdentifier(Chaos.locator("beneficiary_search"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceLow))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.outline, lineWidth: 1))
            }
            Selector(
                label: tr("status"),
                selectedLabel: statusOptions.first(where: { $0.0 == statusFilter })?.1 ?? statusFilter,
                options: statusOptions,
                locator: "beneficiary_status_filter",
                onSelected: { statusFilter = $0 }
            )
        }
    }

    // MARK: Logic

    private var saveLabel: String {
        if saving { return tr("ben_saving") }
        return editingId == nil ? tr("ben_save") : tr("ben_save_changes")
    }

    private var ibanHelper: String? {
        if editingId != nil { return tr("ben_iban_locked") }
        if showValidation && isBlank(formIban) { return tr("ben_iban_required") }
        return nil
    }

    private func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    @MainActor
    private func reload() async {
        loadError = nil
        switch await apiCall({ try await ApiClient.shared.beneficiaries(pageSize: 100) }) {
        case .success(let page): beneficiaries = page.items
        case .failure(let e): loadError = e.message
        }
    }

    private func resetForm() {
        editingId = nil
        formName = ""
        formNickname = ""
        formIban = ""
        formBank = ""
        formCountry = ""
        showValidation = false
        actionError = nil
        showForm = false
    }

    private func startEditing(_ b: Beneficiary) {
        editingId = b.id
        formName = b.name
        formNickname = b.nickname ?? ""
        formIban = b.iban
        formBank = b.bankName
        formCountry = b.country
        showValidation = false
        actionError = nil
        showForm = true
    }

    private func validationMessage() -> String? {
        var missing: [String] = []
        if isBlank(formName) { missing.append(tr("ben_missing_name")) }
        if isBlank(formCountry) { missing.append(tr("ben_missing_country")) }
        if editingId == nil && isBlank(formIban) { missing.append(tr("ben_missing_iban")) }
        if missing.isEmpty { return nil }
        let readable: String
        if missing.count == 1 {
            readable = missing[0]
        } else if missing.count == 2 {
            readable = tr("and_join", missing[0], missing[1])
        } else {
            readable = tr("and_join", missing.dropLast().joined(separator: ", "), missing[missing.count - 1])
        }
        return tr("ben_please_enter", readable)
    }

    @MainActor
    private func save() {
        if let message = validationMessage() {
            showValidation = true
            actionError = message
            return
        }
        showValidation = false
        actionError = nil
        let request = BeneficiaryRequest(
            name: formName.trimmingCharacters(in: .whitespacesAndNewlines),
            nickname: trimmedOrNil(formNickname),
            iban: editingId == nil ? formIban.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            bankName: trimmedOrNil(formBank),
            country: formCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let id = editingId
        Task { @MainActor in
            await requestApproval {
                saving = true
                Task { @MainActor in
                    let result: Result<Beneficiary, AppError>
                    if let id {
                        result = await apiCall { try await ApiClient.shared.updateBeneficiary(id: id, request) }
                    } else {
                        result = await apiCall { try await ApiClient.shared.addBeneficiary(request) }
                    }
                    switch result {
                    case .success:
                        if id == nil {
                            LocalNotifier.schedule(title: tr("ben_notif_title"), message: tr("ben_notif_body", request.name))
                        }
                        resetForm()
                        await reload()
                    case .failure(let e):
                        actionError = e.message
                    }
                    saving = false
                }
            }
        }
    }

    @MainActor
    private func confirmDelete(_ target: Beneficiary) {
        deleteTarget = nil
        Task { @MainActor in
            await requestApproval {
                Task { @MainActor in
                    switch await apiCall({ try await ApiClient.shared.deleteBeneficiary(id: target.id) }) {
                    case .success: await reload()
                    case .failure(let e): actionError = e.message
                    }
                }
            }
        }
    }
}

private struct BeneficiaryRow: View {
    var beneficiary: Beneficiary
    var ibanVisible: Bool
    var onToggleIban: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        if let n = beneficiary.nickname { parts.append(n) }
        parts.append(beneficiary.bankName)
        parts.append(beneficiary.country)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Avatar(name: beneficiary.name, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(beneficiary.name).font(AppFont.titleMedium).foregroundColor(Theme.onSurface)
                    Text(subtitle).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                StatusPill(status: beneficiary.status)
            }
            Text(ibanVisible ? beneficiary.iban : maskIban(beneficiary.iban))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Theme.onSurface)
                .padding(.top, 4)
            HStack(spacing: 4) {
                Button(ibanVisible ? tr("hide_iban") : tr("show_iban"), action: onToggleIban)
                    .accessibilityIdentifier("beneficiary_toggle_iban_\(beneficiary.id)")
                Button(tr("edit"), action: onEdit)
                    .accessibilityIdentifier("beneficiary_edit_\(beneficiary.id)")
                Button(tr("delete"), action: onDelete)
                    .accessibilityIdentifier("beneficiary_delete_\(beneficiary.id)")
            }
            .font(AppFont.labelLarge)
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.outlineVariant, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
