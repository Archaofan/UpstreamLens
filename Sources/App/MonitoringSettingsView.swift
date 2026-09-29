import SwiftUI

/// 监控与刷新子页：GitHub 限额、打开时检查、后台刷新开关与间隔档位。
struct MonitoringSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("refreshCheckOnOpen") private var refreshCheckOnOpen = true
    @AppStorage("refreshBackgroundEnabled") private var refreshBackgroundEnabled = true
    @AppStorage("refreshBackgroundMinutes") private var refreshBackgroundMinutes = RefreshPolicy.defaultMinutes

    var body: some View {
        Form {
            monitoringSection
            rateLimitSection
        }
        .transparentListBackground()
        .navigationTitle("Monitoring & Refresh")
    }

    /// 监控与刷新：打开时是否自动检查、后台刷新开关与间隔档位。
    private var monitoringSection: some View {
        Section {
            Toggle(isOn: $refreshCheckOnOpen) {
                Label("Check for Updates on Open", systemImage: "arrow.clockwise.circle")
            }
            Toggle(isOn: $refreshBackgroundEnabled) {
                Label("Background Refresh", systemImage: "clock.arrow.circlepath")
            }
            if refreshBackgroundEnabled {
                Picker("Interval", selection: $refreshBackgroundMinutes) {
                    ForEach(RefreshPolicy.intervalOptions, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }
            }
        } header: {
            Text("Monitoring & Refresh")
        } footer: {
            Text("Background checks are scheduled by iOS roughly every 30 minutes and are not guaranteed to be real-time.")
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        switch minutes {
        case 15: return AppLocalization.string("15 min")
        case 60: return AppLocalization.string("60 min")
        case 180: return AppLocalization.string("3 hours")
        default: return AppLocalization.string("30 min")
        }
    }

    private var rateLimitSection: some View {
        Section {
            if let rateLimit = model.rateLimit {
                LabeledContent("Remaining This Hour", value: "\(rateLimit.remaining)/\(rateLimit.total == 0 ? 60 : rateLimit.total)")
                LabeledContent("Resets") { Text("in about \(rateLimit.minutesUntilReset) min") }
            } else {
                Text("GitHub API quota is shown after a check completes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("GitHub API Rate Limit")
        } footer: {
            Text("Unauthenticated mode is limited to 60 requests/hour per IP; the search endpoint has a separate limit. Personal notes are never sent to GitHub.")
        }
    }
}
