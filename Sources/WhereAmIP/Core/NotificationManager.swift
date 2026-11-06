import AppKit
import Foundation
@preconcurrency import UserNotifications

/// 负责在出口 IP 发生变化时发送 macOS 系统横幅通知
@MainActor
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()

    /// 当前是否以标准 `.app` 应用包形式运行（`UNUserNotificationCenter` 要求必须有 App Bundle）
    private var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private override init() {
        super.init()
    }

    /// 初始化通知中心并请求通知权限
    public func setup() {
        guard isRunningInAppBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 当出口 IP 发生变化时发送通知
    /// - Parameters:
    ///   - oldInfo: 变化前的 IP 信息
    ///   - newInfo: 变化后的最新 IP 信息
    public func sendIPChangedNotification(from oldInfo: IPInfo, to newInfo: IPInfo) {
        let title: String
        if oldInfo.countryCode != newInfo.countryCode {
            title = "出口归属地已变更: \(oldInfo.flagEmoji) \(oldInfo.countryCode) ➔ \(newInfo.flagEmoji) \(newInfo.localizedCountryName)"
        } else {
            title = "出口 IP 已变更: \(newInfo.flagEmoji) \(newInfo.localizedCountryName) (\(newInfo.countryCode))"
        }

        let subtitle = "新 IP: \(newInfo.ip)（原: \(oldInfo.ip)）"

        var bodyParts: [String] = []
        if let loc = newInfo.locationDetail {
            bodyParts.append(loc)
        }
        if let isp = newInfo.ispDetail {
            bodyParts.append(isp)
        }
        let body = bodyParts.isEmpty ? "数据源: \(newInfo.source)" : bodyParts.joined(separator: " · ")

        deliverNotification(title: title, subtitle: subtitle, body: body)
    }

    /// 内部统一投递方法：优先使用原生 `UNUserNotificationCenter`，若未授权或非 `.app` 环境则回退至 `osascript`
    public func deliverNotification(title: String, subtitle: String, body: String) {
        guard isRunningInAppBundle else {
            deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
            return
        }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                let content = UNMutableNotificationContent()
                content.title = title
                content.subtitle = subtitle
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "com.whereamip.ipchange.\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request) { error in
                    if error != nil {
                        Task { @MainActor in
                            self.deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
                        }
                    }
                }

            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        let content = UNMutableNotificationContent()
                        content.title = title
                        content.subtitle = subtitle
                        content.body = body
                        content.sound = .default
                        let request = UNNotificationRequest(
                            identifier: "com.whereamip.ipchange.\(UUID().uuidString)",
                            content: content,
                            trigger: nil
                        )
                        center.add(request, withCompletionHandler: nil)
                    } else {
                        Task { @MainActor in
                            self.deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
                        }
                    }
                }

            case .denied:
                Task { @MainActor in
                    self.deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
                }

            @unknown default:
                Task { @MainActor in
                    self.deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
                }
            }
        }
    }

    /// AppleScript 兜底通知（确保在命令行直接运行或未授权时也能弹出系统通知）
    private func deliverViaAppleScript(title: String, subtitle: String, body: String) {
        let escapedTitle = escapeForAppleScript(title)
        let escapedSubtitle = escapeForAppleScript(subtitle)
        let escapedBody = escapeForAppleScript(body)

        let script = """
        display notification "\(escapedBody)" with title "\(escapedTitle)" subtitle "\(escapedSubtitle)" sound name "Glass"
        """

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func escapeForAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 确保应用在前台活跃时依然在屏幕右上角弹出横幅通知与提示音
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
