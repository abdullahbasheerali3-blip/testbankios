import SwiftUI

// MARK: - Loading

enum LoadState<T> {
    case loading
    case data(T)
    case error(String)
}

/// Loads data when first shown (and again on retry / when `key` changes), mirroring Android `Loadable`.
/// Change `key` to force a reload after a mutation (e.g. pass a counter you bump).
struct Loadable<T, Content: View>: View {
    var key: String = ""
    var load: () async -> Result<T, AppError>
    @ViewBuilder var content: (T) -> Content

    @State private var state: LoadState<T> = .loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingSkeleton()
            case .error(let message):
                VStack {
                    ErrorBanner(message: message)
                    Button {
                        attempt += 1
                    } label: {
                        Label(tr("try_again"), systemImage: "arrow.clockwise").font(AppFont.labelLarge)
                    }
                }
                .padding(16)
            case .data(let value):
                content(value)
            }
        }
        .task(id: "\(key)#\(attempt)") {
            state = .loading
            switch await load() {
            case .success(let v): state = .data(v)
            case .failure(let e): state = .error(e.message.isEmpty ? tr("failed_to_load") : e.message)
            }
        }
    }
}

struct LoadingSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceHigh).frame(height: 28).shimmer().clipShape(RoundedRectangle(cornerRadius: 10))
            RoundedRectangle(cornerRadius: 24).fill(Theme.surfaceHigh).frame(height: 150).shimmer().clipShape(RoundedRectangle(cornerRadius: 24))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20).fill(Theme.surfaceHigh).frame(height: 76).shimmer().clipShape(RoundedRectangle(cornerRadius: 20))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - Cards & headers

struct SectionCard<Content: View>: View {
    var title: String
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let icon { IconBadge(systemName: icon, size: 36) }
                Text(title).font(AppFont.titleMedium).foregroundColor(Theme.onSurface)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.outlineVariant, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

private struct InSubScreenKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True while a screen is shown inside `SubScreen`, which already displays the title.
    var inSubScreen: Bool {
        get { self[InSubScreenKey.self] }
        set { self[InSubScreenKey.self] = newValue }
    }
}

struct ScreenHeader: View {
    var title: String
    var subtitle: String? = nil
    @Environment(\.inSubScreen) private var inSub

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !inSub {
                Text(title).font(AppFont.headlineMedium).foregroundColor(Theme.onSurface)
            }
            if let subtitle {
                Text(subtitle).font(AppFont.bodyMedium).foregroundColor(Theme.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, inSub ? 0 : 8)
        .padding(.bottom, 8)
    }
}

struct ErrorBanner: View {
    var message: String?
    var title: String = tr("something_wrong")

    var body: some View {
        if let message, !message.isEmpty {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.circle").foregroundColor(Theme.error).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.labelLarge).foregroundColor(Theme.onErrorContainer)
                    Text(message).font(AppFont.bodySmall).foregroundColor(Theme.onErrorContainer)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.errorContainer))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("error_banner")
        }
    }
}

struct SuccessBanner: View {
    var message: String?

    var body: some View {
        if let message, !message.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.tertiary).font(.system(size: 22))
                Text(message).font(AppFont.bodyMedium).foregroundColor(Theme.onTertiaryContainer)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tertiaryContainer))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("success_banner")
        }
    }
}

struct EmptyState: View {
    var systemName: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            IconBadge(systemName: systemName, size: 64)
            Text(title).font(AppFont.titleMedium).foregroundColor(Theme.onSurface)
            Text(message).font(AppFont.bodyMedium).foregroundColor(Theme.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }
}

struct StatusPill: View {
    var status: String

    var body: some View {
        let color = statusColor(status)
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(statusLabel(status)).font(AppFont.labelSmall).foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// Pill-style segmented control.
struct SegmentedTabs: View {
    var options: [String]
    @Binding var selected: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    let isSelected = index == selected
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = index }
                    } label: {
                        Text(label)
                            .font(AppFont.labelLarge)
                            .fontWeight(isSelected ? .bold : .medium)
                            .lineLimit(1)
                            .foregroundColor(isSelected ? Theme.primary : Theme.onSurfaceVariant)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(isSelected ? Theme.surface : Color.clear)
                                .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 2, y: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab_\(index)")
                }
            }
            .padding(4)
        }
        .background(Capsule().fill(Theme.surfaceHigh))
    }
}

/// Screen with a back button + title row (Android `SubScreen`).
struct SubScreen<Content: View>: View {
    var title: String
    var onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("back"))
                .accessibilityIdentifier("back")
                Text(title).font(AppFont.titleLarge).foregroundColor(Theme.onSurface)
                Spacer()
            }
            .padding(.leading, 4)
            .padding(.trailing, 16)
            .padding(.top, 4)
            content()
                .environment(\.inSubScreen, true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Dropdown selector. `options` are (id, label) pairs.
struct Selector: View {
    var label: String
    var selectedLabel: String
    var options: [(String, String)]
    var locator: String? = nil
    var onSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.labelMedium).foregroundColor(Theme.onSurfaceVariant)
            Menu {
                ForEach(options, id: \.0) { option in
                    Button(option.1) { onSelected(option.0) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedLabel).font(AppFont.bodyLarge).lineLimit(1).foregroundColor(Theme.onSurface)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").foregroundColor(Theme.onSurfaceVariant)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceLow))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.outline, lineWidth: 1))
            }
            .accessibilityIdentifier(locator ?? "selector_\(label)")
        }
    }
}

/// Outlined text field with a caption label (Android OutlinedTextField equivalent).
struct AppTextField: View {
    var label: String
    @Binding var text: String
    var placeholder: String = ""
    var locator: String? = nil
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var helper: String? = nil
    var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.labelMedium).foregroundColor(Theme.onSurfaceVariant)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                        .autocorrectionDisabled(keyboard != .default || capitalization == .never)
                }
            }
            .font(AppFont.bodyLarge)
            .disabled(!enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(enabled ? Theme.surfaceLow : Theme.surfaceHigh))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.outline, lineWidth: 1))
            .accessibilityIdentifier(locator ?? label)
            if let helper {
                Text(helper).font(AppFont.bodySmall).foregroundColor(Theme.onSurfaceVariant)
            }
        }
    }
}

/// Standard scrolling page container with the app's padding and background.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}
