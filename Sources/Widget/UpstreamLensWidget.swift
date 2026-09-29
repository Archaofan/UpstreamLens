import SwiftUI
import WidgetKit

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct SnapshotProvider: TimelineProvider {
    private static func read() -> WidgetSnapshot? {
        // 与主 App 相同的组解析：侧载重签后组名可能带团队前缀，固定字符串会拿不到容器。
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupResolver.activeGroupID),
              let data = try? Data(contentsOf: container.appendingPathComponent("widget-snapshot.json")) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: Self.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let entry = SnapshotEntry(date: now, snapshot: Self.read())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

private struct SnapshotView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            case .accessoryCircular:
                circularAccessory
            case .accessoryInline:
                inlineAccessory
            case .accessoryRectangular:
                rectangularAccessory
            default:
                smallLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                // 极淡的品牌色渐变，与 App 图标同一青色系；纯语义色叠加。
                LinearGradient(colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .widgetURL(URL(string: "upstreamlens://findings"))
    }

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var strings: [String: String] { WidgetStrings.table(snapshot?.language ?? "en") }
    private func s(_ key: String, _ fallback: String) -> String { strings[key] ?? fallback }

    /// 2×2：计数为主角，配 ≤2 行短标题与检查时间，避免标题被截成省略号。
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let snapshot {
                countLine
                    .padding(.top, 2)
                headlineText(for: snapshot, lineLimit: 2)
                Spacer(minLength: 0)
                checkedText(for: snapshot)
            } else {
                unavailableText
                Spacer(minLength: 0)
            }
        }
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            if let snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    countLine
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                    checkedText(for: snapshot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(s("latest", "Latest to review"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    headlineText(for: snapshot, lineLimit: 3)
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                unavailableText
                Spacer(minLength: 0)
            }
        }
    }

    private var circularAccessory: some View {
        VStack(spacing: 2) {
            Image(systemName: pendingCount == 0 ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                .font(.caption2)
            Text("\(pendingCount)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(s("circular", "to review"))
                .font(.system(size: 9))
        }
    }

    private var inlineAccessory: some View {
        Label(pendingCount == 0
              ? s("inlineNone", "UpstreamLens: none to review")
              : String(format: s("inlinePending", "UpstreamLens: %@ to review"), "\(pendingCount)"),
              systemImage: "dot.radiowaves.left.and.right")
            .font(.caption)
    }

    private var rectangularAccessory: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                Text("UpstreamLens")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            if let snapshot {
                if let headline = snapshot.headline, pendingCount > 0 {
                    Text(headline)
                        .font(.caption2)
                        .lineLimit(2)
                } else {
                    Text(s("noChanges", "No changes to review"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(checkedLine(for: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(s("unavailable", "Shared data unavailable"))
                    .font(.caption2)
            }
        }
    }

    private var pendingCount: Int { snapshot?.pendingCount ?? 0 }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: entry.date)
    }

    private func checkedLine(for snapshot: WidgetSnapshot) -> String {
        guard let checked = snapshot.lastSuccessfulCheck else { return s("notChecked", "Not checked yet") }
        return String(format: s("checked", "Checked %@"), relative(checked))
    }

    private var header: some View {
        Label("UpstreamLens", systemImage: "dot.radiowaves.left.and.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
    }

    private var countLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(pendingCount)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(s("pending", "to review"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// 相关性着色点：值得关注=橙，其余=品牌色；让“是否要管”一眼可辨。
    private func relevanceDot(_ important: Bool) -> some View {
        Circle()
            .fill(important ? Color.orange : Color.accentColor)
            .frame(width: 8, height: 8)
    }

    /// 超长标题按行数预截断，避免 SwiftUI 在 2×2 上把词切成省略号。
    private func shortHeadline(_ text: String, lineLimit: Int) -> String {
        let max = lineLimit <= 2 ? 48 : 96
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }

    private func headlineText(for snapshot: WidgetSnapshot, lineLimit: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if snapshot.headline != nil {
                relevanceDot(snapshot.headlineRelevance == .important)
                    .padding(.top, 5)
            }
            Group {
                if let headline = snapshot.headline {
                    Text(shortHeadline(headline, lineLimit: lineLimit))
                } else {
                    Text(s("noChanges", "No changes to review"))
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(snapshot.headline == nil ? Color.secondary : Color.primary)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
        }
    }

    private func checkedText(for snapshot: WidgetSnapshot) -> some View {
        Group {
            if let checked = snapshot.lastSuccessfulCheck {
                Text(String(format: s("checked", "Checked %@"), relative(checked)))
            } else {
                Text(s("notChecked", "Not checked yet"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var unavailableText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s("unavailable", "Shared data unavailable")).font(.headline)
            Text(s("unavailableHint", "Open the app to check widget status")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

@main struct UpstreamLensWidget: Widget {
    let kind = "UpstreamLensWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            SnapshotView(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.table("en")["configName"] ?? "Tech Changes")
        .description(WidgetStrings.table("en")["configDescription"] ?? "Shows pending relevant changes and the last check time.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
