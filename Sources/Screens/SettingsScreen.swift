import SwiftUI

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

struct SettingsScreen: View {
    private let settings = Services.shared.settings
    private let pinManager = Services.shared.pin

    @State private var language = Services.shared.settings.language
    @State private var locators = Services.shared.settings.chaosLocators
    @State private var bug = Services.shared.settings.injectBug
    @State private var approvalMethod = Services.shared.settings.approvalMethod
    @State private var biometricEnabled = Services.shared.settings.biometricLoginEnabled
    @State private var hasPin = Services.shared.pin.hasPin()
    @State private var showPinSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScreenHeader(title: tr("settings_title"), subtitle: tr("settings_subtitle"))

                SectionCard(title: tr("language"), icon: "globe") {
                    HStack(spacing: 8) {
                        chip(tr("english"), selected: language == "en", id: "language_en") { setLanguage("en") }
                        chip(tr("arabic"), selected: language == "ar", id: "language_ar") { setLanguage("ar") }
                        Spacer(minLength: 0)
                    }
                }

                SectionCard(title: tr("approval"), icon: "lock.shield") {
                    Text(tr("approval_desc")).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            approvalChip("none", tr("approval_none"))
                            approvalChip("fingerprint", tr("approval_fingerprint"))
                        }
                        HStack(spacing: 8) {
                            approvalChip("device", tr("approval_device"))
                            approvalChip("mpin", tr("approval_mpin"))
                        }
                    }
                    toggleRow(title: tr("biometric_login"), desc: tr("biometric_login_desc"), isOn: Binding(
                        get: { biometricEnabled },
                        set: { enabled in
                            biometricEnabled = enabled
                            if !enabled { Services.shared.credentials.clear() }
                            settings.biometricLoginEnabled = enabled
                        }
                    ), id: "settings_biometric_toggle")

                    HStack(spacing: 8) {
                        Button { showPinSetup = true } label: {
                            Text(hasPin ? tr("reset_mpin") : tr("set_mpin"))
                                .font(AppFont.labelLarge).foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Capsule().fill(Theme.primary))
                        }
                        .accessibilityIdentifier("mpin_set_button")
                        if hasPin {
                            Button {
                                pinManager.clearPin()
                                hasPin = false
                            } label: {
                                Text(tr("remove_mpin"))
                                    .font(AppFont.labelLarge).foregroundColor(Theme.primary)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .overlay(Capsule().stroke(Theme.primary.opacity(0.5), lineWidth: 1.5))
                            }
                            .accessibilityIdentifier("mpin_remove_button")
                        }
                        Spacer(minLength: 0)
                    }
                }

                SectionCard(title: tr("chaos_lab"), icon: "flask") {
                    toggleRow(title: tr("chaos_locators"), desc: tr("chaos_locators_desc"), isOn: Binding(
                        get: { locators },
                        set: { v in
                            locators = v
                            Chaos.locatorsEnabled = v
                            settings.chaosLocators = v
                        }
                    ), id: "chaos_locators_toggle")
                    Divider()
                    toggleRow(title: tr("inject_bug"), desc: tr("inject_bug_desc"), isOn: Binding(
                        get: { bug },
                        set: { v in
                            bug = v
                            Chaos.bugEnabled = v
                            settings.injectBug = v
                        }
                    ), id: "inject_bug_toggle")
                }

                Text(tr("restart_hint")).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showPinSetup) {
            PinSetupSheet(hasPin: hasPin) {
                hasPin = true
                if approvalMethod != "mpin" {
                    settings.approvalMethod = "mpin"
                    approvalMethod = "mpin"
                }
                showPinSetup = false
            } onCancel: {
                showPinSetup = false
            }
        }
    }

    private func setLanguage(_ code: String) {
        language = code
        settings.language = code
        Localizer.shared.setLanguage(code)
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    private func chip(_ label: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                Text(label).font(AppFont.labelMedium)
            }
            .foregroundColor(selected ? Theme.onPrimaryContainer : Theme.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(selected ? Theme.primaryContainer : Color.clear))
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func approvalChip(_ method: String, _ label: String) -> some View {
        chip(label, selected: approvalMethod == method, id: Chaos.locator("approval_method_\(method)")) {
            settings.approvalMethod = method
            approvalMethod = method
        }
    }

    private func toggleRow(title: String, desc: String, isOn: Binding<Bool>, id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.bodyLarge).foregroundColor(Theme.onSurface)
                Text(desc).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().accessibilityIdentifier(id)
        }
    }
}

private struct PinSetupSheet: View {
    var hasPin: Bool
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var pin = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(hasPin ? tr("reset_mpin") : tr("set_mpin")).font(AppFont.titleLarge).foregroundColor(Theme.onSurface)
            AppTextField(label: tr("mpin"), text: $pin, locator: Chaos.locator("mpin_setup"), secure: true)
            AppTextField(label: tr("confirm_mpin"), text: $confirm, locator: Chaos.locator("mpin_confirm"), secure: true)
            if let error {
                Text(error).font(AppFont.bodyMedium).foregroundColor(Theme.error)
            }
            HStack(spacing: 12) {
                SecondaryButton(text: tr("cancel")) { onCancel() }
                    .testTag("mpin_cancel")
                PrimaryButton(text: tr("save")) {
                    let pm = Services.shared.pin
                    if !pm.isValidPin(pin) {
                        error = tr("mpin_invalid")
                    } else if pin != confirm {
                        error = tr("mpin_mismatch")
                    } else {
                        pm.setPin(pin)
                        onSaved()
                    }
                }
                .testTag("mpin_save")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
