import SwiftUI

/// 路径来源的文件内容对照视图：新增行绿色、删除行红色，等宽字体。
struct DiffView: View {
    let old: String?
    let new: String?
    @State private var showAll = false

    private static let collapsedLineLimit = 60

    var body: some View {
        let lines = DiffEngine.lines(old: old, new: new)
        if lines.isEmpty {
            Text("无法生成对照（内容相同或缺失）。").font(.footnote).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                let visible = showAll ? lines : lines.prefix(Self.collapsedLineLimit)
                ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.symbol.rawValue)
                            .font(.system(.footnote, design: .monospaced).weight(.bold))
                            .foregroundStyle(color(for: line.symbol))
                            .frame(width: 14)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(textColor(for: line.symbol))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if lines.count > Self.collapsedLineLimit {
                    Button(showAll ? "收起" : "显示全部 \(lines.count) 行") {
                        withAnimation(.snappy) { showAll.toggle() }
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func color(for symbol: DiffLine.Symbol) -> Color {
        switch symbol {
        case .added: return .green
        case .removed: return .red
        case .same: return .secondary
        }
    }

    private func textColor(for symbol: DiffLine.Symbol) -> Color {
        switch symbol {
        case .added: return .green
        case .removed: return .red
        case .same: return Color.secondary
        }
    }
}
