import SwiftUI
import UIKit

/// 新手引导：六页讲清用途、添加来源、类别与筛选、通知预期、隐私边界与备份。
///
/// 首次启动以全屏方式出现，可随时跳过；**之后可在设置 → 使用引导里重新查看**，
/// 不再"只出现一次就永久消失"。
struct OnboardingView: View {
    /// 结束回调。作为设置子页复看时传空实现即可。
    let onFinish: () -> Void
    /// 复看模式：按钮文案改为"完成"，且不显示语言选择（设置里已有）。
    var isReview: Bool = false

    @State private var page = 0
    @AppStorage(AppLocalization.storageKey) private var appLanguage: AppLanguage = .english

    struct Page {
        let symbol: String
        let title: String
        let message: String
        let footnote: String
    }

    /// 公开给测试断言页数与内容完整性的引导页定义。
    static let pages: [Page] = [
        Page(symbol: "dot.radiowaves.left.and.right",
             title: "Your Tech-Change Radar",
             message: "UpstreamLens watches the GitHub repos you care about — Releases, Tags, and commits to specific files. When something changes you get a checkable signal, instead of refreshing pages.",
             footnote: "Judgments are based on the purpose, version, and keywords you record for each source."),
        Page(symbol: "plus.square.on.square",
             title: "Add Sources",
             message: "Search a repo name or paste a GitHub link. Presets add starred AI projects in one tap. When filling in the version in use, pick straight from the upstream release list.",
             footnote: "The first successful check only sets a baseline; new changes are reported after that."),
        Page(symbol: "tag",
             title: "Categories, Search & Tags",
             message: "The Sources tab groups your repos by category and lets you search by name, purpose or tag. Categories are yours to edit in Settings → Categories.",
             footnote: "Owners who publish content-addressed snapshots can be filtered so only version-like releases are reported."),
        Page(symbol: "bell.badge",
             title: "Notifications & Widget",
             message: "With notifications on, only changes worth your attention raise a banner; the rest land silently in Notification Center. The widget shows the pending count and last check time.",
             footnote: "Background checks are scheduled by iOS roughly every 30 minutes — not real-time pushes."),
        Page(symbol: "lock.shield",
             title: "Data Stays On-Device",
             message: "Purpose, version, keywords, and other personal info stay on your phone and are never sent to GitHub. Export JSON to back up or migrate anytime.",
             footnote: "Monitoring public repos needs no GitHub sign-in."),
        Page(symbol: "paintbrush.pointed",
             title: "Make It Yours",
             message: "Pick an accent theme, choose an alternate app icon, and set a photo as the page background with adjustable opacity, brightness and readability. All of it lives in Settings → General.",
             footnote: "Appearance preferences stay on this device and are never included in backups."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if isReview {
                    Spacer()
                } else {
                    Spacer()
                    Button("Skip") { onFinish() }
                        .font(.subheadline)
                        .padding(.trailing, 20)
                }
            }
            .padding(.top, 12)

            if page == 0 && !isReview {
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            }

            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    pageView(Self.pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // 底部同时给出"上一步"，复看时也能来回翻。
            HStack(spacing: 12) {
                if page > 0 {
                    Button {
                        withAnimation(.snappy) { page -= 1 }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button {
                    if page < Self.pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page == Self.pages.count - 1
                         ? AppLocalization.string(isReview ? "Done" : "Get Started")
                         : AppLocalization.string("Next"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        // 底色由根视图 appBackground() 提供，这里不再重复绘制。
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: item.symbol)
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 116, height: 116)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)
            // 必须显式包成 LocalizedStringKey：Page 里存的是 String，
            // 直接 Text(String) 会走"逐字"初始化器，文案永远不会被本地化。
            Text(LocalizedStringKey(item.title))
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(LocalizedStringKey(item.message))
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(LocalizedStringKey(item.footnote))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }
}
