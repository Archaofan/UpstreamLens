import SwiftUI
import UIKit

/// 设置页：数据管理（导入/导出/清理）、AI 来源清单、GitHub 限额、可复制的诊断信息、关于。
/// 低频功能集中在这里，首页保持清爽。
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var backup: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: PendingImport?
    @State private var dialogError: String?
    @State private var diagnosticsText: String?
    @State private var confirmClearHandled = false
    @State private var showAiPrompt = false
    @State private var showSourceListImporter = false
    @State private var pendingSourceList: PendingSourceListImport?
    @State private var importResultMessage: String?
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var notificationAuthStatus = "未查询"

    private struct PendingImport: Identifiable {
        let data: Data
        let sourceCount: Int
        let findingCount: Int
        var id: String { "\(sourceCount)-\(findingCount)" }
    }

    private struct PendingSourceListImport: Identifiable {
        let sources: [WatchSource]
        let warnings: [String]
        var id: Int { sources.count }
    }

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                rateLimitSection
                dataSection
                helpSection
                diagnosticsSection
                aboutSection
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .fileExporter(isPresented: $showExporter, document: backup, contentType: .json,
                          defaultFilename: "UpstreamLens-backup") { result in
                if case .failure(let error) = result { dialogError = error.localizedDescription }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .fileImporter(isPresented: $showSourceListImporter, allowedContentTypes: [.json]) { result in
                handleSourceListImport(result)
            }
            .sheet(isPresented: $showAiPrompt) {
                CopyableTextSheet(
                    title: "AI 检索提示词",
                    text: SourceListImport.prompt,
                    footnote: "复制给能访问你电脑/服务器的 AI（如 Agent CLI、IDE 助手）；它返回的 JSON 存为 .json 文件后，用“导入 AI 来源清单”加入监控。")
            }
            .confirmationDialog("替换现有数据？", isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } })) {
                Button("替换现有数据", role: .destructive) {
                    guard let pendingImport else { return }
                    do { try model.importData(pendingImport.data) }
                    catch { dialogError = "导入失败：\(error.localizedDescription)" }
                    self.pendingImport = nil
                }
                Button("取消", role: .cancel) { pendingImport = nil }
            } message: {
                if let pendingImport {
                    Text("备份中包含 \(pendingImport.sourceCount) 个来源、\(pendingImport.findingCount) 条记录，导入后将替换现有的 \(model.sources.count) 个来源。")
                }
            }
            .confirmationDialog("合并导入来源清单？", isPresented: Binding(
                get: { pendingSourceList != nil },
                set: { if !$0 { pendingSourceList = nil } })) {
                Button("合并导入") {
                    guard let pending = pendingSourceList else { return }
                    let result = model.mergeSourceList(pending.sources)
                    var lines = ["已新增 \(result.added) 个来源，跳过 \(result.skipped) 个重复项。"]
                    lines.append(contentsOf: pending.warnings)
                    importResultMessage = lines.joined(separator: "\n")
                    self.pendingSourceList = nil
                    Task { await model.refreshAll() }
                }
                Button("取消", role: .cancel) { pendingSourceList = nil }
            } message: {
                if let pending = pendingSourceList {
                    Text("清单包含 \(pending.sources.count) 个来源，将合并到现有的 \(model.sources.count) 个：已有来源不会被修改或删除，重复仓库自动跳过。导入后立即检查一轮。")
                }
            }
            .alert("导入完成", isPresented: Binding(
                get: { importResultMessage != nil },
                set: { if !$0 { importResultMessage = nil } })) {
                Button("确定", role: .cancel) { importResultMessage = nil }
            } message: { Text(importResultMessage ?? "") }
            .alert("清理已处理记录？", isPresented: $confirmClearHandled) {
                Button("清理", role: .destructive) { model.clearHandledRecords() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已处理记录会被永久删除。如需保留，请先导出 JSON 备份。")
            }
            .alert("操作失败", isPresented: Binding(get: { dialogError != nil }, set: { if !$0 { dialogError = nil } })) {
                Button("确定", role: .cancel) { dialogError = nil }
            } message: { Text(dialogError ?? "") }
            .sheet(item: Binding(
                get: { diagnosticsText.map { DiagnosticsPayload(text: $0) } },
                set: { diagnosticsText = $0?.text })) { payload in
                DiagnosticsSheet(text: payload.text)
            }
        }
    }

    private struct DiagnosticsPayload: Identifiable {
        let text: String
        var id: String { text }
    }

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("新变化通知", systemImage: "bell.badge")
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
                LabeledContent("系统授权状态", value: notificationAuthStatus)
            }
        } header: {
            Text("通知")
        } footer: {
            Text("只通知“值得关注”与“影响不确定”的相关变化（每个来源可单独关闭）。“值得关注”会横幅提醒，其余静默进入通知中心；是否打断由系统的专注模式决定。后台检查由 iOS 调度，约每 30 分钟起，不能保证实时。")
        }
    }

    private func authText(_ scheduler: NotificationScheduler) async -> String {
        switch await scheduler.authorizationStatus() {
        case .authorized, .provisional: return "已授权"
        case .denied: return "已被拒绝（请到系统设置开启）"
        case .notDetermined: return "待确认"
        @unknown default: return "未知"
        }
    }

    private var rateLimitSection: some View {
        Section {
            if let rateLimit = model.rateLimit {
                LabeledContent("本小时剩余额度", value: "\(rateLimit.remaining)/\(rateLimit.total == 0 ? 60 : rateLimit.total)")
                LabeledContent("重置") { Text("约 \(rateLimit.minutesUntilReset) 分钟后") }
            } else {
                Text("完成一次检查后显示 GitHub API 剩余额度。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("GitHub API 限额")
        } footer: {
            Text("未登录模式每 IP 每小时 60 次；搜索接口独立限额。个人备注不会发给 GitHub。")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                do { backup = BackupDocument(data: try model.exportData()); showExporter = true }
                catch { dialogError = error.localizedDescription }
            } label: {
                Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("导入 JSON 备份（替换现有数据）", systemImage: "square.and.arrow.down")
            }
            Toggle(isOn: Binding(
                get: { (model.retentionDays ?? 0) > 0 },
                set: { model.setRetentionDays($0 ? 90 : 0) })) {
                Label("自动清理 90 天前的已处理记录", systemImage: "clock.arrow.circlepath")
            }
            let handledCount = model.findings.filter { $0.status == .handled }.count
            Button(role: .destructive) {
                confirmClearHandled = true
            } label: {
                Label(handledCount == 0 ? "暂无已处理记录" : "立即清空已处理记录（\(handledCount)）",
                      systemImage: "trash")
            }
            .disabled(handledCount == 0 || !model.canEditData)
        } header: {
            Text("数据")
        } footer: {
            Text("导出备份会包含个人使用信息；导入会替换全部现有数据。")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button {
                diagnosticsText = model.diagnosticsReport()
            } label: {
                Label("生成诊断信息", systemImage: "stethoscope")
            }
        } header: {
            Text("诊断")
        } footer: {
            Text("包含 App Group、签名 profile、存储与限额状态。小组件显示“共享数据暂不可用”时，请把生成的文本发给开发者。")
        }
    }

    private var helpSection: some View {
        Section {
            Button {
                showAiPrompt = true
            } label: {
                Label("AI 检索提示词（一键复制）", systemImage: "doc.text.viewfinder")
            }
            Button {
                showSourceListImporter = true
            } label: {
                Label("导入 AI 来源清单（合并到现有来源）", systemImage: "sparkles.rectangle.stack")
            }
        } header: {
            Text("帮助 · 用 AI 批量添加来源")
        } footer: {
            Text("把提示词复制给能访问本机的 AI，它会检索你在用的开源项目并输出 JSON 清单；清单保存为 .json 后从这里导入，App 会合并新增来源并立即检查。不会覆盖或修改已有来源。")
        }
    }

    private func handleSourceListImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bytes = try Data(contentsOf: url)
            let parsed = try SourceListImport.parse(bytes)
            pendingSourceList = PendingSourceListImport(sources: parsed.sources, warnings: parsed.warnings)
        } catch {
            dialogError = "来源清单导入失败：\(error.localizedDescription)"
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: appVersion)
            LabeledContent("来源", value: "\(model.sources.count) 个")
            LabeledContent("记录", value: "\(model.findings.count) 条")
            LabeledContent("开发者") {
                Link("@Archaofan", destination: Promotion.developerURL)
            }
            LabeledContent("项目主页") {
                Link("GitHub 仓库", destination: Promotion.projectURL)
            }
            ShareLink("把 UpstreamLens 推荐给朋友", item: Promotion.projectURL)
            Text("UpstreamLens 是本机使用的技术变化雷达：监控公开 GitHub 仓库的 Release、Tag 与指定路径的提交，结合本机保存的用途给出可核查的判断。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bytes = try Data(contentsOf: url)
            let imported = try LocalStore.importData(bytes)
            pendingImport = PendingImport(data: bytes, sourceCount: imported.sources.count,
                                          findingCount: imported.findings.count)
        } catch {
            dialogError = "导入失败：\(error.localizedDescription)"
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
            .navigationTitle("诊断信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制全部") {
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
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制全部") {
                        UIPasteboard.general.string = text
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }
}
