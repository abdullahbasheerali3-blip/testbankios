import Foundation

/// Error surfaced to the UI. `message` is already localised and user-presentable.
struct AppError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum ApiFailure: Error {
    case http(Int, Data)
    case network
    case parse
    case message(String)
}

/// Run an async API block and map any failure to a localised `AppError`.
func apiCall<T>(_ block: () async throws -> T) async -> Result<T, AppError> {
    do {
        return .success(try await block())
    } catch {
        return .failure(AppError(message: errorMessage(error)))
    }
}

func errorMessage(_ error: Error) -> String {
    if let kyc = error as? KycException { return kyc.message }
    if let f = error as? ApiFailure {
        switch f {
        case .network: return tr("err_network")
        case .parse: return tr("err_parse")
        case .message(let m): return m.isEmpty ? tr("err_generic") : m
        case .http(let code, let data):
            let body = String(data: data, encoding: .utf8) ?? ""
            if let r = try? NSRegularExpression(pattern: "\"(?:message|error|detail)\"\\s*:\\s*\"([^\"]+)\""),
               let m = r.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               m.numberOfRanges > 1, let range = Range(m.range(at: 1), in: body) {
                let extracted = String(body[range])
                if !extracted.trimmingCharacters(in: .whitespaces).isEmpty { return extracted }
            }
            switch code {
            case 400: return tr("err_400")
            case 401: return tr("err_401")
            case 403: return tr("err_403")
            case 404: return tr("err_404")
            case 409: return tr("err_409")
            case 500...599: return tr("err_5xx")
            default: return tr("err_http", code)
            }
        }
    }
    if error is URLError { return tr("err_network") }
    if error is DecodingError { return tr("err_parse") }
    let m = error.localizedDescription
    return m.isEmpty ? tr("err_generic") : m
}

final class ApiClient {
    static let shared = ApiClient()

    static let baseURL = "http://20.67.48.181/"

    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config)
    }

    private var session: SessionManager { Services.shared.session }

    // MARK: Core request plumbing

    private func makeRequest(_ method: String, _ path: String, query: [(String, String?)] = []) throws -> URLRequest {
        guard var comps = URLComponents(string: ApiClient.baseURL + path) else { throw ApiFailure.parse }
        let items = query.compactMap { (k, v) -> URLQueryItem? in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw ApiFailure.parse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let cookie = session.cookie, !cookie.isEmpty {
            req.setValue("etb_session=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw ApiFailure.network
        }
        guard let http = response as? HTTPURLResponse else { throw ApiFailure.network }
        if let setCookie = http.allHeaderFields["Set-Cookie"] as? String {
            session.captureSetCookie(setCookie)
        }
        guard (200..<300).contains(http.statusCode) else { throw ApiFailure.http(http.statusCode, data) }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) } catch { throw ApiFailure.parse }
    }

    func get<T: Decodable>(_ path: String, query: [(String, String?)] = []) async throws -> T {
        let req = try makeRequest("GET", path, query: query)
        return try decode(try await perform(req))
    }

    func getData(_ path: String, query: [(String, String?)] = []) async throws -> Data {
        try await perform(try makeRequest("GET", path, query: query))
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        var req = try makeRequest(method, path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        return try decode(try await perform(req))
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await perform(try makeRequest("POST", path)))
    }

    /// For endpoints whose response body we ignore (logout, delete).
    func sendIgnoringBody(_ method: String, _ path: String) async throws {
        _ = try await perform(try makeRequest(method, path))
    }

    func multipart<T: Decodable>(_ path: String, fields: [String: String], fileField: String, filename: String, mime: String, data: Data) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = try makeRequest("POST", path)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        for (k, v) in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        return try decode(try await perform(req))
    }

    // MARK: Endpoints (mirror Android ApiService)

    func login(_ b: LoginRequest) async throws -> LoginResponse { try await send("POST", "api/auth/login", body: b) }
    func devOtp(token: String) async throws -> DevOtpResponse { try await get("api/dev/otp/\(token)") }
    func verifyOtp(_ b: OtpRequest) async throws -> OtpResponse { try await send("POST", "api/auth/otp", body: b) }
    func sessionInfo() async throws -> SessionResponse { try await get("api/auth/session") }
    func me() async throws -> User { try await get("api/auth/me") }
    func logout() async throws { try await sendIgnoringBody("POST", "api/auth/logout") }

    func accounts(limit: Int? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> AccountPage {
        try await get("api/accounts", query: [("limit", limit.map(String.init)), ("page", page.map(String.init)), ("pageSize", pageSize.map(String.init))])
    }
    func accountSummary() async throws -> AccountSummary { try await get("api/accounts/summary") }

    func beneficiaries(search: String? = nil, status: String? = nil, pageSize: Int? = nil) async throws -> BeneficiaryPage {
        try await get("api/beneficiaries", query: [("search", search), ("status", status), ("pageSize", pageSize.map(String.init))])
    }
    func addBeneficiary(_ b: BeneficiaryRequest) async throws -> Beneficiary { try await send("POST", "api/beneficiaries", body: b) }
    func updateBeneficiary(id: String, _ b: BeneficiaryRequest) async throws -> Beneficiary { try await send("PUT", "api/beneficiaries/\(id)", body: b) }
    func deleteBeneficiary(id: String) async throws { try await sendIgnoringBody("DELETE", "api/beneficiaries/\(id)") }

    func createPayment(_ b: PaymentRequest) async throws -> Payment { try await send("POST", "api/payments", body: b) }
    func paymentStatus(id: String) async throws -> PaymentStatus { try await get("api/payments/\(id)/status") }

    func cards() async throws -> CardPage { try await get("api/cards") }
    func freezeCard(id: String) async throws -> BankCard { try await post("api/cards/\(id)/freeze") }
    func unfreezeCard(id: String) async throws -> BankCard { try await post("api/cards/\(id)/unfreeze") }

    func statements() async throws -> [Statement] { try await get("api/statements") }
    func statement(id: String) async throws -> StatementDetail { try await get("api/statements/\(id)") }
    func statementDownload(id: String, format: String, mode: String = "direct") async throws -> Data {
        try await getData("api/statements/\(id)/download", query: [("format", format), ("mode", mode)])
    }

    func standingOrders() async throws -> StandingOrderPage { try await get("api/standing-orders") }
    func createStandingOrder(_ b: StandingOrderRequest) async throws -> StandingOrder { try await send("POST", "api/standing-orders", body: b) }
    func cancelStandingOrder(id: String) async throws { try await sendIgnoringBody("DELETE", "api/standing-orders/\(id)") }

    func kyc() async throws -> KycApplication { try await get("api/kyc") }
    func kycDocuments() async throws -> KycDocumentPage { try await get("api/kyc/documents") }
    func saveKycPersonal(_ b: KycPersonalRequest) async throws -> KycApplication { try await send("PUT", "api/kyc/steps/1", body: b) }
    func saveKycAddress(_ b: KycAddressRequest) async throws -> KycApplication { try await send("PUT", "api/kyc/steps/2", body: b) }
    func saveKycEmployment(_ b: KycEmploymentRequest) async throws -> KycApplication { try await send("PUT", "api/kyc/steps/3", body: b) }
    func uploadKycDocument(kind: String, filename: String, mime: String, data: Data) async throws -> KycDocument {
        try await multipart("api/kyc/documents", fields: ["kind": kind], fileField: "file", filename: filename, mime: mime, data: data)
    }
    func deleteKycDocument(id: String) async throws { try await sendIgnoringBody("DELETE", "api/kyc/documents/\(id)") }
    func submitKyc() async throws -> KycApplication { try await post("api/kyc/submit") }

    func loanProducts() async throws -> [LoanProduct] { try await get("api/loans/products") }
    func loans() async throws -> LoanPage { try await get("api/loans") }
    func loanApplications() async throws -> LoanApplicationPage { try await get("api/loans/applications") }
    func applyForLoan(_ b: LoanApplicationRequest) async throws -> LoanApplication { try await send("POST", "api/loans/applications", body: b) }
    func loanApplication(id: String) async throws -> LoanApplication { try await get("api/loans/applications/\(id)") }
}
