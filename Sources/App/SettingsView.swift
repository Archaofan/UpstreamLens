import SwiftUI
import UIKit

/// 设置根页：拆分为通用 / 监控与刷新 / 数据与备份 / 关于与诊断四个子页面。
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { GeneralSettingsView(model: model) } label: {
                        Label("General", systemImage: "gear")
                    }
                    NavigationLink { CategoriesSettingsView(model: model) } label: {
                        Label("Categories", systemImage: "tag")
                    }
                    NavigationLink { MonitoringSettingsView(model: model) } label: {
                        Label("Monitoring & Refresh", systemImage: "arrow.clockwise.circle")
                    }
                    NavigationLink { DataSettingsView(model: model) } label: {
                        Label("Data & Backup", systemImage: "externaldrive")
                    }
                    NavigationLink { AboutSettingsView(model: model) } label: {
                        Label("About & Diagnostics", systemImage: "info.circle")
                    }
                    // 引导不再是"只看一次"：这里可以随时重看。
                    NavigationLink {
                        OnboardingView(onFinish: {}, isReview: true)
                            .navigationTitle("Getting Started")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Getting Started", systemImage: "sparkles")
                    }
                } footer: {
                    Text("UpstreamLens is an on-device tech-change radar: it monitors Release, Tag, and path commits of public GitHub repos and gives verifiable judgments based on your locally stored usage.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
        }
    }
}

/// 诊断信息展示：可全选复制，一键复制按钮。
struct DiagnosticsSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy All") {
                        UIPasteboard.general.string = text
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }
}

/// 推广信息集中一处，换账号只改这里。
enum Promotion {
    static let developerHandle = "@Archaofan"
    static let developerURL = URL(string: "https://github.com/Archaofan")!
    static let projectURL = URL(string: "https://github.com/Archaofan/UpstreamLens")!
}

/// 可全选复制的文本弹窗（AI 提示词等长文本）。
struct CopyableTextSheet: View {
    let title: String
    let text: String
    var footnote: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let footnote {
                        Text(footnote).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy All") {
                        UIPasteboard.general.string = text
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }
}

/// 引导用户创建只读 PAT：步骤 + 直达 GitHub 令牌创建页。
struct TokenHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let createURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("UpstreamLens only reads public info; a read-only token is enough. Grant permissions as needed:")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 12) {
                        step("1", "Open the “Fine-grained personal access token” creation page on GitHub (the button below goes straight there).")
                        step("2", "Permissions needed: Metadata → Read-only, Contents → Read-only. To monitor private repos, add those repos to the token's repository access scope.")
                        step("3", "After generating, copy the token, return to Settings, paste it, and tap “Sign In and Verify”.")
                    }
                    Text("The token is stored only in the local Keychain; it is never uploaded or written into exported backups, and you can revoke it anytime via “Sign Out” in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: createURL) {
                        Label("Open GitHub Token Creation Page", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("How to Create a Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text).font(.subheadline)
        }
    }
}
