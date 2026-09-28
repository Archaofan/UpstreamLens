import SwiftUI
import UIKit

/// 设置页：数据管理（导入/导出/清理）、GitHub 限额、可复制的诊断信息、关于。
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

    private struct PendingImport: Identifiable {
        let data: Data
        let sourceCount: Int
        let findingCount: Int
        var id: String { "\(sourceCount)-\(findingCount)" }
    }

    var body: some View {
        NavigationStack {
            Form {
                rateLimitSection
                dataSection
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

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: appVersion)
            LabeledContent("来源", value: "\(model.sources.count) 个")
            LabeledContent("记录", value: "\(model.findings.count) 条")
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
