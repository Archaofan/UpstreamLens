import SwiftUI

/// 玻璃质感档位。
/// 注意：iOS 26 的 `Glass` 只有 `.regular` / `.clear` / `.identity` 三个值，
/// 没有 thin/thick/prominent；要"更突出"应提高 tint 不透明度，而非寻找不存在的属性。
enum GlassStyle {
    case regular
    case prominent
}

/// 半透明玻璃卡片容器：iOS 26 用原生液态玻璃，以下系统降级为 Material。
/// 玻璃只作容器背景，文字仍由调用方使用语义色，保证可读性不受材质影响。
/// 修饰顺序遵循官方要求：先 padding 布局，最后才 glassEffect。
struct GlassCard<Content: View>: View {
    var style: GlassStyle = .regular
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    init(style: GlassStyle = .regular,
         cornerRadius: CGFloat = 16,
         padding: CGFloat = 16,
         @ViewBuilder content: () -> Content) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            glassContent
        } else {
            materialContent
        }
    }

    @available(iOS 26.0, *)
    private var glassContent: some View {
        content
            .padding(padding)
            .glassEffect(glassValue, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var materialContent: some View {
        content
            .padding(padding)
            .background(materialValue, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @available(iOS 26.0, *)
    private var glassValue: Glass {
        switch style {
        case .regular: return .regular
        // 官方建议：强调感来自 tint 不透明度，不存在 .prominent 这样的属性。
        case .prominent: return .regular.tint(Color.primary.opacity(0.12))
        }
    }

    private var materialValue: Material {
        switch style {
        case .regular: return .ultraThinMaterial
        case .prominent: return .regularMaterial
        }
    }
}

extension View {
    /// 便捷修饰符：把任意视图包进玻璃卡片。
    func glassCard(_ style: GlassStyle = .regular,
                   cornerRadius: CGFloat = 16,
                   padding: CGFloat = 16) -> some View {
        GlassCard(style: style, cornerRadius: cornerRadius, padding: padding) { self }
    }
}
