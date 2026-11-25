"""Generates Sources/Core/Models.swift from a compact spec so decoding stays tolerant
(missing / null fields fall back to defaults, mirroring Kotlin coerceInputValues)."""
import os

S = '""'
spec = {
    "User": [("id", "String", S), ("username", "String", S), ("displayName", "String", S), ("email", "String", S), ("role", "String", S), ("status", "String", S), ("mfaEnabled", "Bool", "false"), ("createdAt", "String", S)],
    "Account": [("id", "String", S), ("userId", "String", S), ("name", "String", S), ("type", "String", S), ("currency", "String", '"EUR"'), ("balanceMinor", "Int64", "0"), ("iban", "String", S), ("status", "String", '"active"')],
    "Balance": [("currency", "String", '"EUR"'), ("accounts", "Int", "0"), ("totalMinor", "Int64", "0")],
    "AccountSummary": [("balances", "[Balance]", "[]"), ("totalMinor", "Int64", "0"), ("currency", "String", '"EUR"')],
    "Beneficiary": [("id", "String", S), ("name", "String", S), ("nickname", "String?", "nil"), ("iban", "String", S), ("bankName", "String", S), ("country", "String", S), ("status", "String", '"active"'), ("createdAt", "String", S)],
    "Payment": [("id", "String", S), ("fromAccountId", "String", S), ("beneficiaryId", "String", S), ("amountMinor", "Int64", "0"), ("currency", "String", '"EUR"'), ("reference", "String", S), ("executeOn", "String", S), ("status", "String", '"pending"'), ("createdAt", "String", S)],
    "PaymentStatus": [("id", "String", S), ("status", "String", S), ("updatedAt", "String", S)],
    "BankCard": [("id", "String", S), ("userId", "String", S), ("accountId", "String", S), ("maskedPan", "String", S), ("holderName", "String", S), ("expiry", "String", S), ("type", "String", '"debit"'), ("status", "String", '"active"'), ("sortOrder", "Int", "0"), ("pinChangedAt", "String?", "nil")],
    "Statement": [("id", "String", S), ("accountId", "String", S), ("periodStart", "String", S), ("periodEnd", "String", S), ("generatedAt", "String", S)],
    "StatementTotals": [("openingMinor", "Int64", "0"), ("closingMinor", "Int64", "0"), ("creditsMinor", "Int64", "0"), ("debitsMinor", "Int64", "0"), ("txCount", "Int", "0"), ("currency", "String", '"EUR"')],
    "StatementDetail": [("id", "String", S), ("accountId", "String", S), ("periodStart", "String", S), ("periodEnd", "String", S), ("generatedAt", "String", S), ("totals", "StatementTotals", "StatementTotals()")],
    "StandingOrder": [("id", "String", S), ("userId", "String", S), ("fromAccountId", "String", S), ("beneficiaryId", "String", S), ("amountMinor", "Int64", "0"), ("currency", "String", '"EUR"'), ("frequency", "String", '"monthly"'), ("nextRunOn", "String", S), ("endOn", "String?", "nil"), ("reference", "String?", "nil"), ("status", "String", '"active"'), ("beneficiaryName", "String?", "nil")],
    "KycPersonal": [("firstName", "String", S), ("lastName", "String", S), ("dateOfBirth", "String", S), ("nationality", "String", S)],
    "KycAddressData": [("street", "String", S), ("city", "String", S), ("postcode", "String", S), ("country", "String", S)],
    "KycEmploymentData": [("status", "String", S), ("employer", "String?", "nil"), ("companyName", "String?", "nil"), ("registrationNumber", "String?", "nil"), ("annualIncomeMinor", "Int64", "0")],
    "KycData": [("fullName", "String?", "nil"), ("dateOfBirth", "String?", "nil"), ("nationality", "String?", "nil"), ("addressLine", "String?", "nil"), ("city", "String?", "nil"), ("personal", "KycPersonal", "KycPersonal()"), ("address", "KycAddressData", "KycAddressData()"), ("employment", "KycEmploymentData", "KycEmploymentData()")],
    "KycApplication": [("id", "String", S), ("userId", "String", S), ("status", "String", '"draft"'), ("step", "Int", "1"), ("data", "KycData", "KycData()"), ("createdAt", "String", S), ("updatedAt", "String", S)],
    "KycDocument": [("id", "String", S), ("kind", "String", S), ("filename", "String", S), ("mime", "String", S), ("sizeBytes", "Int64", "0")],
    "LoanProduct": [("id", "String", S), ("name", "String", S), ("rateBps", "Int", "0"), ("minMinor", "Int64", "0"), ("maxMinor", "Int64", "0"), ("minTerm", "Int", "0"), ("maxTerm", "Int", "0")],
    "Loan": [("id", "String", S), ("product", "String", S), ("principalMinor", "Int64", "0"), ("currency", "String", '"EUR"'), ("rateBps", "Int", "0"), ("termMonths", "Int", "0"), ("outstandingMinor", "Int64", "0"), ("nextPaymentOn", "String", S), ("status", "String", '"active"')],
    "LoanTimelineEntry": [("status", "String", S), ("at", "String", S), ("note", "String", S)],
    "LoanApplication": [("id", "String", S), ("userId", "String", S), ("product", "String", S), ("amountMinor", "Int64", "0"), ("currency", "String", '"EUR"'), ("termMonths", "Int", "0"), ("status", "String", '"received"'), ("timeline", "[LoanTimelineEntry]", "[]"), ("createdAt", "String", S)],
}
pages = {"AccountPage": "Account", "BeneficiaryPage": "Beneficiary", "CardPage": "BankCard", "StandingOrderPage": "StandingOrder",
         "KycDocumentPage": "KycDocument", "LoanPage": "Loan", "LoanApplicationPage": "LoanApplication"}
ident = {"Beneficiary", "Account", "BankCard", "Statement", "StandingOrder", "KycDocument", "LoanProduct", "Loan", "LoanApplication", "Payment"}

HEADER = '''import Foundation

// GENERATED by scripts/gen_models.py - edit the script, not this file.
// Tolerant decoding: missing or null fields fall back to defaults (mirrors Kotlin `coerceInputValues`).
extension KeyedDecodingContainer {
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
    func o<T: Decodable>(_ key: Key) -> T? {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil)
    }
}

// MARK: - Requests

struct LoginRequest: Encodable { var username: String; var password: String }
struct LoginResponse: Decodable {
    var otpRequired: Bool = false
    var otpToken: String = ""
    enum CodingKeys: String, CodingKey { case otpRequired, otpToken }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        otpRequired = c.v(.otpRequired, false)
        otpToken = c.v(.otpToken, "")
    }
}
struct OtpRequest: Encodable { var otpToken: String; var code: String }
struct DevOtpResponse: Decodable {
    var code: String = ""
    var availableAt: String = ""
    var ready: Bool = false
    enum CodingKeys: String, CodingKey { case code, availableAt, ready }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.v(.code, "")
        availableAt = c.v(.availableAt, "")
        ready = c.v(.ready, false)
    }
}

struct BeneficiaryRequest: Encodable {
    var name: String
    var nickname: String? = nil
    var iban: String? = nil
    var bankName: String? = nil
    var country: String
}

struct PaymentRequest: Encodable {
    var fromAccountId: String
    var beneficiaryId: String
    var amountMinor: Int64
    var currency: String
    var reference: String
    var executeOn: String
    var idempotencyKey: String
}

struct StandingOrderRequest: Encodable {
    var fromAccountId: String
    var beneficiaryId: String
    var amountMinor: Int64
    var currency: String = "EUR"
    var frequency: String
    var firstRunOn: String
    var endOn: String? = nil
    var reference: String? = nil
}

struct KycPersonalRequest: Encodable { var firstName: String; var lastName: String; var dateOfBirth: String; var nationality: String }
struct KycAddressRequest: Encodable { var street: String; var city: String; var postcode: String; var country: String }
struct KycEmploymentRequest: Encodable {
    var status: String
    var employer: String? = nil
    var companyName: String? = nil
    var registrationNumber: String? = nil
    var annualIncomeMinor: Int64? = nil
}

struct LoanApplicationRequest: Encodable {
    var product: String
    var amountMinor: Int64
    var currency: String = "EUR"
    var termMonths: Int
    var purpose: String
}

// MARK: - Responses
'''

FOOTER = '''
struct OtpResponse: Decodable {
    var user: User = User()
    enum CodingKeys: String, CodingKey { case user }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); user = c.v(.user, User()) }
}
struct SessionResponse: Decodable {
    var user: User? = nil
    enum CodingKeys: String, CodingKey { case user }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); user = c.o(.user) }
}
'''

out = [HEADER]
for name, fields in spec.items():
    conf = "Codable, Hashable" + (", Identifiable" if name in ident else "")
    out.append(f"struct {name}: {conf} {{")
    for f, t, d in fields:
        out.append(f"    var {f}: {t} = {d}")
    out.append("}")
    out.append(f"extension {name} {{")
    out.append("    init(from decoder: Decoder) throws {")
    out.append("        self.init()")
    out.append("        let c = try decoder.container(keyedBy: CodingKeys.self)")
    for f, t, d in fields:
        if t.endswith("?"):
            out.append(f"        {f} = c.o(.{f})")
        else:
            out.append(f"        {f} = c.v(.{f}, {f})")
    out.append("    }")
    out.append("}\n")

out.append("// MARK: - Paged list wrappers (server returns { items: [...] })\n")
for p, item in pages.items():
    out.append(f"struct {p}: Decodable {{\n    var items: [{item}] = []\n    enum CodingKeys: String, CodingKey {{ case items }}\n    init(from decoder: Decoder) throws {{ let c = try decoder.container(keyedBy: CodingKeys.self); items = c.v(.items, []) }}\n}}")
out.append(FOOTER)

path = os.path.join(os.path.dirname(__file__), "..", "Sources", "Core", "Models.swift")
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("ok")
