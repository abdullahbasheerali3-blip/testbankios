import Foundation
import Security
import CryptoKit
import UIKit

// MARK: - Services container (Android: TestBankApp)

final class Services {
    static let shared = Services()
    let session = SessionManager()
    let settings = SettingsManager()
    let pin = PinManager()
    let credentials = CredentialStore()
    let kyc = KycStore()
    private init() {}

    /// Apply persisted settings (language, chaos switches) at launch.
    func bootstrap() {
        Localizer.shared.setLanguage(settings.language)
        Chaos.locatorsEnabled = settings.chaosLocators
        Chaos.bugEnabled = settings.injectBug
    }
}

// MARK: - Session cookie

final class SessionManager {
    private let key = "etb_session"
    private let lock = NSLock()
    private var _cookie: String?

    init() { _cookie = UserDefaults.standard.string(forKey: key) }

    var cookie: String? {
        lock.lock(); defer { lock.unlock() }
        return _cookie
    }

    /// Parse an `etb_session=...;` value out of a Set-Cookie header (may contain several cookies).
    func captureSetCookie(_ header: String) {
        guard let range = header.range(of: "etb_session=") else { return }
        let rest = header[range.upperBound...]
        let value = rest.prefix(while: { $0 != ";" && $0 != "," }).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        lock.lock(); _cookie = value; lock.unlock()
        UserDefaults.standard.set(value, forKey: key)
    }

    func clear() {
        lock.lock(); _cookie = nil; lock.unlock()
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Settings

final class SettingsManager {
    private let d = UserDefaults.standard

    var language: String {
        get { let v = d.string(forKey: "app_language") ?? "en"; return ["en", "ar"].contains(v) ? v : "en" }
        set { d.set(["en", "ar"].contains(newValue) ? newValue : "en", forKey: "app_language") }
    }
    var chaosLocators: Bool {
        get { d.bool(forKey: "chaos_locators") }
        set { d.set(newValue, forKey: "chaos_locators") }
    }
    var injectBug: Bool {
        get { d.bool(forKey: "inject_display_bug") }
        set { d.set(newValue, forKey: "inject_display_bug") }
    }
    /// "none" | "fingerprint" | "device" | "mpin"
    var approvalMethod: String {
        get { let v = d.string(forKey: "approval_method") ?? "none"; return ["none", "fingerprint", "device", "mpin"].contains(v) ? v : "none" }
        set { d.set(["none", "fingerprint", "device", "mpin"].contains(newValue) ? newValue : "none", forKey: "approval_method") }
    }
    var biometricLoginEnabled: Bool {
        get { d.bool(forKey: "biometric_login") }
        set { d.set(newValue, forKey: "biometric_login") }
    }
}

// MARK: - Keychain helper

enum Keychain {
    private static let service = "com.expleo.testbankios"

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Saved credentials (for biometric sign-in)

final class CredentialStore {
    func save(username: String, password: String) {
        Keychain.set(username, for: "username")
        Keychain.set(password, for: "password")
    }

    func load() -> (username: String, password: String)? {
        guard let u = Keychain.get("username"), let p = Keychain.get("password"),
              !u.trimmingCharacters(in: .whitespaces).isEmpty, !p.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (u, p)
    }

    func hasCredentials() -> Bool { load() != nil }

    func clear() {
        Keychain.remove("username")
        Keychain.remove("password")
    }
}

// MARK: - MPIN

final class PinManager {
    private let key = "mpin_hash"

    func hasPin() -> Bool { !(UserDefaults.standard.string(forKey: key) ?? "").isEmpty }

    func isValidPin(_ pin: String) -> Bool {
        (4...8).contains(pin.count) && pin.allSatisfy { $0.isNumber && $0.isASCII }
    }

    func setPin(_ pin: String) {
        guard isValidPin(pin) else { return }
        UserDefaults.standard.set(hash(pin), forKey: key)
    }

    func verifyPin(_ pin: String) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty else { return false }
        return hash(pin) == stored
    }

    func clearPin() { UserDefaults.standard.removeObject(forKey: key) }

    private func hash(_ pin: String) -> String {
        let salt = UIDevice.current.identifierForVendor?.uuidString ?? "expleo-test-bank"
        let digest = SHA256.hash(data: Data("\(salt):\(pin)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - KYC (local-only, mirrors Android KycStore)

struct KycException: Error {
    var message: String
}

final class KycStore {
    static let requiredDocs: Set<String> = ["id-front", "id-back", "proof-of-address"]
    private static let maxBytes = 10 * 1024 * 1024

    private struct Stored: Codable {
        var app: KycApplication
        var docs: [KycDocument] = []
    }

    private let defaults = UserDefaults.standard
    private let key = "kyc_state"
    private var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("kyc", isDirectory: true)
    }

    private func now() -> String { ISO8601DateFormatter().string(from: Date()) }

    private func read() -> Stored {
        if let raw = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Stored.self, from: raw) { return s }
        var app = KycApplication()
        app.id = "kyc_local"; app.status = "draft"; app.step = 1; app.createdAt = now(); app.updatedAt = now()
        return Stored(app: app)
    }

    @discardableResult
    private func write(_ stored: Stored) -> KycApplication {
        var s = stored
        s.app.updatedAt = now()
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
        return s.app
    }

    private func requireDraft(_ app: KycApplication) throws {
        if app.status.lowercased() != "draft" { throw KycException(message: tr("already_submitted")) }
    }

    func kyc() -> KycApplication { read().app }

    func kycDocuments() -> KycDocumentPage {
        var page = KycDocumentPage()
        page.items = read().docs
        return page
    }

    func saveKycPersonal(_ req: KycPersonalRequest) throws -> KycApplication {
        var s = read()
        try requireDraft(s.app)
        if req.firstName.trimmingCharacters(in: .whitespaces).isEmpty || req.lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            throw KycException(message: tr("kyc_name_required"))
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let dob = f.date(from: req.dateOfBirth), f.string(from: dob) == req.dateOfBirth else {
            throw KycException(message: tr("kyc_dob_invalid"))
        }
        let years = Calendar(identifier: .gregorian).dateComponents([.year], from: dob, to: Date()).year ?? 0
        if years < 18 { throw KycException(message: tr("kyc_dob_age")) }
        if req.nationality.range(of: "^[A-Za-z]{2}$", options: .regularExpression) == nil {
            throw KycException(message: tr("kyc_nationality_invalid"))
        }
        s.app.data.personal = KycPersonal(firstName: req.firstName, lastName: req.lastName, dateOfBirth: req.dateOfBirth, nationality: req.nationality)
        s.app.step = max(s.app.step, 2)
        return write(s)
    }

    func saveKycAddress(_ req: KycAddressRequest) throws -> KycApplication {
        var s = read()
        try requireDraft(s.app)
        if [req.street, req.city, req.postcode, req.country].contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw KycException(message: tr("kyc_address_required"))
        }
        s.app.data.address = KycAddressData(street: req.street, city: req.city, postcode: req.postcode, country: req.country)
        s.app.step = max(s.app.step, 3)
        return write(s)
    }

    func saveKycEmployment(_ req: KycEmploymentRequest) throws -> KycApplication {
        var s = read()
        try requireDraft(s.app)
        if req.status == "employed", (req.employer ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw KycException(message: tr("kyc_employer_required"))
        }
        if req.status == "self-employed", (req.companyName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw KycException(message: tr("kyc_company_required"))
        }
        s.app.data.employment = KycEmploymentData(status: req.status, employer: req.employer, companyName: req.companyName,
                                                  registrationNumber: req.registrationNumber, annualIncomeMinor: req.annualIncomeMinor ?? 0)
        s.app.step = max(s.app.step, 4)
        return write(s)
    }

    /// Move the progress marker forward (e.g. when the user reaches the review step).
    @discardableResult
    func advanceTo(_ step: Int) -> KycApplication {
        var s = read()
        guard s.app.status.lowercased() == "draft" else { return s.app }
        s.app.step = max(s.app.step, min(max(step, 1), 5))
        return write(s)
    }

    func uploadKycDocument(kind: String, filename: String, mime: String, data: Data) throws -> KycDocument {
        var s = read()
        try requireDraft(s.app)
        if data.count > KycStore.maxBytes { throw KycException(message: tr("kyc_file_too_large")) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = "doc_\(Int(Date().timeIntervalSince1970 * 1000))"
        let safe = filename.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        do { try data.write(to: dir.appendingPathComponent("\(id)_\(safe)")) } catch {
            throw KycException(message: tr("kyc_file_read_error"))
        }
        s.docs.filter { $0.kind == kind }.forEach { deleteFile($0.id) }
        var doc = KycDocument()
        doc.id = id; doc.kind = kind; doc.filename = filename; doc.mime = mime; doc.sizeBytes = Int64(data.count)
        s.docs = s.docs.filter { $0.kind != kind } + [doc]
        write(s)
        return doc
    }

    func deleteKycDocument(id: String) throws {
        var s = read()
        try requireDraft(s.app)
        deleteFile(id)
        s.docs = s.docs.filter { $0.id != id }
        write(s)
    }

    func submitKyc() throws -> KycApplication {
        var s = read()
        try requireDraft(s.app)
        let d = s.app.data
        let complete = !d.personal.firstName.isEmpty && !d.address.street.isEmpty && !d.employment.status.isEmpty
        if !complete { throw KycException(message: tr("kyc_incomplete")) }
        let kinds = Set(s.docs.map { $0.kind })
        if !KycStore.requiredDocs.isSubset(of: kinds) { throw KycException(message: tr("kyc_docs_missing")) }
        s.app.status = "submitted"; s.app.step = 5
        return write(s)
    }

    /// Demo helper: pretend a back-office reviewer approved the application.
    @discardableResult
    func approveKyc() -> KycApplication {
        var s = read()
        guard s.app.status.lowercased() == "submitted" else { return s.app }
        s.app.status = "approved"
        return write(s)
    }

    func reset() {
        defaults.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: dir)
    }

    private func deleteFile(_ id: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files.filter { $0.lastPathComponent.hasPrefix("\(id)_") }.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
