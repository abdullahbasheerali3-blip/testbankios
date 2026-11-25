import SwiftUI
import LocalAuthentication
import UserNotifications

// MARK: - Biometrics

enum BiometricAuth {
    enum Mode { case biometricOnly, deviceCredential }

    /// Returns true only if the user successfully authenticated.
    static func authenticate(_ mode: Mode) async -> Bool {
        let context = LAContext()
        let policy: LAPolicy = mode == .biometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        if mode == .biometricOnly { context.localizedCancelTitle = tr("cancel") }
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: tr("biometric_subtitle"))
        } catch {
            return false
        }
    }

    static func isAvailable(_ mode: Mode) -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(mode == .biometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication, error: &error)
    }
}

// MARK: - Local notifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

enum LocalNotifier {
    static let delegate = NotificationDelegate()

    static func requestPermission() {
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Show a local notification after `delay` seconds (default 2.5s like Android).
    static func schedule(title: String, message: String, delay: TimeInterval = 2.5) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Action approval (none / fingerprint / device password / app MPIN)

final class ApprovalFlow: ObservableObject {
    static let shared = ApprovalFlow()
    /// Set when MPIN approval is required; the root view presents the PIN alert while non-nil.
    @Published var pending: (() -> Void)?
}

/// Gate a sensitive action behind the configured approval method, then run `action` on the main actor.
@MainActor
func requestApproval(_ action: @escaping () -> Void) async {
    switch Services.shared.settings.approvalMethod {
    case "fingerprint":
        if await BiometricAuth.authenticate(.biometricOnly) { action() }
    case "device":
        if await BiometricAuth.authenticate(.deviceCredential) { action() }
    case "mpin":
        ApprovalFlow.shared.pending = action
    default:
        action()
    }
}

/// Attach once at the app root; shows the MPIN prompt when `ApprovalFlow.pending` is set.
struct ApprovalDialogModifier: ViewModifier {
    @ObservedObject private var flow = ApprovalFlow.shared
    @State private var pin = ""
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .alert(tr("approve_mpin_title"), isPresented: Binding(get: { flow.pending != nil }, set: { if !$0 { flow.pending = nil; pin = ""; error = nil } })) {
                SecureField(tr("mpin"), text: $pin)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier(Chaos.locator("approval_pin"))
                Button(tr("approve")) {
                    if Services.shared.pin.verifyPin(pin) {
                        let action = flow.pending
                        flow.pending = nil
                        pin = ""
                        error = nil
                        action?()
                    } else {
                        // Keep the dialog usable: re-present with an error message.
                        let action = flow.pending
                        flow.pending = nil
                        pin = ""
                        error = tr("incorrect_mpin")
                        DispatchQueue.main.async { flow.pending = action }
                    }
                }
                Button(tr("cancel"), role: .cancel) { flow.pending = nil; pin = ""; error = nil }
            } message: {
                Text(error ?? tr("approve_mpin_desc"))
            }
    }
}

extension View {
    func approvalDialog() -> some View { modifier(ApprovalDialogModifier()) }

    /// Android `testTag` equivalent - exposed to Appium/XCUITest as `name`/`accessibilityIdentifier`.
    func testTag(_ id: String) -> some View { accessibilityIdentifier(id) }
}
