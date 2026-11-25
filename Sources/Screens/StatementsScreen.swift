import SwiftUI
import UIKit

struct StatementsScreen: View {
    var body: some View {
        Loadable(key: "statements", load: {
            await apiCall { () async throws -> StatementsPayload in
                let accounts = try await ApiClient.shared.accounts(page: 1, pageSize: 100)
                let statements = try await ApiClient.shared.statements()
                return StatementsPayload(accounts: accounts, statements: statements)
            }
        }) { (payload: StatementsPayload) in
            StatementsContent(accounts: payload.accounts.items, statements: payload.statements)
        }
        .background(Theme.background)
    }
}

private struct StatementsPayload {
    var accounts: AccountPage
    var statements: [Statement]
}

private struct StatementShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController wrapper used to share/open downloaded statement files.
struct StatementShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct StatementsContent: View {
    let accounts: [Account]
    let statements: [Statement]

    @State private var selectedAccount = "all"
    @State private var detail: StatementDetail?
    @State private var detailError: String?
    @State private var shareItem: StatementShareItem?
    @State private var downloading = false

    private var options: [(String, String)] {
        [("all", tr("all_accounts"))] + accounts.map { ($0.id, $0.name) }
    }

    private var visible: [Statement] {
        selectedAccount == "all" ? statements : statements.filter { $0.accountId == selectedAccount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: tr("title_statements"), subtitle: tr("subtitle_statements"))
                Selector(
                    label: tr("account"),
                    selectedLabel: options.first(where: { $0.0 == selectedAccount })?.1 ?? tr("all_accounts"),
                    options: options,
                    locator: "statement_account_selector",
                    onSelected: { selectedAccount = $0 }
                )
                ErrorBanner(message: detailError)
                if let detail {
                    detailCard(detail)
                }
                ForEach(visible) { statement in
                    statementCard(statement)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $shareItem) { item in
            StatementShareSheet(url: item.url)
        }
    }

    private func statementCard(_ statement: Statement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                IconBadge(systemName: "doc.text.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(statement.periodStart) → \(statement.periodEnd)").font(AppFont.titleMedium).foregroundColor(Theme.onSurface)
                    Text(tr("generated_on", String(statement.generatedAt.prefix(10)), statement.accountId))
                        .font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
                }
                Spacer(minLength: 4)
                Text(statement.id).font(AppFont.labelSmall).foregroundColor(Theme.onSurfaceVariant)
            }
            SecondaryButton(text: tr("view_summary"), icon: "eye") {
                loadDetail(statement.id)
            }
            .testTag(Chaos.locator("statement_view_\(statement.id)"))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func loadDetail(_ id: String) {
        detailError = nil
        Task { @MainActor in
            switch await apiCall({ try await ApiClient.shared.statement(id: id) }) {
            case .success(let d): detail = d
            case .failure(let e): detailError = e.message
            }
        }
    }

    private func detailCard(_ detail: StatementDetail) -> some View {
        SectionCard(title: tr("statement_summary", detail.id), icon: "doc.text.fill") {
            Text(tr("period_label", detail.periodStart, detail.periodEnd)).font(AppFont.bodyMedium)
            summaryRow(tr("opening"), formatMinor(detail.totals.openingMinor, detail.totals.currency))
            summaryRow(tr("credits"), formatMinor(detail.totals.creditsMinor, detail.totals.currency))
            summaryRow(tr("debits"), formatMinor(detail.totals.debitsMinor, detail.totals.currency))
            summaryRow(tr("closing"), formatMinor(detail.totals.closingMinor, detail.totals.currency))
            summaryRow(tr("transactions"), String(detail.totals.txCount))
            HStack(spacing: 8) {
                SecondaryButton(text: "PDF", icon: "doc.richtext", enabled: !downloading) {
                    download(detail.id, format: "pdf")
                }
                .testTag("statement_pdf")
                SecondaryButton(text: "CSV", icon: "tablecells", enabled: !downloading) {
                    download(detail.id, format: "csv")
                }
                .testTag("statement_csv")
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(AppFont.bodyMedium).foregroundColor(Theme.onSurfaceVariant)
            Spacer()
            Text(value).font(AppFont.bodyMedium).fontWeight(.semibold).foregroundColor(Theme.onSurface)
        }
    }

    private func download(_ id: String, format: String) {
        downloading = true
        detailError = nil
        Task { @MainActor in
            let result = await apiCall { () async throws -> URL in
                let data = try await ApiClient.shared.statementDownload(id: id, format: format)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("statement-\(id).\(format)")
                try data.write(to: url, options: .atomic)
                return url
            }
            downloading = false
            switch result {
            case .success(let url): shareItem = StatementShareItem(url: url)
            case .failure(let e): detailError = e.message
            }
        }
    }
}
