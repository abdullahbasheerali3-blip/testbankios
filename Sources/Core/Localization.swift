import SwiftUI

/// Runtime-switchable localisation (English / Arabic), mirrors Android's `tr(R.string.x)`.
/// Keys are identical to the Android string resource names (see Resources/*.lproj/Localizable.strings).
final class Localizer {
    static let shared = Localizer()
    private(set) var language: String = "en"
    private var bundle: Bundle = .main

    func setLanguage(_ code: String) {
        let lang = ["en", "ar"].contains(code) ? code : "en"
        language = lang
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
    }

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Look up a localised string. Format args use `%1$@` / `%1$d` positional specifiers.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = Localizer.shared.string(key)
    if args.isEmpty { return format }
    let safe: [CVarArg] = args.map { ($0 as? Int).map { Int32($0) } ?? $0 }
    return String(format: format, locale: Locale(identifier: "en_US"), arguments: safe)
}

/// Test-automation "chaos" switches (alternate locators / injected display bug).
enum Chaos {
    static var locatorsEnabled = false
    static var bugEnabled = false

    /// Accessibility identifier for a field, optionally mutated for resilience demos.
    static func locator(_ base: String) -> String { locatorsEnabled ? "chaos_\(base)" : base }

    static func label(_ base: String) -> String { locatorsEnabled ? "\(base) • alt" : base }

    static func displayAmount(_ amountMinor: Int64, _ currency: String) -> String {
        let value = formatMinor(amountMinor, currency)
        return bugEnabled ? value.replacingOccurrences(of: currency, with: "\(currency) \(currency)") : value
    }
}

// MARK: - Formatting helpers

func formatMinor(_ amountMinor: Int64, _ currency: String) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.usesGroupingSeparator = true
    let s = f.string(from: NSNumber(value: Double(amountMinor) / 100.0)) ?? "0.00"
    return "\(s) \(currency)"
}

func maskIban(_ iban: String) -> String {
    let clean = iban.replacingOccurrences(of: " ", with: "")
    return clean.count <= 4 ? "•••• \(clean)" : "•••• \(clean.suffix(4))"
}

func capitalizedFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return first.uppercased() + s.dropFirst()
}

func statusLabel(_ status: String) -> String {
    switch status.lowercased() {
    case "active": return tr("st_active")
    case "frozen": return tr("st_frozen")
    case "blocked": return tr("st_blocked")
    case "pending": return tr("st_pending")
    case "completed": return tr("st_completed")
    case "submitted": return tr("st_submitted")
    case "received": return tr("st_received")
    case "cancelled", "canceled": return tr("st_cancelled")
    case "declined": return tr("st_declined")
    case "rejected": return tr("st_rejected")
    case "approved": return tr("st_approved")
    case "failed": return tr("st_failed")
    case "draft": return tr("st_draft")
    case "under review", "under_review", "review": return tr("st_review")
    default: return capitalizedFirst(status)
    }
}

func frequencyLabel(_ value: String) -> String {
    switch value.lowercased() {
    case "weekly": return tr("freq_weekly")
    case "monthly": return tr("freq_monthly")
    case "quarterly": return tr("freq_quarterly")
    case "yearly", "annually": return tr("freq_yearly")
    default: return capitalizedFirst(value)
    }
}

func accountTypeLabel(_ value: String) -> String {
    let v = value.lowercased()
    if v.contains("sav") { return tr("acct_savings") }
    if v.contains("current") || v.contains("check") { return tr("acct_current") }
    return capitalizedFirst(value)
}

func cardTypeLabel(_ value: String) -> String {
    switch value.lowercased() {
    case "debit": return tr("card_debit")
    case "credit": return tr("card_credit")
    default: return capitalizedFirst(value)
    }
}
