import SwiftUI

/// 通用设置子页：外观、语言、GitHub 登录、通知。
struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .english
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage(ThemePreferences.storageKey) private var appTheme: AppTheme = .teal
    @AppStorage(AppIconPreferences.storageKey) private var appIcon: AppIconOption = .primary
    @State private var iconError: String?
    @AppStorage(BackgroundPreferences.enabledKey) private var backgroundEnabled = false
    @AppStorage(BackgroundPreferences.opacityKey) private var backgroundOpacity = BackgroundPreferences.defaultOpacity
    @AppStorage(BackgroundPreferences.brightnessKey) private var backgroundBrightness = BackgroundPreferences.defaultBrightness
    @AppStorage(BackgroundPreferences.dimmingKey) private var backgroundDimming = BackgroundPreferences.defaultDimming
    @ObservedObject private var backgroundStore = BackgroundStore.shared
    @State private var showPhotoPicker = false
    @State private var backgroundError: String?
    @State private var notificationAuthStatus = AppLocalization.string("Not Checked")
    @State private var tokenInput = ""
    @State private var isValidatingToken = false
    @State private var loginError: String?
    @State private var validatedQuota: RateLimitInfo?
    @State private var showTokenHelp = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            appearanceSection
            appIconSection
            languageSection
            githubLoginSection
            notificationSection
        }
        .transparentListBackground()
        .navigationTitle("General")
        .sheet(isPresented: $showTokenHelp) {
            TokenHelpSheet()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { image in
                Task { @MainActor in
                    showPhotoPicker = false
                    guard let image else { return } // 用户取消
                    do {
                        // 低层 store 写盘并 @Published 通知，背景立即刷新（旧实现漏了这一步）。
                        try backgroundStore.setImage(image)
                    } catch {
                        backgroundError = error.localizedDescription
                    }
                }
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { backgroundError != nil },
            set: { if !$0 { backgroundError = nil } })) {
            Button("OK", role: .cancel) { backgroundError = nil }
        } message: {
            Text(backgroundError ?? "")
        }
        // 进页面就查一次真实授权状态。旧实现只在开关变化时才查，
        // 于是已开启通知的用户永远看到"未确定/未查询"。
        .task { await refreshNotificationAuth() }
        .onChange(of: scenePhase) { _, phase in
            // 用户可能刚去系统设置改过通知权限，回前台重查。
            if phase == .active { Task { await refreshNotificationAuth() } }
        }
    }

    @MainActor private func refreshNotificationAuth() async {
        notificationAuthStatus = await authText(NotificationScheduler())
    }

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                appTheme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(ThemePreferences.accent(theme, scheme: colorScheme))
                                            .frame(width: 38, height: 38)
                                        if appTheme == theme {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text(theme.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(appTheme == theme ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(appTheme == theme ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
            Toggle(isOn: $backgroundEnabled) {
                Label("Custom Background", systemImage: "photo")
            }
            if backgroundEnabled {
                // 有了图片才给"选择"以外的操作，避免空状态下按钮无意义。
                if backgroundStore.image != nil {
                    HStack(spacing: 14) {
                        Image(uiImage: backgroundStore.image!)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("Current background")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    showPhotoPicker = true
                } label: {
                    Label(backgroundStore.image == nil ? "Choose Background Image" : "Replace Background Image",
                          systemImage: "photo.on.rectangle.angled")
                }
                if backgroundStore.image != nil {
                    Button("Remove Background Image", role: .destructive) {
                        backgroundStore.clear()
                    }
                }
                sliderRow("Background Opacity", value: $backgroundOpacity,
                          range: BackgroundPreferences.opacityRange) {
                    Text("\(Int((backgroundOpacity * 100).rounded()))%")
                }
                sliderRow("Background Brightness", value: $backgroundBrightness,
                          range: BackgroundPreferences.brightnessRange) {
                    Text(String(format: "%+.0f%%", backgroundBrightness * 100))
                }
                // 图片越花，越需要这层压暗才能保证文字可读。
                sliderRow("Content Readability Shade", value: $backgroundDimming,
                          range: BackgroundPreferences.dimmingRange) {
                    Text("\(Int((backgroundDimming * 100).rounded()))%")
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("The theme only changes the accent color. A custom background replaces the page background; opacity, brightness and the readability shade are adjustable and can be turned off anytime. These preferences stay on this device and are never included in backups.")
        }
    }

    /// 带数值显示的滑块行。
    private func sliderRow<Value: View>(_ title: LocalizedStringKey,
                                        value: Binding<Double>,
                                        range: ClosedRange<Double>,
                                        @ViewBuilder valueLabel: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                valueLabel().font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var appIconSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("App Icon")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppIconOption.allCases) { option in
                            Button {
                                selectIcon(option)
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        // 直接显示包里真正在用的图标，避免"预览与实际不符"。
                                        if let artwork = option.artwork {
                                            Image(uiImage: artwork)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 56, height: 56)
                                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .fill(option.previewColor(colorScheme))
                                                .frame(width: 56, height: 56)
                                        }
                                        if appIcon == option {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.accentColor)
                                                .offset(x: 22, y: 22)
                                        }
                                    }
                                    .frame(width: 64, height: 64)
                                    Text(option.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(appIcon == option ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(appIcon == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("App Icon")
        } footer: {
            Text("Alternate icons are installed with the app. The system may briefly show a notification while switching. This preference stays on this device and is never included in backups.")
        }
        .alert("Icon Switch Failed", isPresented: Binding(
            get: { iconError != nil },
            set: { if !$0 { iconError = nil } })) {
            Button("OK", role: .cancel) { iconError = nil }
        } message: {
            Text(iconError ?? "")
        }
    }

    private func selectIcon(_ option: AppIconOption) {
        let previous = appIcon
        appIcon = option
        // 系统回调不在主线程，且失败时要回滚，所以用 Task 包一层。
        Task { @MainActor in
            do {
                try await AppIconSwitcher.apply(option)
            } catch {
                appIcon = previous
                iconError = error.localizedDescription
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    // 用本族名（English / 简体中文），与 iOS 系统设置一致。
                    Text(language.displayName).tag(language)
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("The app defaults to English. You can switch to Simplified Chinese or follow the system language anytime.")
        }
    }

    private var githubLoginSection: some View {
        Section {
            if model.isAuthenticated {
                LabeledContent("Status", value: AppLocalization.string("Signed In"))
                if let validatedQuota {
                    LabeledContent("Verified Quota", value: "\(validatedQuota.remaining)/\(validatedQuota.total) \(AppLocalization.string("requests"))")
                }
                Button("Sign Out", role: .destructive) { logout() }
            } else {
                SecureField("Paste GitHub Personal Access Token", text: $tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await login() }
                } label: {
                    if isValidatingToken {
                        HStack(spacing: 8) { ProgressView(); Text("Verifying…") }
                    } else {
                        Text("Sign In and Verify")
                    }
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingToken)
                Button("How to create a token?") { showTokenHelp = true }
            }
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("GitHub Sign-In")
        } footer: {
            Text(model.isAuthenticated
                 ? "Signed in: uses the authenticated limit (about 5000/hour) and can monitor private repos. The token is stored only in the local Keychain."
                 : "Not signed in: uses the public limit (about 60/hour per IP). Sign in to lift the limit and support private repos; the app works fine without it.")
        }
    }

    @MainActor private func login() async {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isValidatingToken = true
        loginError = nil
        defer { isValidatingToken = false }
        do {
            let info = try await GitHubClient().rateLimitStatus(token: token)
            model.setAuthToken(token)
            validatedQuota = info
            tokenInput = ""
            await model.refreshAll()
        } catch GitHubError.notAuthorized {
            loginError = AppLocalization.string("The token is invalid or has been revoked. Check it and try again.")
        } catch {
            loginError = AppLocalization.string("Verification failed") + ": \(error.localizedDescription)"
        }
    }

    @MainActor private func logout() {
        model.setAuthToken(nil)
        validatedQuota = nil
        loginError = nil
        Task { await model.refreshAll() }
    }

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Notify on New Changes", systemImage: "bell.badge")
            }
            .onChange(of: notificationsEnabled) { _, enabled in
                if enabled {
                    Task {
                        let scheduler = NotificationScheduler()
                        _ = await scheduler.requestAuthorization()
                        notificationAuthStatus = await authText(scheduler)
                    }
                }
            }
            if notificationsEnabled {
                LabeledContent("System Authorization", value: notificationAuthStatus)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Only “Worth Attention” and “Uncertain Impact” changes are notified (each source can be turned off individually). “Worth Attention” shows a banner; the rest enter Notification Center silently; whether it interrupts is decided by the system Focus mode. Background checks are scheduled by iOS roughly every 30 minutes and are not guaranteed to be real-time.")
        }
    }

    private func authText(_ scheduler: NotificationScheduler) async -> String {
        switch await scheduler.authorizationStatus() {
        case .authorized, .provisional: return AppLocalization.string("Authorized")
        case .denied: return AppLocalization.string("Denied (enable in System Settings)")
        case .notDetermined: return AppLocalization.string("Not Determined")
        @unknown default: return AppLocalization.string("Unknown")
        }
    }
}
