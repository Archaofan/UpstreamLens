import SwiftUI

/// 首次启动的新手引导：四页讲清用途、添加方式、通知预期与隐私边界，
/// 只出现一次（hasCompletedOnboarding 记忆），之后可在设置里回顾。
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let message: String
        let footnote: String
    }

    private let pages: [Page] = [
        Page(symbol: "dot.radiowaves.left.and.right",
             title: "你的技术变化雷达",
             message: "UpstreamLens 盯住 GitHub 上你在意的仓库：Release、Tag、指定文件的提交。出现变化时给你可核查的判断，不用反复刷网页。",
             footnote: "判断依据是你在来源里记录的用途、使用版本和关键词。"),
        Page(symbol: "plus.square.on.square",
             title: "添加监控来源",
             message: "搜索仓库名或粘贴 GitHub 链接即可；“常用预设”一键添加 AI 领域的高星项目。填写“正在使用的版本”时可以直接从上游版本列表下拉选择。",
             footnote: "首次成功检查只建立基线，之后才报告新变化。"),
        Page(symbol: "bell.badge",
             title: "通知与小组件",
             message: "开启通知后，只有“值得关注”的变化才会横幅提醒，其余静默进入通知中心。小组件显示待查看数量与上次检查时间。",
             footnote: "后台检查由 iOS 调度，约每 30 分钟一次，不是实时推送。"),
        Page(symbol: "lock.shield",
             title: "数据只留在本机",
             message: "用途、版本、关键词等个人信息只保存在手机上，不会发给 GitHub。导出 JSON 可随时备份或迁移。",
             footnote: "公开仓库监控无需登录 GitHub 账号。"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("跳过") { onFinish() }
                    .font(.subheadline)
                    .padding(.trailing, 20)
                    .padding(.top, 12)
            }
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button {
                if page < pages.count - 1 {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page == pages.count - 1 ? "开始使用" : "下一步")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            Text(item.title)
                .font(.title.weight(.bold))
            Text(item.message)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(item.footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }
}
