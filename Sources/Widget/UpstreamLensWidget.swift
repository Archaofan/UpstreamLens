import SwiftUI
import WidgetKit

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct SnapshotProvider: TimelineProvider {
    private static func read() -> WidgetSnapshot? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.upstreamlens.ios"),
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
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("UpstreamLens", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            if let snapshot = entry.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(snapshot.pendingCount)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("条待查看")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let headline = snapshot.headline {
                    Text(headline).font(.subheadline.weight(.medium)).lineLimit(2)
                } else {
                    Text("暂无需要关注的新变化")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let checked = snapshot.lastSuccessfulCheck {
                    Text("检查于 \(checked, style: .relative)")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("尚未完成检查").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("共享数据暂不可用").font(.headline)
                Text("请打开 App 检查组件状态").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "upstreamlens://findings"))
    }
}

@main struct UpstreamLensWidget: Widget {
    let kind = "UpstreamLensWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            SnapshotView(entry: entry)
        }
        .configurationDisplayName("技术变化")
        .description("显示待查看的相关变化与上次检查时间。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
