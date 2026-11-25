import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private let kycDocumentKinds: [(String, String)] = [
    ("id-front", "kyc_doc_id_front"),
    ("id-back", "kyc_doc_id_back"),
    ("proof-of-address", "kyc_doc_poa"),
    ("selfie", "kyc_doc_selfie"),
]
private let kycEmploymentStatuses = ["employed", "self-employed", "unemployed", "student"]

private func kycEmploymentLabel(_ status: String) -> String {
    switch status {
    case "employed": return tr("emp_employed")
    case "self-employed": return tr("emp_self_employed")
    case "unemployed": return tr("emp_unemployed")
    case "student": return tr("emp_student")
    default: return capitalizedFirst(status)
    }
}

/// Runs a synchronous KycStore call and maps thrown errors to a user-facing message.
private func kycRun<T>(_ block: () throws -> T) -> Result<T, AppError> {
    do {
        return .success(try block())
    } catch {
        return .failure(AppError(message: errorMessage(error)))
    }
}

struct KycScreen: View {
    @State private var reloadKey = 0
    @State private var showRestart = false

    var body: some View {
        Loadable(key: "kyc-\(reloadKey)", load: {
            let store = Services.shared.kyc
            return kycRun { KycSnapshot(app: store.kyc(), docs: store.kycDocuments().items) }
        }) { (snap: KycSnapshot) in
            KycContent(snapshot: snap, onRestart: { showRestart = true })
        }
        .background(Theme.background)
        .alert(tr("kyc_restart_title"), isPresented: $showRestart) {
            Button(tr("kyc_restart"), role: .destructive) {
                Services.shared.kyc.reset()
                reloadKey += 1
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: {
            Text(tr("kyc_restart_body"))
        }
    }
}

private struct KycSnapshot {
    var app: KycApplication
    var docs: [KycDocument]
}

private struct KycContent: View {
    let onRestart: () -> Void

    @State private var app: KycApplication
    @State private var docs: [KycDocument]
    @State private var section: Int
    @State private var error: String?
    @State private var notice: String?
    @State private var uploadError: String?
    @State private var saving = false

    @State private var pendingKind: String?
    @State private var showSourceDialog = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    @State private var firstName: String
    @State private var lastName: String
    @State private var dateOfBirth: String
    @State private var nationality: String
    @State private var street: String
    @State private var city: String
    @State private var postcode: String
    @State private var country: String
    @State private var employmentStatus: String
    @State private var employer: String
    @State private var companyName: String
    @State private var registrationNumber: String
    @State private var annualIncome: String

    init(snapshot: KycSnapshot, onRestart: @escaping () -> Void) {
        self.onRestart = onRestart
        let a = snapshot.app
        _app = State(initialValue: a)
        _docs = State(initialValue: snapshot.docs)
        let draft = a.status.lowercased() == "draft"
        _section = State(initialValue: draft ? min(max(a.step, 1), 5) - 1 : 4)
        _firstName = State(initialValue: a.data.personal.firstName)
        _lastName = State(initialValue: a.data.personal.lastName)
        _dateOfBirth = State(initialValue: a.data.personal.dateOfBirth)
        _nationality = State(initialValue: a.data.personal.nationality)
        _street = State(initialValue: a.data.address.street)
        _city = State(initialValue: a.data.address.city)
        _postcode = State(initialValue: a.data.address.postcode)
        _country = State(initialValue: a.data.address.country)
        _employmentStatus = State(initialValue: a.data.employment.status.isEmpty ? "employed" : a.data.employment.status)
        _employer = State(initialValue: a.data.employment.employer ?? "")
        _companyName = State(initialValue: a.data.employment.companyName ?? "")
        _registrationNumber = State(initialValue: a.data.employment.registrationNumber ?? "")
        let income = a.data.employment.annualIncomeMinor
        _annualIncome = State(initialValue: income > 0 ? String(Double(income) / 100.0) : "")
    }

    private var isDraft: Bool { app.status.lowercased() == "draft" }
    private var isSubmitted: Bool { app.status.lowercased() == "submitted" }
    private var isApproved: Bool { app.status.lowercased() == "approved" }

    private var sectionLabels: [String] {
        [tr("personal"), tr("address"), tr("employment"), tr("documents"), tr("review")]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch section {
                case 0: personalCard
                case 1: addressCard
                case 2: employmentCard
                case 3: documentsCard
                default: reviewCard
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(tr("upload"), isPresented: $showSourceDialog, titleVisibility: .hidden) {
            Button("Photo library") { showPhotoPicker = true }
            Button("Files") { showFileImporter = true }
            Button(tr("cancel"), role: .cancel) { pendingKind = nil }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            handlePhoto(item)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handleFile(result)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScreenHeader(title: tr("title_kyc"), subtitle: tr("subtitle_kyc"))
            HStack(spacing: 8) {
                StatusPill(status: app.status)
                Text(tr("step_of", Int32(app.step))).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
            }
            ProgressView(value: Double(min(max(app.step, 1), 5)) / 5.0)
                .tint(Theme.primary)
                .padding(.vertical, 6)
            SegmentedTabs(options: sectionLabels, selected: $section)
            HStack {
                Text(tr("kyc_local_note")).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
                Spacer(minLength: 8)
                Button(tr("kyc_restart"), action: onRestart)
                    .font(AppFont.labelLarge)
                    .accessibilityIdentifier("kyc_restart")
            }
            .padding(.top, 8)
            ErrorBanner(message: error ?? uploadError)
            SuccessBanner(message: notice)
        }
    }

    // MARK: Sections

    private var personalCard: some View {
        SectionCard(title: tr("personal")) {
            AppTextField(label: tr("first_name"), text: $firstName, locator: Chaos.locator("kyc_first_name"), capitalization: .words)
            AppTextField(label: tr("last_name"), text: $lastName, locator: Chaos.locator("kyc_last_name"), capitalization: .words)
            AppTextField(label: tr("date_of_birth"), text: $dateOfBirth, locator: Chaos.locator("kyc_dob"), keyboard: .numbersAndPunctuation)
            AppTextField(label: tr("nationality"), text: $nationality, locator: Chaos.locator("kyc_nationality"), capitalization: .characters)
            saveButton { savePersonal() }
        }
    }

    private var addressCard: some View {
        SectionCard(title: tr("address")) {
            AppTextField(label: tr("street"), text: $street, locator: Chaos.locator("kyc_street"), capitalization: .words)
            AppTextField(label: tr("city"), text: $city, locator: Chaos.locator("kyc_city"), capitalization: .words)
            AppTextField(label: tr("postcode"), text: $postcode, locator: Chaos.locator("kyc_postcode"), capitalization: .characters)
            AppTextField(label: tr("country"), text: $country, locator: Chaos.locator("kyc_country"), capitalization: .characters)
            saveButton { saveAddress() }
        }
    }

    private var needsIncome: Bool { employmentStatus == "employed" || employmentStatus == "self-employed" }

    private var employmentCard: some View {
        SectionCard(title: tr("employment")) {
            Selector(
                label: tr("status"),
                selectedLabel: kycEmploymentLabel(employmentStatus),
                options: kycEmploymentStatuses.map { ($0, kycEmploymentLabel($0)) },
                locator: "kyc_employment_status",
                onSelected: { employmentStatus = $0 }
            )
            if employmentStatus == "employed" {
                AppTextField(label: tr("employer"), text: $employer, locator: Chaos.locator("kyc_employer"), capitalization: .words)
            }
            if employmentStatus == "self-employed" {
                AppTextField(label: tr("company_name"), text: $companyName, locator: Chaos.locator("kyc_company"), capitalization: .words)
                AppTextField(label: tr("registration_number"), text: $registrationNumber, locator: Chaos.locator("kyc_registration"), capitalization: .characters)
            }
            if needsIncome {
                AppTextField(label: tr("annual_income"), text: $annualIncome, locator: Chaos.locator("kyc_income"), keyboard: .decimalPad)
            }
            saveButton { saveEmployment() }
        }
    }

    private var documentsCard: some View {
        SectionCard(title: tr("documents")) {
            ForEach(kycDocumentKinds, id: \.0) { entry in
                documentRow(kind: entry.0, labelKey: entry.1)
            }
            PrimaryButton(text: tr("review")) {
                app = Services.shared.kyc.advanceTo(5)
                section = 4
            }
            .testTag("kyc_review")
        }
    }

    private func documentRow(kind: String, labelKey: String) -> some View {
        let existing = docs.first(where: { $0.kind == kind })
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr(labelKey)).font(AppFont.bodyMedium).fontWeight(.semibold).foregroundColor(Theme.onSurface)
            if let existing {
                Text(tr("kyc_uploaded_file", existing.filename)).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
            }
            HStack(spacing: 8) {
                SecondaryButton(text: existing == nil ? tr("upload") : tr("replace"), fullWidth: false) {
                    uploadError = nil
                    pendingKind = kind
                    showSourceDialog = true
                }
                .testTag("kyc_upload_\(kind)")
                if let existing {
                    SecondaryButton(text: tr("remove"), fullWidth: false) {
                        uploadError = nil
                        switch kycRun({ try Services.shared.kyc.deleteKycDocument(id: existing.id) }) {
                        case .success: docs = docs.filter { $0.id != existing.id }
                        case .failure(let e): uploadError = e.message
                        }
                    }
                    .testTag("kyc_remove_\(kind)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var reviewCard: some View {
        let personal = app.data.personal
        let addr = app.data.address
        let name = [personal.firstName, personal.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let address = [addr.street, addr.city, addr.postcode, addr.country].filter { !$0.isEmpty }.joined(separator: ", ")
        return SectionCard(title: tr("review")) {
            reviewRow(tr("name"), name)
            reviewRow(tr("date_of_birth"), personal.dateOfBirth)
            reviewRow(tr("nationality"), personal.nationality)
            reviewRow(tr("address"), address)
            reviewRow(tr("employment"), kycEmploymentLabel(app.data.employment.status))
            reviewRow(tr("docs_uploaded"), String(docs.count))
            if isSubmitted { SuccessBanner(message: tr("kyc_submitted_banner")) }
            if isApproved { SuccessBanner(message: tr("kyc_approved_banner")) }
            PrimaryButton(
                text: isDraft ? (saving ? tr("submitting") : tr("submit_application")) : tr("already_submitted"),
                enabled: !saving && isDraft
            ) {
                submit()
            }
            .testTag(Chaos.locator("kyc_submit"))
            if isSubmitted {
                SecondaryButton(text: tr("kyc_simulate_approval")) {
                    app = Services.shared.kyc.approveKyc()
                }
                .testTag("kyc_simulate_approval")
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(AppFont.labelMedium).foregroundColor(Theme.onSurfaceVariant)
            Text(value.isEmpty ? "—" : value).font(AppFont.bodyMedium).fontWeight(.semibold).foregroundColor(Theme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveButton(_ action: @escaping () -> Void) -> some View {
        PrimaryButton(text: saving ? tr("saving") : tr("save_continue"), enabled: !saving, action: action)
            .testTag("kyc_save_continue")
    }

    // MARK: Actions

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func savePersonal() {
        error = nil
        let req = KycPersonalRequest(firstName: trimmed(firstName), lastName: trimmed(lastName),
                                     dateOfBirth: trimmed(dateOfBirth), nationality: trimmed(nationality).uppercased())
        switch kycRun({ try Services.shared.kyc.saveKycPersonal(req) }) {
        case .success(let updated):
            app = updated
            notice = tr("kyc_personal_saved")
            section = 1
        case .failure(let e):
            error = e.message
        }
    }

    private func saveAddress() {
        error = nil
        let req = KycAddressRequest(street: trimmed(street), city: trimmed(city),
                                    postcode: trimmed(postcode), country: trimmed(country).uppercased())
        switch kycRun({ try Services.shared.kyc.saveKycAddress(req) }) {
        case .success(let updated):
            app = updated
            notice = tr("kyc_address_saved")
            section = 2
        case .failure(let e):
            error = e.message
        }
    }

    private func saveEmployment() {
        var incomeMinor: Int64?
        if let d = Double(trimmed(annualIncome)) { incomeMinor = Int64((d * 100).rounded()) }
        if needsIncome && incomeMinor == nil {
            error = tr("kyc_income_invalid")
            return
        }
        error = nil
        let emp = trimmed(employer)
        let comp = trimmed(companyName)
        let reg = trimmed(registrationNumber)
        let req = KycEmploymentRequest(
            status: employmentStatus,
            employer: employmentStatus == "employed" && !emp.isEmpty ? emp : nil,
            companyName: employmentStatus == "self-employed" && !comp.isEmpty ? comp : nil,
            registrationNumber: employmentStatus == "self-employed" && !reg.isEmpty ? reg : nil,
            annualIncomeMinor: needsIncome ? incomeMinor : nil
        )
        switch kycRun({ try Services.shared.kyc.saveKycEmployment(req) }) {
        case .success(let updated):
            app = updated
            notice = tr("kyc_employment_saved")
            section = 3
        case .failure(let e):
            error = e.message
        }
    }

    private func submit() {
        Task { @MainActor in
            await requestApproval {
                saving = true
                error = nil
                switch kycRun({ try Services.shared.kyc.submitKyc() }) {
                case .success(let updated):
                    app = updated
                    notice = tr("kyc_submitted_notice")
                case .failure(let e):
                    error = e.message
                }
                saving = false
            }
        }
    }

    private func upload(kind: String, filename: String, mime: String, data: Data) {
        switch kycRun({ try Services.shared.kyc.uploadKycDocument(kind: kind, filename: filename, mime: mime, data: data) }) {
        case .success(let doc):
            docs = docs.filter { $0.kind != doc.kind } + [doc]
        case .failure(let e):
            uploadError = e.message
        }
    }

    private func handlePhoto(_ item: PhotosPickerItem) {
        let kind = pendingKind
        pendingKind = nil
        photoItem = nil
        guard let kind else { return }
        uploadError = nil
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    uploadError = tr("kyc_file_read_error")
                    return
                }
                upload(kind: kind, filename: "photo-\(kind).jpg", mime: "image/jpeg", data: data)
            } catch {
                uploadError = tr("kyc_file_read_error")
            }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        let kind = pendingKind
        pendingKind = nil
        guard let kind else { return }
        uploadError = nil
        switch result {
        case .failure:
            uploadError = tr("kyc_file_read_error")
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                uploadError = tr("kyc_file_read_error")
                return
            }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            upload(kind: kind, filename: url.lastPathComponent, mime: mime, data: data)
        }
    }
}
