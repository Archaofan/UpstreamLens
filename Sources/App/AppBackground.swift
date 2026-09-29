import SwiftUI
import UIKit

/// 全局页面背景偏好（仅本机，**不进导出备份、不进诊断**）。
enum BackgroundPreferences {
    static let enabledKey = "bgEnabled"
    static let opacityKey = "bgOpacity"
    static let brightnessKey = "bgBrightness"
    /// 是否让列表/表单透出背景。旧实现漏了这一环，导致图片永远被不透明列表盖住。
    static let dimmingKey = "bgContentDimming"

    /// 透明度下限 0.15：保证内容可读性不被用户调到几乎不可读。
    static let opacityRange: ClosedRange<Double> = 0.15...1.0
    static let brightnessRange: ClosedRange<Double> = -0.35...0.35
    static let defaultOpacity = 0.55
    static let defaultBrightness = 0.0
    /// 背景之上、内容之下的一层压暗/提亮，保证文字始终可读。
    static let dimmingRange: ClosedRange<Double> = 0.0...0.6
    static let defaultDimming = 0.18

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func opacity(_ defaults: UserDefaults = .standard) -> Double {
        clamp(defaults.object(forKey: opacityKey) as? Double ?? defaultOpacity, opacityRange)
    }

    static func brightness(_ defaults: UserDefaults = .standard) -> Double {
        clamp(defaults.object(forKey: brightnessKey) as? Double ?? defaultBrightness, brightnessRange)
    }

    static func dimming(_ defaults: UserDefaults = .standard) -> Double {
        clamp(defaults.object(forKey: dimmingKey) as? Double ?? defaultDimming, dimmingRange)
    }
}

enum BackgroundError: LocalizedError {
    case noContainer
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .noContainer: return "Shared container is unavailable."
        case .encodeFailed: return "The image could not be encoded."
        }
    }
}

/// 背景图存储：优先 App Group 容器（重装/清缓存不易丢），退化到沙盒 Documents。
enum BackgroundImageStore {
    /// 候选目录按优先级排列：App Group → 沙盒 Documents。
    private static var candidateDirectories: [URL] {
        var dirs: [URL] = []
        if let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupResolver.activeGroupID) {
            dirs.append(group.appendingPathComponent("background", isDirectory: true))
        }
        if let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true) {
            dirs.append(docs.appendingPathComponent("background", isDirectory: true))
        }
        return dirs
    }

    /// 读取时用"第一个真正存在文件的目录"，写入时用第一个目录。
    static var existingFileURL: URL? {
        for dir in candidateDirectories {
            let url = dir.appendingPathComponent("current.jpg")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static var writeFileURL: URL? {
        candidateDirectories.first?.appendingPathComponent("current.jpg")
    }

    /// 兼容旧调用点。
    static var fileURL: URL? { existingFileURL }

    static func save(_ image: UIImage) throws {
        let scaled = image.scaledLongestEdge(2048)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { throw BackgroundError.encodeFailed }
        var lastError: Error?
        for dir in candidateDirectories {
            let url = dir.appendingPathComponent("current.jpg")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BackgroundError.noContainer
    }

    static func load() -> UIImage? {
        guard let url = existingFileURL,
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    static func remove() {
        for dir in candidateDirectories {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("current.jpg"))
        }
    }

    static var byteSize: Int {
        guard let url = existingFileURL,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return values.fileSize ?? 0
    }
}

/// 背景图的可观察单例。
///
/// 修掉旧实现的两个致命缺陷：
/// 1. 旧实现把图片只放进 static 缓存，`AppBackgroundModifier` 的 `@State` 不会刷新，
///    于是"选完图片完全没反应"——这里是 `@Published`，选完立即生效；
/// 2. 旧实现只在 `enabled` 变化时重载，选图不触发任何刷新。
///
/// 刻意**不加** `@MainActor`：View 的属性初始化器是非隔离上下文，
/// 引用 `@MainActor` 的 static shared 会编译失败。所有调用点都在主线程。
final class BackgroundStore: ObservableObject {
    static let shared = BackgroundStore()

    @Published private(set) var image: UIImage?
    /// 每次内容变化自增，供 `.id()` / onChange 感知。
    @Published private(set) var generation = 0

    private init() {
        image = BackgroundImageStore.load()
    }

    func reload() {
        image = BackgroundImageStore.load()
        generation += 1
    }

    func setImage(_ image: UIImage) throws {
        try BackgroundImageStore.save(image)
        self.image = BackgroundImageStore.load() ?? image
        generation += 1
    }

    func clear() {
        BackgroundImageStore.remove()
        image = nil
        generation += 1
    }
}

extension UIImage {
    /// 按最长边等比缩放，避免放大。
    func scaledLongestEdge(_ maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return self }
        let ratio = maxEdge / longest
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// 全局背景：关闭时铺 systemGroupedBackground，与改动前一致（零视觉回归）；
/// 开启后叠加用户图片，透明度与亮度按偏好钳制，再压一层保证可读性。
///
/// 关键：这里只是"最底层"。要让图片真正可见，各级 List/Form 必须
/// `.scrollContentBackground(.hidden)`（见 `View.transparentListBackground()`）。
struct AppBackgroundModifier: ViewModifier {
    @ObservedObject private var store = BackgroundStore.shared
    @AppStorage(BackgroundPreferences.enabledKey) private var enabled = false
    @AppStorage(BackgroundPreferences.opacityKey) private var opacity = BackgroundPreferences.defaultOpacity
    @AppStorage(BackgroundPreferences.brightnessKey) private var brightness = BackgroundPreferences.defaultBrightness
    @AppStorage(BackgroundPreferences.dimmingKey) private var dimming = BackgroundPreferences.defaultDimming

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                    if enabled, let image = store.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .opacity(BackgroundPreferences.clamp(opacity, BackgroundPreferences.opacityRange))
                            .brightness(BackgroundPreferences.clamp(brightness, BackgroundPreferences.brightnessRange))
                        // 可读性压层：深色模式压黑、浅色模式压白，避免花哨图片吃掉文字对比度。
                        Color(uiColor: .systemGroupedBackground)
                            .opacity(BackgroundPreferences.clamp(dimming, BackgroundPreferences.dimmingRange))
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear { store.reload() }
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackgroundModifier()) }

    /// 让 List/Form 透出全局背景。所有顶层列表容器都必须调用，
    /// 否则系统分组底色会把用户背景图整块盖住。
    func transparentListBackground() -> some View {
        scrollContentBackground(.hidden)
    }
}

/// 系统相册选择器：用 UIKit 桥接而非 PhotosUI，避免为一张背景图额外链接框架。
/// 采用标准 Coordinator 模式（回调自持，不反向引用父视图）。
/// 需在 Info.plist 声明 NSPhotoLibraryUsageDescription。
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    /// 选中图片回调；取消或未取到图片时传 nil，由调用方自行收起了。
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void

        init(onPicked: @escaping (UIImage?) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            onPicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPicked(nil)
        }
    }
}
