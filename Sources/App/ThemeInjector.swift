import SwiftUI

/// 主题注入：按持久化选择设置全局强调色。
/// teal（默认）走 Color.accentColor，即资源里的品牌色，与现有视觉完全一致。
struct ThemeInjector: ViewModifier {
    @AppStorage(ThemePreferences.storageKey) private var rawTheme = ThemePreferences.fallback.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme { ThemePreferences.resolve(rawTheme) }

    func body(content: Content) -> some View {
        content.tint(ThemePreferences.accent(theme, scheme: colorScheme))
    }
}

extension View {
    func injectTheme() -> some View { modifier(ThemeInjector()) }
}
