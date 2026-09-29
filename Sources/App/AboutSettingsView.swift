import SwiftUI

/// 关于与诊断子页：诊断信息生成、版本/开发者/项目主页/分享、简介。
struct AboutSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var diagnosticsText: String?

    private struct DiagnosticsPayload: Identifiable {
        let text: String
        var id: String { text }
    }

    var body: some View {
        Form {
            diagnosticsSection
            aboutSection
        }
        .transparentListBackground()
        .navigationTitle("About")
        .sheet(item: Binding(
            get: { diagnosticsText.map { DiagnosticsPayload(text: $0) } },
            set: { diagnosticsText = $0?.text })) { payload in
            DiagnosticsSheet(text: payload.text)
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button {
                diagnosticsText = model.diagnosticsReport()
            } label: {
                Label("Generate Diagnostics", systemImage: "stethoscope")
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Includes App Group, signing profile, storage, and rate-limit status. If the widget shows “Shared data unavailable”, send the generated text to the developer.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Sources", value: "\(model.sources.count)")
            LabeledContent("Records", value: "\(model.findings.count)")
            LabeledContent("Developer") {
                Link("@Archaofan", destination: Promotion.developerURL)
            }
            LabeledContent("Project Home") {
                Link("GitHub Repository", destination: Promotion.projectURL)
            }
            ShareLink("Recommend UpstreamLens to a friend", item: Promotion.projectURL)
            Text("UpstreamLens is an on-device tech-change radar: it monitors Release, Tag, and path commits of public GitHub repos and gives verifiable judgments based on your locally stored usage.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
