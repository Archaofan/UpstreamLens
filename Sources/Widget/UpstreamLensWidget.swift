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
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "upstreamlens://findings"))
    }

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let snapshot {
                countLine
                    .padding(.top, 2)
                headlineText(for: snapshot)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("最新待查看")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    headlineText(for: snapshot)
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

    private var header: some View {
        Label("UpstreamLens", systemImage: "dot.radiowaves.left.and.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
    }

    private var countLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(snapshot?.pendingCount ?? 0)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text("条待查看")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func headlineText(for snapshot: WidgetSnapshot) -> some View {
        Group {
            if let headline = snapshot.headline {
                Text(headline)
            } else {
                Text("暂无需要关注的新变化")
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(snapshot.headline == nil ? Color.secondary : Color.primary)
        .lineLimit(3)
    }

    private func checkedText(for snapshot: WidgetSnapshot) -> some View {
        Group {
            if let checked = snapshot.lastSuccessfulCheck {
                Text("检查于 \(checked, style: .relative)")
            } else {
                Text("尚未完成检查")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var unavailableText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("共享数据暂不可用").font(.headline)
            Text("请打开 App 检查组件状态").font(.caption).foregroundStyle(.secondary)
        }
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
