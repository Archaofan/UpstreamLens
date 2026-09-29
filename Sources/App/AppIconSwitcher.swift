import SwiftUI
import UIKit

enum AppIconSwitchError: LocalizedError {
    case notSupported
    case systemFailure(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return AppLocalization.string("This device does not support alternate app icons.")
        case .systemFailure(let message):
            return message
        }
    }
}

/// 真正调用系统切换 App 图标。放在 App 目标而不是 Shared：
/// `UIApplication.shared` 在 Widget 扩展中不可用。
enum AppIconSwitcher {
    /// 应用图标选择；失败时抛错，由调用方回滚本地状态。
    @MainActor
    static func apply(_ option: AppIconOption) async throws {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { throw AppIconSwitchError.notSupported }
        guard app.alternateIconName != option.alternateName else { return }

        // 显式标注 Void：闭包体里只有 resume()，Swift 推不出 T。
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            app.setAlternateIconName(option.alternateName) { error in
                if let error {
                    continuation.resume(throwing: AppIconSwitchError.systemFailure(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
